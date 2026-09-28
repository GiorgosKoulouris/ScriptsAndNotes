-- ---- Restore Full backup -----
-- Get the logical names
RESTORE FILELISTONLY
FROM DISK = 'G:\TCOP\TCOP_Full.bak';
GO

RESTORE DATABASE TCOP
FROM DISK = 'G:\TCOP\TCOP_Full.bak'
WITH 
    MOVE 'TCOP' TO 'D:\TCOP\TCOP.mdf',
    MOVE 'TCOP_Data_2'  TO 'D:\TCOP\TCOP_Data_2.ndf',
    MOVE 'TCOP_log'  TO 'L:\TCOP\TCOP_log.ldf',
    REPLACE,  -- overwrite existing DB if it exists
    STATS = 10;  -- shows progress every 10%
GO

-- ---- Restore to point in time -------

-- Step 1 is valid if you care about the current logs
-- Back up the current log and leave the DB in recovery mode
BACKUP LOG TCOP
TO DISK = 'G:\TCOP\TCOP_Tail.trn'
WITH NORECOVERY;
GO

RESTORE DATABASE TCOP
FROM DISK = 'G:\TCOP\TCOP_Full.bak'
WITH REPLACE,
    MOVE 'TCOP' TO 'D:\TCOP\TCOP.mdf',
    MOVE 'TCOP_Data_2'  TO 'D:\TCOP\TCOP_Data_2.ndf',
    MOVE 'TCOP_log'  TO 'L:\TCOP\TCOP_log.ldf',
    NORECOVERY,  -- keep DB in restoring state
    STATS = 10;
GO

-- Restore multiple logs
RESTORE LOG TCOP
FROM DISK = 'G:\TCOP\TCOP_Log_001.trn'
WITH NORECOVERY;
GO

RESTORE LOG TCOP
FROM DISK = 'G:\TCOP\TCOP_Log_002.trn'
WITH NORECOVERY;
GO

RESTORE LOG TCOP
FROM DISK = 'G:\TCOP\TCOP_Log_003.trn'
WITH 
    STOPAT = '2025-12-17 10:35:00',  -- desired point in time
    RECOVERY,                        -- bring database online
    STATS = 10;
GO
