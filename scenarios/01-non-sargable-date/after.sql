-- Same report as a half-open date range on the bare column. No schema change needed.
-- BENCH:MEASURE one-day report
SELECT JobId, CustomerId, BookedUtc, JobStatus
FROM dbo.Jobs
WHERE BookedUtc >= '2025-03-14' AND BookedUtc < '2025-03-15';
