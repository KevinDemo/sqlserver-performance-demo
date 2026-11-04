// Generates the static results site into docs-site/ from the repo's own files. Needs only Node. Run from anywhere:
//   node static-demo/build.mjs
// Every figure comes from results/results.json, results/deadlock.md or results/plans/*.sqlplan. Nothing is typed in by hand.
import { cpSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { esc, page, startOutput } from "./kit/shell.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const out = join(root, "docs-site");
startOutput(out, join(here, "kit"));
cpSync(join(here, "site.css"), join(out, "site.css"));

const REPO = "https://github.com/KevinDemo/sqlserver-performance-demo/blob/main";
const read = (...p) => readFileSync(join(root, ...p), "utf8").replace(/\r\n/g, "\n");
const n = (v) => Number(v).toLocaleString("en-AU");
const ms = (v) => `${v.toFixed(1)} ms`;

/** Inline markdown only: the write-ups use bold, code and links. Links to repo files go to GitHub. */
function inline(text, folder) {
  return esc(text)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, '<code class="mono">$1</code>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) => `<a href="${url.startsWith("http") ? url : `${REPO}/${folder}/${url}`}" target="_blank" rel="noopener">${label}</a>`);
}

/** Reads a .sqlplan into a tree of operators with their actual rows. */
function readPlan(file) {
  const xml = read("results", "plans", file);
  const top = { children: [] };
  const stack = [top];
  for (const [token] of xml.matchAll(/<RelOp [^>]*>|<\/RelOp>|<RunTimeCountersPerThread [^>]*>|<IndexScan [^>]*>|<Object [^>]*>/g)) {
    const attr = (name) => new RegExp(`\\b${name}="([^"]*)"`).exec(token)?.[1];
    const current = stack[stack.length - 1];
    if (token.startsWith("</RelOp")) stack.pop();
    else if (token.startsWith("<RelOp")) {
      const op = { name: attr("PhysicalOp"), estimate: Number(attr("EstimateRows")), actual: 0, seen: false, children: [] };
      current.children.push(op);
      stack.push(op);
    } else if (token.startsWith("<RunTime")) {
      if (current !== top) { current.actual += Number(attr("ActualRows")); current.seen = true; }
    } else if (token.startsWith("<IndexScan")) {
      if (attr("Lookup") === "1") current.name = "Key Lookup";
    } else if (current !== top && !current.object) {
      current.object = (attr("Index") ?? attr("Table") ?? "").replace(/[[\]]/g, "");
    }
  }
  return top.children[0];
}

function planLines(op, depth = 0) {
  const label = `${"  ".repeat(depth)}${op.name}${op.object ? ` ${op.object}` : ""}`;
  const rows = `${op.seen ? `actual ${n(op.actual)}` : "actual n/a"}, est. ${n(Math.round(op.estimate))}`;
  return [`<span class="op">${esc(label)}</span>  <span class="rows">${rows}</span>`, ...op.children.flatMap((c) => planLines(c, depth + 1))];
}

const results = JSON.parse(read("results", "results.json"));

function meter(caption, before, after, format) {
  // A bar must never rest at a false length, so a 0 before draws no full-width bar. Bars are to scale within one figure.
  const width = before > 0 ? (after / before) * 100 : 0;
  return `<figure class="meter">
    <figcaption>${esc(caption)}</figcaption>
    <div class="meter-row"><span class="meter-key">Before</span><span class="meter-track"><i class="meter-before" style="width:${before > 0 ? 100 : 0}%"></i></span><span class="meter-val">${format(before)}</span></div>
    <div class="meter-row"><span class="meter-key">After</span><span class="meter-track"><i class="meter-after" style="width:${width.toFixed(3)}%"></i></span><span class="meter-val">${format(after)}</span></div>
  </figure>`;
}

function caseBlock(row, index) {
  const plans = ["before", "after"].map((when) => {
    const file = `${row.Scenario}-${when}-${index + 1}.sqlplan`;
    const side = when === "before" ? row.Before : row.After;
    const plan = readPlan(file);
    // A wrong pairing of plan and case would silently show the wrong evidence, so the build refuses it.
    if (plan.actual !== side.RowCount) throw new Error(`${file} returned ${plan.actual} rows, results.json says ${side.RowCount}`);
    return `<div>
      <h4>Plan ${when}</h4>
      <pre class="plan">${planLines(plan).join("\n")}</pre>
      <a class="plan-link" href="${REPO}/results/plans/${file}" target="_blank" rel="noopener">${file}</a>
    </div>`;
  }).join("");
  return `<div class="case">
    <h3>${esc(row.Case[0].toUpperCase() + row.Case.slice(1))} <span class="rowcount mono">${n(row.Before.RowCount)} rows, same result before and after</span></h3>
    <div class="meters">
      ${meter("Logical reads", row.Before.LogicalReads, row.After.LogicalReads, n)}
      ${meter("Elapsed, median of " + results.Repetitions + " runs", row.Before.ElapsedMs, row.After.ElapsedMs, ms)}
      ${meter("CPU", row.Before.CpuMs, row.After.CpuMs, (v) => `${v} ms`)}
    </div>
    <div class="pair">${plans}</div>
  </div>`;
}

function sqlPair(folder) {
  const panes = ["before.sql", "after.sql"].filter((f) => existsSync(join(root, "scenarios", folder, f)))
    .map((f) => `<div><h4>${f}</h4><pre>${esc(read("scenarios", folder, f).trim())}</pre></div>`).join("");
  return `<details><summary>The SQL, before and after</summary><div class="pair">${panes}</div></details>`;
}

function writeUp(folder) {
  const [title, ...rest] = read("scenarios", folder, "README.md").trim().split(/\n\n+/);
  return {
    title: title.replace(/^#\s*\d+\s*-\s*/, ""),
    html: rest.filter((b) => !b.startsWith("|") && !b.startsWith("```")).map((b) => `<p>${inline(b.replace(/\n/g, " "), `scenarios/${folder}`)}</p>`).join(""),
  };
}

const groups = [...new Set(results.Rows.map((r) => r.Scenario))];
const scenarioSections = groups.map((folder) => {
  const up = writeUp(folder);
  const rows = results.Rows.filter((r) => r.Scenario === folder);
  return `<section class="scenario" id="s${folder.slice(0, 2)}">
    <h2>${esc(up.title)}</h2>
    <div class="writeup">${up.html}</div>
    ${rows.map(caseBlock).join("")}
    ${sqlPair(folder)}
  </section>`;
}).join("");

// Scenario 05: results/deadlock.md
const deadlockLines = read("results", "deadlock.md").split("\n");
const deadlockTable = deadlockLines.filter((l) => l.startsWith("|")).map((l) => l.split("|").slice(1, -1).map((c) => c.trim()));
const deadlockUp = writeUp("05-deadlock");
const deadlockSection = `<section class="scenario" id="s05">
  <h2>${esc(deadlockUp.title)}</h2>
  <div class="writeup">${deadlockUp.html}</div>
  <div class="case">
    <h3>${esc(deadlockLines[0].replace(/ Run:.*/, ""))}</h3>
    <div class="table-wrap"><table>
      <thead><tr>${deadlockTable[0].map((h, i) => `<th${i ? ' class="num"' : ""}>${esc(h)}</th>`).join("")}</tr></thead>
      <tbody>${deadlockTable.slice(2).map((r) => `<tr>${r.map((c, i) => `<td${i ? ' class="num"' : ""}>${esc(c)}</td>`).join("")}</tr>`).join("")}</tbody>
    </table></div>
  </div>
  ${sqlPair("05-deadlock")}
</section>`;

const summary = results.Rows.map((r) => `<tr>
  <td>${esc(r.Scenario.replace(/^(\d+)-/, "$1 ").replace(/-/g, " "))}, ${esc(r.Case)}</td>
  <td class="num">${n(r.Before.LogicalReads)}</td><td class="num">${n(r.After.LogicalReads)}</td>
  <td class="num">${ms(r.Before.ElapsedMs)}</td><td class="num">${ms(r.After.ElapsedMs)}</td>
</tr>`).join("");

const body = `
<section class="intro">
  <h1>SQL Server performance case study</h1>
  <p>Five common production problems on a fictional courier schema, reproduced, fixed and measured. Measured on ${esc(results.Server)}, median of ${results.Repetitions} runs with a warm cache, on ${results.RunUtc.slice(0, 10)}. Generated from the repo's results files.</p>
</section>
<section class="scenario" id="summary">
  <h2>Results</h2>
  <div class="table-wrap"><table>
    <thead><tr><th>Scenario</th><th class="num">Reads before</th><th class="num">Reads after</th><th class="num">Elapsed before</th><th class="num">Elapsed after</th></tr></thead>
    <tbody>${summary}</tbody>
  </table></div>
  <p class="hint read-note">Logical reads came out the same on every run, so they are the stable measure. Elapsed times moved by up to about 50% between runs, so treat them as orders of magnitude. This is a developer machine with everything in memory, not a promise about your server.</p>
</section>
${scenarioSections}
${deadlockSection}
<footer class="foot">All data is generated and every name is invented. This is a results site: running the queries needs SQL Server, and the steps are in the repo.</footer>
`;

writeFileSync(join(out, "index.html"), page({
  repo: "sqlserver-performance-demo",
  product: "SQL Server performance case study",
  title: "SQL Server performance results",
  lead: "Before and after query plans, reads and timings for five SQL Server performance problems.",
  body,
  styles: ["site.css"],
}));
console.log(`built docs-site/ from ${results.Rows.length} measured cases`);
