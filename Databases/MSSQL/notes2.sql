-- SQL Server File Layout, TempDB Move, and Transaction Log Runbook
-- Applies to: SQL Server on Windows

-- ====================================================
-- SECTION 1 - DISK & FILE LAYOUT BEST PRACTICE
-- ====================================================

-- Recommended logical layout (drives may be LUNs / virtual disks):

-- C:\   → Windows OS + SQL Server binaries only
-- D:\   → User database DATA files (.mdf, .ndf)
-- E:\   → User database LOG files (.ldf)
-- F:\   → TempDB data + log
-- G:\   → Backups

-- Notes:
-- - Separate physical I/O paths matter more than drive letters
-- - Data = random IO, Logs = sequential IO
-- - TempDB should always be isolated

-- ====================================================
-- SECTION 2 - IDENTIFY SQL SERVER SERVICE ACCOUNT
-- ====================================================

-- Option A - T-SQL:
-- -----------------
-- SELECT servicename, service_account
-- FROM sys.dm_server_services;

-- Option B - GUI:
-- ---------------
-- SQL Server Configuration Manager
-- → SQL Server Services
-- → Check "Log On As"

-- Examples:
-- - NT SERVICE\MSSQLSERVER
-- - NT SERVICE\MSSQL$MyInstance
-- - DOMAIN\SqlSvcAccount

-- IMPORTANT:
-- Permissions must be granted to THIS account.

-- ====================================================
-- SECTION 3 - GRANT FOLDER PERMISSIONS (WINDOWS)
-- ====================================================

-- This is REQUIRED before moving data/log/TempDB files.

-- --- GUI METHOD ---
-- 1. Right-click target folder (e.g. F:\SQLTempDB)
-- 2. Properties → Security → Edit → Add
-- 3. Add SQL Server service account
-- 4. Grant: Full Control
-- 5. Apply

-- --- CLI METHOD (Run as Administrator) ---

-- Default instance:
-- icacls F:\SQLTempDB /grant "NT SERVICE\MSSQLSERVER:(OI)(CI)F"

-- Named instance:
-- icacls F:\SQLTempDB /grant "NT SERVICE\MSSQL$MyInstance:(OI)(CI)F"

-- Domain account:
-- icacls F:\SQLTempDB /grant "DOMAIN\SqlSvcAccount:(OI)(CI)F"

-- (OI) = Object inherit
-- (CI) = Container inherit
-- F    = Full control

-- ====================================================
-- SECTION 4 - MOVE TEMPDB (EXACT SEQUENCE)
-- ====================================================

-- IMPORTANT:
-- - DO NOT move files manually
-- - TempDB is recreated on restart

--- Step 1: Check current TempDB files ---
USE tempdb;
SELECT name, physical_name FROM sys.database_files;

--- Step 2: Create folder at OS level ---
-- Example:
-- F:\SQLTempDB\
-- (Grant permissions - see Section 3)

--- Step 3: Change file locations (T-SQL) ---
USE master;

ALTER DATABASE tempdb
MODIFY FILE (NAME = tempdev,
             FILENAME = 'F:\SQLTempDB\tempdev.mdf');

ALTER DATABASE tempdb
MODIFY FILE (NAME = templog,
             FILENAME = 'F:\SQLTempDB\templog.ldf');

-- Repeat for tempdev2, tempdev3, etc if present

--- Step 4: Restart SQL Server service ---
-- GUI:
-- - SQL Server Configuration Manager
-- OR CLI:
-- - Restart-Service MSSQLSERVER
-- - Restart-Service MSSQL$MyInstance

--- Step 5: Verify ---
USE tempdb;
SELECT name, physical_name FROM sys.database_files;

--- Step 6: Delete old TempDB files ---
-- ONLY after successful restart and verification.

-- ====================================================
-- SECTION 5 - CONFIGURE TEMPDB FILE COUNT & SIZE
-- ====================================================

-- Guideline:
-- - Start with min( logical CPU cores, 8 ) data files
-- - All files must be same size & growth

-- Example (8 files):

ALTER DATABASE tempdb MODIFY FILE
(NAME='tempdev', SIZE=16GB, FILEGROWTH=1GB);

ALTER DATABASE tempdb ADD FILE
(NAME='tempdev2', FILENAME='F:\SQLTempDB\tempdev2.ndf',
 SIZE=16GB, FILEGROWTH=1GB);

-- -- Repeat tempdev3 .. tempdev8

-- ====================================================
-- SECTION 6 - USER DATABASE DATA & LOG SEPARATION
-- ====================================================

--- Check current locations ---
USE TCOP;
SELECT name, physical_name
FROM sys.database_files;

