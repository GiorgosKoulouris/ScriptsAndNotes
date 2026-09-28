-- ===================================================
-- 2. Create Test Tables
-- ===================================================
USE TCOP;
GO

IF OBJECT_ID('dbo.TestOrders','U') IS NOT NULL DROP TABLE dbo.TestOrders;
IF OBJECT_ID('dbo.TestAudit','U') IS NOT NULL DROP TABLE dbo.TestAudit;

CREATE TABLE dbo.TestOrders
(
    OrderID        int IDENTITY(1,1) PRIMARY KEY,
    OrderDate      datetime2 NOT NULL DEFAULT SYSDATETIME(),
    CustomerName   varchar(100) NOT NULL,
    Amount         decimal(12,2) NOT NULL
);

CREATE TABLE dbo.TestAudit
(
    AuditID    bigint IDENTITY(1,1) PRIMARY KEY,
    OrderID    int,
    Action     varchar(20),
    ActionDate datetime2 DEFAULT SYSDATETIME()
);
GO

-- ===================================================
-- 3. Simple Auto-Commit Inserts
-- ===================================================
INSERT INTO dbo.TestOrders (CustomerName, Amount)
VALUES ('Alice', 100.00),
       ('Bob',   200.00),
       ('Carol', 300.00);
GO

-- ===================================================
-- 4. Explicit Transaction with COMMIT
-- ===================================================
BEGIN TRAN;

INSERT INTO dbo.TestOrders (CustomerName, Amount)
VALUES ('David', 400.00);

INSERT INTO dbo.TestAudit (OrderID, Action)
VALUES (SCOPE_IDENTITY(), 'INSERT');

COMMIT TRAN;
GO

-- ===================================================
-- 5. Explicit Transaction with ROLLBACK
-- ===================================================
BEGIN TRAN;

INSERT INTO dbo.TestOrders (CustomerName, Amount)
VALUES ('Eve', 500.00);

ROLLBACK TRAN;
GO

-- ===================================================
-- 6. Generate Heavy Log Volume (Looped Transactions)
-- ===================================================
SET NOCOUNT ON;

DECLARE @i int = 1;

WHILE @i <= 1000 -- adjust number for testing load
BEGIN
    BEGIN TRAN;

    INSERT INTO dbo.TestOrders (CustomerName, Amount)
    VALUES (CONCAT('Customer_', @i), RAND() * 1000);

    COMMIT TRAN;

    SET @i += 1;
END
GO

-- ===================================================
-- 7. Long-Running Transaction (Blocks Log Truncation)
-- ===================================================
-- Open a separate session to run this and leave open:
-- BEGIN TRAN;
-- UPDATE dbo.TestOrders SET Amount = Amount + 1;
-- -- DO NOT COMMIT OR ROLLBACK YET
-- -- In another session, check log_reuse_wait_desc

-- ===================================================
-- 8. Transaction Log Backup with Timestamped Filenames
-- ===================================================

-- DECLARE @FileName nvarchar(4000);

-- SET @FileName =
--   N'G:\TCOP\TCOP_Log_' +
--   CONVERT(char(8), GETDATE(), 112) + '_' +
--   REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '') +
--   N'.trn';

-- BACKUP LOG TCOP
-- TO DISK = @FileName
-- WITH COMPRESSION;
-- GO

-- ===================================================
-- 9. Verify Log Usage (Optional)
-- ===================================================
DBCC SQLPERF(LOGSPACE);
GO

SELECT name, log_reuse_wait_desc
FROM sys.databases
WHERE name = 'TCOP';
GO

-- ===================================================
-- 10. Optional Cleanup (Uncomment if needed)
-- ===================================================
-- DROP DATABASE TCOP;
-- GO