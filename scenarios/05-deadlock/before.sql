-- Two nightly batches touch the same jobs and consignments in opposite table order.
-- RateJobs goes Jobs then Consignments, ImportPods goes Consignments then Jobs.
-- @WorkMs stands in for the application work done while the transaction is open.
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
        UPDATE dbo.Consignments SET PodUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
        WAITFOR DELAY @Delay;
        UPDATE dbo.Jobs SET DeliveredUtc = @Stamp WHERE JobId BETWEEN @FromJobId AND @ToJobId;
    COMMIT;
END
GO
