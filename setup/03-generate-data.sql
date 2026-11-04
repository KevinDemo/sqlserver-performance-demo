-- Deterministic data generator: no NEWID() or RAND(), so every run produces the same rows and the
-- benchmark numbers can be compared between runs. "Random" values come from multiplicative hashing.
--
-- Row counts: 60 zones, 20,000 customers, 800 drivers, 600,000 jobs, 900,000 consignments,
-- about 2,190,000 job events. All names are generated placeholders.
USE HarbourDemo;
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Numbers table used only during generation.
DROP TABLE IF EXISTS #Numbers;
SELECT TOP (2500000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS n
INTO #Numbers
FROM sys.all_columns a CROSS JOIN sys.all_columns b;
CREATE UNIQUE CLUSTERED INDEX CX ON #Numbers (n);

INSERT dbo.Zones (ZoneId, ZoneCode, ZoneName, BaseRate)
SELECT n, 'Z' + RIGHT('000' + CAST(n AS VARCHAR(3)), 3), N'Zone ' + CAST(n AS NVARCHAR(3)), 8.50 + (n % 12) * 1.25
FROM #Numbers WHERE n <= 60;

INSERT dbo.Customers (CustomerId, AccountCode, CustomerName, HomeZoneId, CreatedUtc)
SELECT n,
       'AC' + RIGHT('00000000' + CAST(n AS VARCHAR(8)), 8),
       N'Demo Customer ' + CAST(n AS NVARCHAR(8)),
       1 + (n * 7) % 60,
       DATEADD(DAY, (n * 13) % 1500, CAST('2019-01-01' AS DATETIME2(0)))
FROM #Numbers WHERE n <= 20000;

INSERT dbo.Drivers (DriverId, DriverCode, DisplayName, VehicleType, HomeZoneId, IsActive)
SELECT n,
       'D' + RIGHT('00000' + CAST(n AS VARCHAR(5)), 5),
       N'Demo Driver ' + CAST(n AS NVARCHAR(5)),
       CASE n % 4 WHEN 0 THEN 'Bike' WHEN 1 THEN 'Car' WHEN 2 THEN 'Van' ELSE 'Truck' END,
       1 + (n * 11) % 60,
       CASE WHEN n % 10 = 0 THEN 0 ELSE 1 END
FROM #Numbers WHERE n <= 800;

-- Jobs span 2024-01-01 to about 2025-12-31 in BookedUtc order, like a real append-only table.
-- Customer skew is deliberate and drives scenario 03: customer 1 is a large national account with
-- 20% of all jobs, customers 2-10 share another 10%, and the rest share 70%.
INSERT dbo.Jobs WITH (TABLOCK)
    (JobId, CustomerId, DriverId, PickupZoneId, DeliveryZoneId, JobStatus, ServiceLevel,
     BookedUtc, DeliveredUtc, RatedAmount, RatedUtc, Reference, Notes)
SELECT s.n,
       CASE WHEN s.h1 % 100 < 20 THEN 1
            WHEN s.h1 % 100 < 30 THEN 2 + s.h2 % 9
            ELSE 11 + s.h2 % 19990 END,
       CASE WHEN s.st = 0 THEN NULL ELSE 1 + s.h3 % 800 END,
       1 + s.h2 % 60,
       1 + s.h3 % 60,
       s.st,
       CASE s.h1 % 10 WHEN 0 THEN 'ONT' WHEN 1 THEN 'EXP' WHEN 2 THEN 'EXP' ELSE 'STD' END,
       s.booked,
       CASE WHEN s.st = 3 THEN DATEADD(MINUTE, 45 + s.h2 % 300, s.booked) END,
       CASE WHEN s.st = 3 THEN 12.00 + (s.h3 % 9000) / 100.0 END,
       CASE WHEN s.st = 3 THEN DATEADD(HOUR, 6, s.booked) END,
       'REF-' + CAST(s.h2 % 1000000 AS VARCHAR(7)),
       CASE WHEN s.n % 5 = 0 THEN N'Leave at reception, call on arrival' END
FROM (
    SELECT n,
           CAST((n * CAST(2654435761 AS BIGINT)) % 4294967296 AS BIGINT) / 16 AS h1,
           CAST((n * CAST(2246822519 AS BIGINT)) % 4294967296 AS BIGINT) / 16 AS h2,
           CAST((n * CAST(3266489917 AS BIGINT)) % 4294967296 AS BIGINT) / 16 AS h3,
           -- Older jobs are nearly all finished. Only the most recent 1% are still open.
           CAST(CASE WHEN n > 594000 THEN n % 3
                     WHEN n % 40 = 0 THEN 4
                     ELSE 3 END AS TINYINT) AS st,
           DATEADD(SECOND, CAST(n * 105.12 AS INT), CAST('2024-01-01' AS DATETIME2(0))) AS booked
    FROM #Numbers WHERE n <= 600000
) AS s
OPTION (MAXDOP 4);

-- One to two consignments per job (900,000 in total).
INSERT dbo.Consignments WITH (TABLOCK)
    (ConsignmentId, JobId, ConsignmentNumber, WeightKg, Items, PodSignedBy, PodUtc, LastUpdatedUtc)
SELECT n,
       CASE WHEN n <= 600000 THEN n ELSE ((n - 600000) * 2) END,
       'HF' + RIGHT('0000000000' + CAST(n AS VARCHAR(10)), 10),
       0.50 + ((n * 37) % 4000) / 100.0,
       1 + n % 6,
       CASE WHEN n % 3 = 0 THEN N'Signed at door' END,
       CASE WHEN n % 3 = 0 THEN DATEADD(SECOND, CAST(((n - 1) % 600000) * 105.12 AS INT), CAST('2024-01-02' AS DATETIME2(0))) END,
       DATEADD(SECOND, CAST(((n - 1) % 600000) * 105.12 AS INT), CAST('2024-01-01' AS DATETIME2(0)))
FROM #Numbers WHERE n <= 900000
OPTION (MAXDOP 4);

-- Three to four events per job, the biggest table in the demo.
INSERT dbo.JobEvents WITH (TABLOCK) (JobEventId, JobId, EventType, EventUtc, DriverId, Detail)
SELECT ROW_NUMBER() OVER (ORDER BY j.JobId, e.EventType),
       j.JobId,
       e.EventType,
       DATEADD(MINUTE, e.EventType * 40, j.BookedUtc),
       j.DriverId,
       e.Detail
FROM dbo.Jobs AS j
CROSS APPLY (VALUES (CAST(0 AS TINYINT), 'Booked online'),
                    (CAST(1 AS TINYINT), 'Despatched to driver'),
                    (CAST(2 AS TINYINT), 'Picked up')) AS e (EventType, Detail)
OPTION (MAXDOP 4);

DECLARE @next BIGINT = (SELECT MAX(JobEventId) FROM dbo.JobEvents);
INSERT dbo.JobEvents WITH (TABLOCK) (JobEventId, JobId, EventType, EventUtc, DriverId, Detail)
SELECT @next + ROW_NUMBER() OVER (ORDER BY JobId), JobId, 3, DeliveredUtc, DriverId, 'Delivered, POD captured'
FROM dbo.Jobs
WHERE JobStatus = 3 AND JobId % 3 <> 0
OPTION (MAXDOP 4);

DROP TABLE #Numbers;
GO

UPDATE STATISTICS dbo.Jobs WITH FULLSCAN;
UPDATE STATISTICS dbo.Consignments WITH FULLSCAN;
UPDATE STATISTICS dbo.JobEvents WITH FULLSCAN;
GO

SELECT 'Zones' AS TableName, COUNT_BIG(*) AS [Rows] FROM dbo.Zones
UNION ALL SELECT 'Customers', COUNT_BIG(*) FROM dbo.Customers
UNION ALL SELECT 'Drivers', COUNT_BIG(*) FROM dbo.Drivers
UNION ALL SELECT 'Jobs', COUNT_BIG(*) FROM dbo.Jobs
UNION ALL SELECT 'Consignments', COUNT_BIG(*) FROM dbo.Consignments
UNION ALL SELECT 'JobEvents', COUNT_BIG(*) FROM dbo.JobEvents;
GO
