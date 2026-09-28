SELECT name, physical_name
FROM sys.database_files;

ALTER DATABASE TCOP
MODIFY FILE (NAME = TCOP, FILENAME = 'D:\SQLData\TCOP.mdf');

ALTER DATABASE TCOP
MODIFY FILE (NAME = TCOP_Log, FILENAME = 'E:\SQLLogs\TCOP_log.ldf');

ALTER DATABASE TCOP SET OFFLINE WITH ROLLBACK IMMEDIATE;

# Move files on OS level

ALTER DATABASE TCOP SET ONLINE;

# Temp DB
USE tempdb;
GO
SELECT name, physical_name
FROM sys.database_files;

# ------
USE master;
GO

ALTER DATABASE tempdb
MODIFY FILE (NAME = tempdev, FILENAME = 'T:\TempDB\tempdb.mdf');

ALTER DATABASE tempdb
MODIFY FILE (NAME = templog, FILENAME = 'T:\TempDB\templog.ldf');

ALTER DATABASE tempdb
MODIFY FILE (NAME = temp2, FILENAME = 'T:\TempDB\tempdb_mssql_2.ndf');

ALTER DATABASE tempdb
MODIFY FILE (NAME = temp3, FILENAME = 'T:\TempDB\tempdb_mssql_3.ndf');

ALTER DATABASE tempdb
MODIFY FILE (NAME = temp4, FILENAME = 'T:\TempDB\tempdb_mssql_4.ndf');

# Move the files
Restart-Service MSSQLSERVER

USE tempdb;
GO
SELECT name, physical_name
FROM sys.database_files;

-- Check recovery model
SELECT name, recovery_model_desc
FROM sys.databases
WHERE name = 'TCOP';

-- Check restore state (0=online, 1=restoring)
SELECT name, state_desc
FROM sys.databases
WHERE name = 'TCOP';

-- Bring database online if it is in restoring state:
RESTORE DATABASE TCOP WITH RECOVERY;
GO

-- Change recovery model (logging behavior) without restoring:
ALTER DATABASE TCOP
SET RECOVERY FULL;  -- or SIMPLE / BULK_LOGGED
GO


