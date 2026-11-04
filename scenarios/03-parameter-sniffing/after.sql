-- OPTION (RECOMPILE) gives each call a plan for its own parameter value, at the cost of a compile per call.
CREATE OR ALTER PROCEDURE dbo.GetCustomerJobs
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT JobId, BookedUtc, JobStatus, ServiceLevel, RatedAmount, Notes
    FROM dbo.Jobs
    WHERE CustomerId = @CustomerId
    ORDER BY BookedUtc DESC
    OPTION (RECOMPILE);
END
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
EXEC dbo.GetCustomerJobs @CustomerId = 5000;
GO
-- BENCH:MEASURE large customer, small customer ran first
EXEC dbo.GetCustomerJobs @CustomerId = 1;
-- BENCH:PREP
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
EXEC dbo.GetCustomerJobs @CustomerId = 1;
GO
-- BENCH:MEASURE small customer, large customer ran first
EXEC dbo.GetCustomerJobs @CustomerId = 5000;
