-- Customer job history. Customer 1 owns 20% of all jobs, customer 5000 has a few dozen.
-- Whichever customer runs first after a recompile decides the plan everyone else gets.
CREATE OR ALTER PROCEDURE dbo.GetCustomerJobs
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT JobId, BookedUtc, JobStatus, ServiceLevel, RatedAmount, Notes
    FROM dbo.Jobs
    WHERE CustomerId = @CustomerId
    ORDER BY BookedUtc DESC;
END
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Small customer runs first and caches a seek plus key lookups.
EXEC dbo.GetCustomerJobs @CustomerId = 5000;
GO
-- BENCH:MEASURE large customer, small customer ran first
EXEC dbo.GetCustomerJobs @CustomerId = 1;
-- BENCH:PREP
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Large customer runs first and caches a full scan.
EXEC dbo.GetCustomerJobs @CustomerId = 1;
GO
-- BENCH:MEASURE small customer, large customer ran first
EXEC dbo.GetCustomerJobs @CustomerId = 5000;
