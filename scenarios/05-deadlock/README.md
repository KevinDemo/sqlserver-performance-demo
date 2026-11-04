# 05 - Deadlock between two concurrent batches

**Problem.** Two batches update the same jobs and consignments at the same time. `dbo.RateJobs` goes Jobs then Consignments, and `dbo.ImportPods` goes Consignments then Jobs. Each ends up holding what the other needs, SQL Server kills one as the deadlock victim (error 1205), and that batch's transaction rolls back.

**Fix.** Three things, in order of importance:

1. Consistent lock order: both procedures now touch Jobs first, then Consignments (`after.sql`).
2. Short transactions: 200 jobs per commit instead of 2,000, so locks are held for less time and a failure loses less work.
3. A retry on error 1205 with a short backoff, in `DeadlockRepro/Program.cs`, as a safety net.

**Run it.**

```bash
dotnet run -c Release --project scenarios/05-deadlock/DeadlockRepro/DeadlockRepro.csproj
```

It runs two concurrent tasks through 20 rounds of 2,000 jobs in each of three modes, then checks the rows themselves: a job counts as processed only if both batches stamped it and all of its consignments.

**Measured.**

| Mode | Deadlocks | Retries | Batches that gave up | Jobs fully processed | Elapsed |
|---|--:|--:|--:|--:|--:|
| before | 20 | 0 | 20 | 0 of 40,000 | 16.4 s |
| retry-only | 20 | 20 | 0 | 40,000 of 40,000 | 13.4 s |
| fixed | 0 | 0 | 0 | 40,000 of 40,000 | 6.9 s |

**Worth noticing.** Every round deadlocks before the fix because the repro holds each transaction open long enough to overlap, using a simulated work delay. Real systems usually deadlock less often, and that makes the problem harder to diagnose, not milder. Retry alone recovers the data but the deadlocks keep happening, so it hides the cause and still pays for the rollbacks. The elapsed times come from this deliberately conflicting workload and should not be read as a general throughput gain.

`read-deadlock-graphs.sql` pulls the graphs from the built-in `system_health` session. The XML includes host and login names, so review it before sharing it. The repro changes stamps on jobs 300,001 to 340,000; rerun `setup/setup.sh` for a pristine database.
