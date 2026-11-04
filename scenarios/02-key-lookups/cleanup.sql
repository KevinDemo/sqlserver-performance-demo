-- The covering index also covers scenario 01's query, so it must not outlive this scenario.
DROP INDEX IF EXISTS IX_Jobs_PickupZone_BookedUtc ON dbo.Jobs;