--- Change file locations ---
ALTER DATABASE TCOP
MODIFY FILE (NAME = TCOP_Data,
             FILENAME = 'D:\TCOP\TCOP_Data.mdf');

ALTER DATABASE TCOP
MODIFY FILE (NAME = TCOP_Log,
             FILENAME = 'E:\SQLLogs\TCOP_Log.ldf');

--- Offline DB ---
ALTER DATABASE TCOP SET OFFLINE WITH ROLLBACK IMMEDIATE;

--- MANUAL STEP (Windows Explorer / CLI) ---
Move .mdf/.ndf/.ldf files to new locations.

--- Bring DB online ---
ALTER DATABASE TCOP SET ONLINE;

-- ====================================================
-- SECTION 7 - MULTIPLE DATA FILES (USER DATABASE)
-- ====================================================

-- Why:
-- - Reduce allocation contention
-- - Improve write concurrency

-- Rules:
-- - Same size
-- - Same FILEGROWTH
-- - Fixed growth (MB/GB)

-- Example:
ALTER DATABASE TCOP ADD FILE
(
 NAME = TCOP_Data_2,
 FILENAME = 'D:\TCOP\TCOP_Data_2.ndf',
 SIZE = 8MB,
 FILEGROWTH = 64MB
);

-- ====================================================
-- SECTION 8 - TRANSACTION LOGS (IMPORTANT)
-- ====================================================

-- FACT:
-- Transaction logs ALWAYS exist and cannot be disabled.

-- What you control:
-- - Recovery model
-- - Log backups

--- Check recovery model ---
SELECT name, recovery_model_desc
FROM sys.databases
WHERE name = 'TCOP';

--- Enable FULL recovery ---
ALTER DATABASE TCOP SET RECOVERY FULL;

--- REQUIRED: Take full backup ---
BACKUP DATABASE TCOP
TO DISK = 'G:\TCOP\TCOP_Full.bak'
WITH INIT, COMPRESSION;

--- Schedule log backups ---
USE msdb;
GO

EXEC sp_add_job
    @job_name = N'TCOP - Transaction Log Backup',
    @enabled = 1,
    @description = N'Log backup every 10 minutes with timestamped files',
    @owner_login_name = N'sa';
GO

EXEC sp_add_jobstep
    @job_name = N'TCOP - Transaction Log Backup',
    @step_name = N'Backup Log',
    @subsystem = N'TSQL',
    @database_name = N'master',
    @command = N'
DECLARE @FileName nvarchar(4000);
SET @FileName =
  N''G:\TCOP\TCOP_Log_'' +
  CONVERT(char(8), GETDATE(), 112) + ''_'' +
  REPLACE(CONVERT(char(8), GETDATE(), 108), '':'','''') +
  ''.trn'';
BACKUP LOG TCOP
TO DISK = @FileName
WITH COMPRESSION;
',
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Quit with failure
GO

EXEC sp_add_schedule
    @schedule_name = N'Every 10 Minutes',
    @freq_type = 4,          -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,   -- Minutes
    @freq_subday_interval = 10,
    @active_start_time = 000000;
GO
EXEC sp_attach_schedule
    @job_name = N'TCOP - Transaction Log Backup',
    @schedule_name = N'Every 10 Minutes';
GO
EXEC sp_add_jobserver
    @job_name = N'TCOP - Transaction Log Backup';
GO

-- Verify job
EXEC msdb.dbo.sp_start_job N'TCOP - Transaction Log Backup';


--- Verify log reuse ---
SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'TCOP';

-- Healthy value:
-- NOTHING

-- ====================================================
-- SECTION 9 - LOG FILE SIZING
-- ====================================================

-- Best practice:
-- - Pre-size log
-- - Fixed growth

-- Example:
ALTER DATABASE TCOP
MODIFY FILE
(
 NAME = TCOP_Log,
 SIZE = 20GB,
 FILEGROWTH = 2GB
);

-- ====================================================
-- SECTION 10 - INSTANT FILE INITIALIZATION (OPTIONAL)
-- ====================================================

-- Windows Local Security Policy:
-- Grant SQL Server service account:
-- "Perform Volume Maintenance Tasks"

-- Effect:
-- - Faster data file growth
-- - Does NOT affect log files

-- ====================================================
-- SECTION 11 - COMMON FAILURES TO AVOID
-- ====================================================

-- Moving files before ALTER DATABASE
-- Forgetting folder permissions
-- Percentage-based file growth
-- No log backups in FULL recovery
-- Unequal TempDB data file sizes

-- ====================================================
-- END OF FILE
-- ====================================================
