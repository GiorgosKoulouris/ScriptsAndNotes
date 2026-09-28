/* ============================================================
   Point-in-Time Restore Template for SQL Server
   - Restores a full backup
   - Applies multiple transaction log backups in order
   - Stops at a specific point in time
   ============================================================ */

-- ===============================
-- Step 0: Set variables
-- ===============================
DECLARE @DatabaseName SYSNAME = N'TCOP';   -- target database
DECLARE @FullBackup NVARCHAR(4000) = N'G:\TCOP\TCOP_Full.bak';

-- Logical names from backup (check using RESTORE FILELISTONLY)
DECLARE @DataFile NVARCHAR(128) = N'TCOP';
DECLARE @LogFile  NVARCHAR(128) = N'TCOP_Log';

-- Physical paths for this server
DECLARE @DataPath NVARCHAR(4000) = N'G:\TCOP\TCOP.mdf';
DECLARE @LogPath  NVARCHAR(4000) = N'G:\TCOP\TCOP_Log.ldf';

-- Log backups in chronological order
DECLARE @LogBackups TABLE (BackupFile NVARCHAR(4000));
INSERT INTO @LogBackups (BackupFile)
VALUES 
('G:\TCOP\TCOP_Log_001.trn'),
('G:\TCOP\TCOP_Log_002.trn'),
('G:\TCOP\TCOP_Log_003.trn');  -- Add more as needed

-- Point in time to stop (within the last log)
DECLARE @StopAt DATETIME = '2025-12-17 10:35:00';

-- ===============================
-- Step 1: Restore full backup
-- ===============================
RESTORE DATABASE [TCOP]
FROM DISK = @FullBackup
WITH 
    MOVE @DataFile TO @DataPath,
    MOVE @LogFile TO @LogPath,
    NORECOVERY,  -- keep DB in restoring state
    REPLACE,     -- overwrite if DB exists
    STATS = 10;
GO

-- ===============================
-- Step 2: Restore log backups in order
-- ===============================
DECLARE @BackupFile NVARCHAR(4000);
DECLARE log_cursor CURSOR FOR
    SELECT BackupFile FROM @LogBackups ORDER BY BackupFile;

OPEN log_cursor;
FETCH NEXT FROM log_cursor INTO @BackupFile;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- If this is the last log backup, use STOPAT + RECOVERY
    IF (@BackupFile = (SELECT MAX(BackupFile) FROM @LogBackups))
    BEGIN
        PRINT 'Restoring final log backup with STOPAT...';
        RESTORE LOG [TCOP]
        FROM DISK = @BackupFile
        WITH 
            STOPAT = @StopAt,
            RECOVERY,
            STATS = 10;
    END
    ELSE
    BEGIN
        PRINT 'Restoring log backup: ' + @BackupFile;
        RESTORE LOG [TCOP]
        FROM DISK = @BackupFile
        WITH NORECOVERY,
             STATS = 10;
    END

    FETCH NEXT FROM log_cursor INTO @BackupFile;
END

CLOSE log_cursor;
DEALLOCATE log_cursor;
GO

-- ===============================
-- Step 3: Verify restore
-- ===============================
USE [TCOP];
GO
SELECT name FROM sys.tables;           -- list tables
SELECT COUNT(*) AS RowCount FROM dbo.YourTable;  -- verify rows
DBCC SQLPERF(LOGSPACE);                -- check log usage
GO
