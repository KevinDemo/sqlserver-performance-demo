// Runs each scenario's before.sql and after.sql and records what actually happened:
// elapsed time on the client, CPU from the session DMV, and logical reads from STATISTICS IO.
// Each measured statement runs once to warm the cache, then N more times; the median is reported.
// Before and after must return the same rows, otherwise the run fails.
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Data.SqlClient;

var root = FindRepoRoot();
var connectionString = Environment.GetEnvironmentVariable("HARBOUR_CONNECTION")
    ?? @"Server=(localdb)\MSSQLLocalDB;Database=HarbourDemo;Integrated Security=true;TrustServerCertificate=true;Connect Timeout=60";
const int Repetitions = 7;

var resultsDir = Path.Combine(root, "results");
var plansDir = Path.Combine(resultsDir, "plans");
Directory.CreateDirectory(plansDir);

await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();
var messages = new StringBuilder();
connection.InfoMessage += (_, e) => messages.AppendLine(e.Message);

var rows = new List<Row>();
var scenarioDirs = Directory.GetDirectories(Path.Combine(root, "scenarios")).Order().ToArray();

// A fix left behind by an earlier run would change the "before" numbers of other scenarios.
foreach (var scenarioDir in scenarioDirs) await Cleanup(scenarioDir);

foreach (var scenarioDir in scenarioDirs)
{
    var name = Path.GetFileName(scenarioDir);
    if (name.Contains("deadlock")) continue; // has its own concurrent repro, see scenarios/05-deadlock

    var before = await RunScript(Path.Combine(scenarioDir, "before.sql"), name, "before");
    var after = await RunScript(Path.Combine(scenarioDir, "after.sql"), name, "after");
    await Cleanup(scenarioDir);
    if (before.Count != after.Count) throw new InvalidOperationException($"{name}: measure count differs");

    for (var i = 0; i < before.Count; i++)
    {
        var (b, a) = (before[i], after[i]);
        if (b.RowCount != a.RowCount || b.ResultHash != a.ResultHash)
            throw new InvalidOperationException($"{name} / {b.Label}: before and after returned different rows");
        rows.Add(new Row(name, b.Label, b, a));
        Console.WriteLine($"{name} / {b.Label}: reads {b.LogicalReads:N0} -> {a.LogicalReads:N0}, " +
                          $"elapsed {b.ElapsedMs:N1} -> {a.ElapsedMs:N1} ms, rows {b.RowCount:N0}");
    }
}

var version = await Scalar("SELECT @@VERSION");
var firstLine = version.Split('\n')[0].Trim();
await File.WriteAllTextAsync(Path.Combine(resultsDir, "results.json"),
    JsonSerializer.Serialize(new { RunUtc = DateTime.UtcNow, Server = firstLine, Repetitions, Rows = rows },
        new JsonSerializerOptions { WriteIndented = true }));
await File.WriteAllTextAsync(Path.Combine(resultsDir, "results.md"), ToMarkdown(rows, firstLine));
Console.WriteLine("Wrote results/results.md and results/results.json");
return;

async Task Cleanup(string scenarioDir)
{
    var path = Path.Combine(scenarioDir, "cleanup.sql");
    if (File.Exists(path)) await Execute(await File.ReadAllTextAsync(path));
}

async Task<List<Measure>> RunScript(string path, string scenario, string phase)
{
    var measures = new List<Measure>();
    foreach (var section in ParseSections(await File.ReadAllTextAsync(path)))
    {
        if (section.Label is null)
        {
            foreach (var batch in SplitBatches(section.Sql)) await Execute(batch);
            continue;
        }

        await Execute("SET STATISTICS IO ON;");
        await Measure(section.Sql); // warm-up run, not recorded
        var runs = new List<Sample>();
        for (var i = 0; i < Repetitions; i++) runs.Add(await Measure(section.Sql));
        await Execute("SET STATISTICS IO OFF;");

        var planFile = $"{scenario}-{phase}-{measures.Count + 1}.sqlplan";
        var plan = await CapturePlan(section.Sql, Path.Combine(plansDir, planFile));
        var last = runs[^1];
        measures.Add(new Measure(section.Label, Median(runs.Select(r => r.ElapsedMs)), Median(runs.Select(r => r.CpuMs)),
            runs.Max(r => r.LogicalReads) == runs.Min(r => r.LogicalReads) ? last.LogicalReads : (long)Median(runs.Select(r => (double)r.LogicalReads)),
            last.RowCount, last.ResultHash, plan));
    }
    return measures;
}

async Task<Sample> Measure(string sql)
{
    var cpuBefore = await SessionCpu();
    messages.Clear();
    var clock = Stopwatch.StartNew();
    await using var command = new SqlCommand(sql, connection) { CommandTimeout = 300 };
    await using var reader = await command.ExecuteReaderAsync();
    long rowCount = 0;
    long hash = 0;
    do
    {
        while (await reader.ReadAsync())
        {
            rowCount++;
            var line = new StringBuilder();
            for (var c = 0; c < reader.FieldCount; c++)
                line.Append(Convert.ToString(reader.GetValue(c), CultureInfo.InvariantCulture)).Append('|');
            // Order-independent, so a different row order alone is not reported as a different answer.
            hash = unchecked(hash + StableHash(line.ToString()));
        }
    } while (await reader.NextResultAsync());
    await reader.CloseAsync();
    clock.Stop();
    var cpu = await SessionCpu() - cpuBefore;
    var reads = Regex.Matches(messages.ToString(), @"logical reads (\d+)").Sum(m => long.Parse(m.Groups[1].Value));
    return new Sample(clock.Elapsed.TotalMilliseconds, cpu, reads, rowCount, hash);
}

