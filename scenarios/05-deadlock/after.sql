-- The fix on the database side: both batches now lock Jobs first, then Consignments.
-- RateJobs already used that order and stays as it was. The client side of the fix (short batches
-- and a retry on error 1205) is in DeadlockRepro/Program.cs.
CREATE OR ALTER PROCEDURE dbo.RateJobs
    @FromJobId INT, @ToJobId INT, @Stamp DATETIME2(0), @WorkMs INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Delay CHAR(12) = CONVERT(CHAR(12), DATEADD(MILLISECOND, @WorkMs, CAST('00:00:00' AS TIME(3))), 114);
    BEGIN TRANSACTION;
        UPDATE dbo.Jobs SET RatedUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
        WAITFOR DELAY @Delay;
        UPDATE dbo.Consignments SET LastUpdatedUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
    COMMIT;
END
GO
CREATE OR ALTER PROCEDURE dbo.ImportPods
    @FromJobId INT, @ToJobId INT, @Stamp DATETIME2(0), @WorkMs INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Delay CHAR(12) = CONVERT(CHAR(12), DATEADD(MILLISECOND, @WorkMs, CAST('00:00:00' AS TIME(3))), 114);
    BEGIN TRANSACTION;
        UPDATE dbo.Jobs SET DeliveredUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
        WAITFOR DELAY @Delay;
        UPDATE dbo.Consignments SET PodUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
    COMMIT;
END
GO
