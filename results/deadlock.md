20 rounds of 2,000 jobs, two concurrent batches per round, 40,000 jobs in total. Run: 2026-11-04 02:31 UTC.

| Mode | Deadlocks (error 1205) | Retries | Batches that gave up | Jobs fully processed | Jobs expected | Elapsed (s) |
|---|--:|--:|--:|--:|--:|--:|
| before | 20 | 0 | 20 | 0 | 40,000 | 16.4 |
| retry-only | 20 | 20 | 0 | 40,000 | 40,000 | 13.4 |
| fixed | 0 | 0 | 0 | 40,000 | 40,000 | 6.9 |