async Task<string> CapturePlan(string sql, string file)
{
    await Execute("SET STATISTICS XML ON;");
    await using var command = new SqlCommand(sql, connection) { CommandTimeout = 300 };
    var operators = new List<string>();
    string? xml = null;
    await using (var reader = await command.ExecuteReaderAsync())
    {
        do
        {
            var isPlan = reader.FieldCount == 1 && reader.GetName(0).Contains("Showplan", StringComparison.OrdinalIgnoreCase);
            while (await reader.ReadAsync())
                if (isPlan) xml = reader.GetString(0);
        } while (await reader.NextResultAsync());
    }
    await Execute("SET STATISTICS XML OFF;");
    if (xml is null) return "(no plan)";

    await File.WriteAllTextAsync(file, xml);
    XNamespace ns = "http://schemas.microsoft.com/sqlserver/2004/07/showplan";
    foreach (var op in XDocument.Parse(xml).Descendants(ns + "RelOp"))
    {
        var name = op.Attribute("PhysicalOp")!.Value;
        if (name is not ("Index Seek" or "Index Scan" or "Clustered Index Seek" or "Clustered Index Scan" or "Sort" or "Table Scan")) continue;
        var isLookup = op.Elements().SelectMany(e => e.Attributes("Lookup")).Any(a => a.Value == "1" || a.Value == "true");
        var index = op.Elements().Elements(ns + "Object").Attributes("Index").FirstOrDefault()?.Value.Trim('[', ']');
        operators.Add(isLookup ? $"Key Lookup {index}" : index is null ? name : $"{name} {index}");
    }
    return string.Join(" + ", operators.Distinct());
}

async Task Execute(string sql)
{
    await using var command = new SqlCommand(sql, connection) { CommandTimeout = 300 };
    await using var reader = await command.ExecuteReaderAsync();
    do { while (await reader.ReadAsync()) { } } while (await reader.NextResultAsync());
}

async Task<double> SessionCpu() => double.Parse(await Scalar("SELECT cpu_time FROM sys.dm_exec_sessions WHERE session_id = @@SPID"));

async Task<string> Scalar(string sql)
{
    await using var command = new SqlCommand(sql, connection);
    return Convert.ToString(await command.ExecuteScalarAsync(), CultureInfo.InvariantCulture)!;
}

static long StableHash(string text)
{
    var hash = 1125899906842597L;
    foreach (var ch in text) hash = unchecked(31 * hash + ch);
    return hash;
}

static double Median(IEnumerable<double> values)
{
    var sorted = values.Order().ToArray();
    return sorted.Length % 2 == 1 ? sorted[sorted.Length / 2] : (sorted[sorted.Length / 2 - 1] + sorted[sorted.Length / 2]) / 2;
}

// Splits a script on "-- BENCH:MEASURE <label>" and "-- BENCH:PREP" lines.
// Text before the first marker and after BENCH:PREP is setup; a MEASURE section is one measured batch.
static IEnumerable<Section> ParseSections(string script)
{
    string? label = null;
    var buffer = new StringBuilder();
    foreach (var line in script.Split('\n'))
    {
        var marker = Regex.Match(line, @"^\s*--\s*BENCH:(MEASURE\s+(?<label>.+?)|PREP)\s*$");
        if (!marker.Success) { buffer.AppendLine(line.TrimEnd('\r')); continue; }
        yield return new Section(label, buffer.ToString());
        buffer.Clear();
        label = marker.Groups["label"].Success ? marker.Groups["label"].Value : null;
    }
    yield return new Section(label, buffer.ToString());
}

static IEnumerable<string> SplitBatches(string sql) =>
    Regex.Split(sql, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase)
         .Where(b => Regex.Replace(b, @"--.*$", "", RegexOptions.Multiline).Trim().Length > 0);

static string FindRepoRoot()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "scenarios"))) dir = dir.Parent;
    return dir?.FullName ?? throw new InvalidOperationException("Could not find the scenarios folder");
}

static string ToMarkdown(List<Row> rows, string server)
{
    var md = new StringBuilder();
    md.AppendLine($"Server: {server}. Run: {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC. Median of {Repetitions} runs with a warm cache.");
    md.AppendLine();
    md.AppendLine("| Scenario | Case | Rows | Logical reads before | Logical reads after | Elapsed before (ms) | Elapsed after (ms) | CPU before (ms) | CPU after (ms) |");
    md.AppendLine("|---|---|--:|--:|--:|--:|--:|--:|--:|");
    foreach (var r in rows)
        md.AppendLine($"| {r.Scenario} | {r.Case} | {r.Before.RowCount:N0} | {r.Before.LogicalReads:N0} | {r.After.LogicalReads:N0} | " +
                      $"{r.Before.ElapsedMs:N1} | {r.After.ElapsedMs:N1} | {r.Before.CpuMs:N0} | {r.After.CpuMs:N0} |");
    md.AppendLine();
    md.AppendLine("| Scenario | Case | Plan before | Plan after |");
    md.AppendLine("|---|---|---|---|");
    foreach (var r in rows) md.AppendLine($"| {r.Scenario} | {r.Case} | {r.Before.Plan} | {r.After.Plan} |");
    return md.ToString();
}

record Section(string? Label, string Sql);
record Sample(double ElapsedMs, double CpuMs, long LogicalReads, long RowCount, long ResultHash);
record Measure(string Label, double ElapsedMs, double CpuMs, long LogicalReads, long RowCount, long ResultHash, string Plan);
record Row(string Scenario, string Case, Measure Before, Measure After);
