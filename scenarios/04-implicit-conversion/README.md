# 04 - Implicit conversion, VARCHAR column and NVARCHAR parameter

**Problem.** `ConsignmentNumber` is `VARCHAR(20)` with a unique index. The calling code passes a .NET string through `AddWithValue`, which sends `NVARCHAR`. NVARCHAR has higher precedence, so SQL Server converts the column rather than the parameter, and a one-row lookup becomes a scan of the whole index.

**Fix.** Send the right type. Nothing changes in the database:

```csharp
// before
command.Parameters.AddWithValue("@Number", number);

// after
command.Parameters.Add("@Number", SqlDbType.VarChar, 20).Value = number;
```

**Measured.** Logical reads went from 2,918 to 6. Elapsed time went from about 66 ms to about 0.3 ms.

**Worth noticing.** The result depends on collation. This database uses `SQL_Latin1_General_CP1_CI_AS`, where the conversion forces a scan. With a Windows collation SQL Server can often still seek, so the same code would cost much less, which is why the setup script pins the collation. Plans with this problem carry a `PlanAffectingConvert` warning, so they can be searched for across the plan cache instead of found one complaint at a time.
