# 02 - Key lookups from the wrong index

**Problem.** A despatch board asks for one pickup zone on one day. The only useful index is on `BookedUtc`, so SQL Server reads the day for all 60 zones and does a key lookup per row (822 lookups) to test the zone and fetch the other columns. Only 21 rows come back.

**Fix.** A covering index with the equality column first: `(PickupZoneId, BookedUtc) INCLUDE (CustomerId, DriverId, JobStatus, ServiceLevel)`.

**Measured.** Logical reads went from 2,528 to 3. Elapsed time went from about 1.4 ms to about 0.3 ms.

**Worth noticing.** On one execution with a warm cache that time saving is tiny, and it would be dishonest to sell it as more. The value is in reads: a board refreshed by many users all day does about 800 times less page work, which leaves more buffer pool for everything else. Every index also slows writes and takes disk space, so a real review weighs this against the write load and looks for existing indexes it can replace.

`cleanup.sql` drops the index afterwards, because it also happens to cover the query in scenario 01 and would change that scenario's "before" numbers. The benchmark hit exactly that on its second run, which is why the cleanup exists.
