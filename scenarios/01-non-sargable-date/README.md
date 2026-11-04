# 01 - Function on a date column

**Problem.** A daily report filters with `CONVERT(CHAR(10), BookedUtc, 120) = '2025-03-14'`. Wrapping the column in a function means SQL Server cannot seek the index on `BookedUtc`, so it scans all 600,000 jobs and converts each date to text.

**Fix.** Filter the bare column with a half-open range: `BookedUtc >= '2025-03-14' AND BookedUtc < '2025-03-15'`. No schema change, same 822 rows.

**Measured.** Logical reads went from 6,399 to 2,532. Elapsed time went from about 108 ms to about 2 ms.

**Worth noticing.** Reads fell by only 2.5 times but elapsed time fell by about 50 times. Most of the original cost was CPU spent converting 600,000 dates to strings, which a reads-only review would underrate. The 2,532 reads that remain are key lookups, and scenario 02 shows how to remove that kind of cost when a query runs often enough to justify an index.
