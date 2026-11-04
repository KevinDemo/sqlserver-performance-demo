-- ConsignmentNumber is VARCHAR(20). This is what an ADO.NET call sends when it uses
-- AddWithValue with a .NET string: an NVARCHAR parameter. The column gets converted, so no seek.
-- BENCH:MEASURE lookup by consignment number
EXEC sp_executesql
    N'SELECT ConsignmentId, JobId, WeightKg, Items FROM dbo.Consignments WHERE ConsignmentNumber = @Number',
    N'@Number NVARCHAR(20)',
    @Number = N'HF0000450000';
