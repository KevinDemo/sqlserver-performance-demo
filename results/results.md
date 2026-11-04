Server: Microsoft SQL Server 2019 (RTM-CU27-GDR) (KB5040948) - 15.0.4382.1 (X64). Run: 2026-11-04 02:30 UTC. Median of 7 runs with a warm cache.

| Scenario | Case | Rows | Logical reads before | Logical reads after | Elapsed before (ms) | Elapsed after (ms) | CPU before (ms) | CPU after (ms) |
|---|---|--:|--:|--:|--:|--:|--:|--:|
| 01-non-sargable-date | one-day report | 822 | 6,399 | 2,532 | 108.4 | 2.1 | 109 | 0 |
| 02-key-lookups | zone despatch board | 21 | 2,528 | 3 | 1.4 | 0.3 | 0 | 0 |
| 03-parameter-sniffing | large customer, small customer ran first | 119,987 | 360,172 | 6,399 | 304.0 | 185.1 | 219 | 78 |
| 03-parameter-sniffing | small customer, large customer ran first | 18 | 6,399 | 57 | 37.7 | 1.3 | 31 | 0 |
| 04-implicit-conversion | lookup by consignment number | 1 | 2,918 | 6 | 66.2 | 0.3 | 63 | 0 |

| Scenario | Case | Plan before | Plan after |
|---|---|---|---|
| 01-non-sargable-date | one-day report | Clustered Index Scan PK_Jobs | Index Seek IX_Jobs_BookedUtc + Key Lookup PK_Jobs |
| 02-key-lookups | zone despatch board | Index Seek IX_Jobs_BookedUtc + Key Lookup PK_Jobs | Index Seek IX_Jobs_PickupZone_BookedUtc |
| 03-parameter-sniffing | large customer, small customer ran first | Sort + Index Seek IX_Jobs_CustomerId + Key Lookup PK_Jobs | Sort + Clustered Index Scan PK_Jobs |
| 03-parameter-sniffing | small customer, large customer ran first | Sort + Clustered Index Scan PK_Jobs | Sort + Index Seek IX_Jobs_CustomerId + Key Lookup PK_Jobs |
| 04-implicit-conversion | lookup by consignment number | Index Scan UX_Consignments_Number + Key Lookup PK_Consignments | Index Seek UX_Consignments_Number + Key Lookup PK_Consignments |
