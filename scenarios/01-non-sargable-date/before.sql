-- Daily report written by converting the column to text. The index on BookedUtc cannot be used for a seek.
-- BENCH:MEASURE one-day report
SELECT JobId, CustomerId, BookedUtc, JobStatus
FROM dbo.Jobs
WHERE CONVERT(CHAR(10), BookedUtc, 120) = '2025-03-14';
