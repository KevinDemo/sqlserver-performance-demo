-- Reads recent deadlock graphs from the built-in system_health session. No setup needed, and this is
-- normally the first query of a deadlock investigation. Save a graph as .xdl to open it in SSMS.
-- The XML includes host and login names, so review it before sharing it.
SET QUOTED_IDENTIFIER ON; -- the XML methods below require it, and sqlcmd defaults to OFF
SELECT TOP (5)
    x.event_xml.value('(event/@timestamp)[1]', 'datetime2(0)') AS EventUtc,
    x.event_xml.query('(event/data/value/deadlock)[1]') AS DeadlockGraph
FROM (
    SELECT CAST(event_data AS XML) AS event_xml
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
) AS x
ORDER BY EventUtc DESC;
