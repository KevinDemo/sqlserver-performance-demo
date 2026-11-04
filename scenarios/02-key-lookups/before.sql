-- Despatch board for one pickup zone. Only the index on BookedUtc helps, so the query seeks a one-day
-- range for all zones and does a key lookup per row just to test PickupZoneId and fetch the other columns.
DROP INDEX IF EXISTS IX_Jobs_PickupZone_BookedUtc ON dbo.Jobs;
GO
-- BENCH:MEASURE zone despatch board
SELECT JobId, CustomerId, DriverId, JobStatus, ServiceLevel, BookedUtc
FROM dbo.Jobs
WHERE PickupZoneId = 17
  AND BookedUtc >= '2025-10-06' AND BookedUtc < '2025-10-07';
