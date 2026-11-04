// Two concurrent batches over the same jobs, run three ways:
//   before      opposite lock order, one big transaction per round, no retry
//   retry-only  opposite lock order, one big transaction per round, retry on deadlock
//   fixed       consistent lock order (after.sql), short batches, retry still armed
// After each mode the rows are checked: both batches must have stamped every row in the range.
using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

var connectionString = Environment.GetEnvironmentVariable("HARBOUR_CONNECTION")
    ?? @"Server=(localdb)\MSSQLLocalDB;Database=HarbourDemo;Integrated Security=true;TrustServerCertificate=true;Connect Timeout=60";

const int Rounds = 20;
const int JobsPerRound = 2000;
const int BatchSize = 200;
const int FirstJobId = 300_001; // well away from the dates the other scenarios read
const double WorkMsPerJob = 0.1; // same work per job in every mode, so elapsed times compare fairly

var root = FindRepoRoot();
var scenario = Path.Combine(root, "scenarios", "05-deadlock");

var results = new List<ModeResult>
{
    await RunMode("before", "before.sql", JobsPerRound, retry: false),
    await RunMode("retry-only", "before.sql", JobsPerRound, retry: true),
    await RunMode("fixed", "after.sql", BatchSize, retry: true),
};

var md = new StringBuilder();
md.AppendLine($"{Rounds} rounds of {JobsPerRound:N0} jobs, two concurrent batches per round, {Rounds * JobsPerRound:N0} jobs in total. Run: {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC.");
md.AppendLine();
md.AppendLine("| Mode | Deadlocks (error 1205) | Retries | Batches that gave up | Jobs fully processed | Jobs expected | Elapsed (s) |");
md.AppendLine("|---|--:|--:|--:|--:|--:|--:|");
foreach (var r in results)
    md.AppendLine($"| {r.Mode} | {r.Deadlocks:N0} | {r.Retries:N0} | {r.GaveUp:N0} | {r.JobsComplete:N0} | {Rounds * JobsPerRound:N0} | {r.ElapsedSeconds:N1} |");
var text = md.ToString();
Console.WriteLine(text);
await File.WriteAllTextAsync(Path.Combine(root, "results", "deadlock.md"), text);
return;

async Task<ModeResult> RunMode(string mode, string script, int batchSize, bool retry)
{
    await ApplyScript(Path.Combine(scenario, script));

    // A stamp unique to this run, so rows left over from an earlier mode do not count.
    var stamp = await NewStamp();
    int deadlocks = 0, retries = 0, gaveUp = 0;
    var clock = Stopwatch.StartNew();

    for (var round = 0; round < Rounds; round++)
    {
        var from = FirstJobId + round * JobsPerRound;
        var to = from + JobsPerRound - 1;
        await Task.WhenAll(Worker("dbo.RateJobs"), Worker("dbo.ImportPods"));

        // Each batch walks the round's range in its own transactions.
        async Task Worker(string procedure)
        {
            for (var start = from; start <= to; start += batchSize)
            {
                var end = Math.Min(start + batchSize - 1, to);
                var workMs = Math.Max(1, (int)(WorkMsPerJob * (end - start + 1)));
                for (var attempt = 1; ; attempt++)
                {
                    try
                    {
                        await CallBatch(procedure, start, end, stamp, workMs);
                        break;
                    }
                    catch (SqlException ex) when (ex.Number == 1205)
                    {
                        Interlocked.Increment(ref deadlocks);
                        if (!retry || attempt == 5)
                        {
                            Interlocked.Increment(ref gaveUp);
                            break; // this batch's work is rolled back and lost
                        }
                        Interlocked.Increment(ref retries);
                        await Task.Delay(50 * attempt + Random.Shared.Next(50));
                    }
                }
            }
        }
    }
    clock.Stop();

    var complete = await CountComplete(stamp);
    Console.WriteLine($"{mode}: deadlocks={deadlocks} retries={retries} gaveUp={gaveUp} complete={complete} elapsed={clock.Elapsed.TotalSeconds:N1}s");
    return new ModeResult(mode, deadlocks, retries, gaveUp, complete, clock.Elapsed.TotalSeconds);
}

async Task CallBatch(string procedure, int from, int to, DateTime stamp, int workMs)
{
    // A new connection per call, as a batch service with pooling would do.
    await using var connection = new SqlConnection(connectionString);
    await connection.OpenAsync();
    await using var command = new SqlCommand(procedure, connection) { CommandType = System.Data.CommandType.StoredProcedure, CommandTimeout = 120 };
    command.Parameters.AddWithValue("@FromJobId", from);
    command.Parameters.AddWithValue("@ToJobId", to);
    command.Parameters.Add("@Stamp", System.Data.SqlDbType.DateTime2).Value = stamp;
    command.Parameters["@Stamp"].Scale = 0;
    command.Parameters.AddWithValue("@WorkMs", workMs);
    await command.ExecuteNonQueryAsync();
}

// A job counts as complete only if both batches stamped it and all of its consignments.
async Task<int> CountComplete(DateTime stamp)
{
    await using var connection = new SqlConnection(connectionString);
    await connection.OpenAsync();
    const string sql = """
        SELECT COUNT(*)
        FROM dbo.Jobs AS j
        WHERE j.JobId BETWEEN @From AND @To
          AND j.RatedUtc = @Stamp AND j.DeliveredUtc = @Stamp
          AND NOT EXISTS (SELECT 1 FROM dbo.Consignments AS c
                          WHERE c.JobId = j.JobId
                            AND (c.LastUpdatedUtc <> @Stamp OR c.PodUtc IS NULL OR c.PodUtc <> @Stamp));
        """;
    await using var command = new SqlCommand(sql, connection) { CommandTimeout = 120 };
    command.Parameters.AddWithValue("@From", FirstJobId);
    command.Parameters.AddWithValue("@To", FirstJobId + Rounds * JobsPerRound - 1);
    command.Parameters.Add("@Stamp", System.Data.SqlDbType.DateTime2).Value = stamp;
    command.Parameters["@Stamp"].Scale = 0;
    return (int)(await command.ExecuteScalarAsync())!;
}

// Whole seconds, because the columns are DATETIME2(0). The one second pause guarantees a new value per mode.
async Task<DateTime> NewStamp()
{
    await Task.Delay(1100);
    var now = DateTime.UtcNow;
    return new DateTime(now.Year, now.Month, now.Day, now.Hour, now.Minute, now.Second, DateTimeKind.Utc);
}

async Task ApplyScript(string path)
{
    await using var connection = new SqlConnection(connectionString);
    await connection.OpenAsync();
    var batches = Regex.Split(await File.ReadAllTextAsync(path), @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
    foreach (var batch in batches.Where(b => b.Trim().Length > 0))
    {
        await using var command = new SqlCommand(batch, connection);
        await command.ExecuteNonQueryAsync();
    }
}

static string FindRepoRoot()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "scenarios"))) dir = dir.Parent;
    return dir?.FullName ?? throw new InvalidOperationException("Could not find the scenarios folder");
}

record ModeResult(string Mode, int Deadlocks, int Retries, int GaveUp, int JobsComplete, double ElapsedSeconds);
