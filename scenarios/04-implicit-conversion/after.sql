-- The parameter type now matches the column. The only change is in the calling code.
-- BENCH:MEASURE lookup by consignment number
EXEC sp_executesql
    N'SELECT ConsignmentId, JobId, WeightKg, Items FROM dbo.Consignments WHERE ConsignmentNumber = @Number',
    N'@Number VARCHAR(20)',
    @Number = 'HF0000450000';
