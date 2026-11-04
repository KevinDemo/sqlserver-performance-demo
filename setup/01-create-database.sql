-- Creates (or recreates) the demo database. Everything in it is fictional.
USE master;
GO
IF DB_ID(N'HarbourDemo') IS NOT NULL
BEGIN
    ALTER DATABASE HarbourDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE HarbourDemo;
END
GO
-- The collation is pinned because scenario 04 depends on it: with a SQL_ collation an
-- NVARCHAR parameter against a VARCHAR column cannot seek. Windows collations behave differently.
CREATE DATABASE HarbourDemo COLLATE SQL_Latin1_General_CP1_CI_AS;
GO
ALTER DATABASE HarbourDemo SET RECOVERY SIMPLE;
-- Pinned so results do not move between SQL Server versions.
ALTER DATABASE HarbourDemo SET COMPATIBILITY_LEVEL = 150;
GO
