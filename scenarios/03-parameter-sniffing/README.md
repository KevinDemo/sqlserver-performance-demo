# 03 - Parameter sniffing on a stored procedure

**Problem.** `dbo.GetCustomerJobs` returns a customer's job history. Customer 1 has 119,987 jobs and customer 5000 has 18. SQL Server builds the cached plan for whichever value it sees first, so the same procedure is fast or slow depending on who ran first after the last recompile. That is why this kind of issue often looks random and "fixes itself" after a restart.

**Fix.** `OPTION (RECOMPILE)` on the statement, so each call gets a plan for its own value.

**Measured.**

| Case | Reads before | Reads after | Elapsed before | Elapsed after |
|---|--:|--:|--:|--:|
| Large customer, small customer ran first | 360,172 | 6,399 | about 304 ms | about 185 ms |
| Small customer, large customer ran first | 6,399 | 57 | about 38 ms | about 1.3 ms |

**Worth noticing.** Both directions are bad. The large customer suffers from 120,000 key lookups, and the small customer pays for a full scan to get 18 rows. `OPTION (RECOMPILE)` is not free, since every call compiles, and that is acceptable here but not for a procedure called thousands of times a minute. In that case I would look at a covering index, `OPTIMIZE FOR`, or separate code paths for the few very large customers. Which one is right depends on call frequency, so the choice is made per procedure.
