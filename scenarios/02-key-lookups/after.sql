-- Covering index: equality column first, then the range column, with the selected columns included.
DROP INDEX IF EXISTS IX_Jobs_PickupZone_BookedUtc ON dbo.Jobs;
GO
CREATE INDEX IX_Jobs_PickupZone_BookedUtc
    ON dbo.Jobs (PickupZoneId, BookedUtc)
    INCLUDE (CustomerId, DriverId, JobStatus, ServiceLevel);
GO
-- BENCH:MEASURE zone despatch board
SELECT JobId, CustomerId, DriverId, JobStatus, ServiceLevel, BookedUtc
FROM dbo.Jobs
WHERE PickupZoneId = 17
  AND BookedUtc >= '2025-10-06' AND BookedUtc < '2025-10-07';
