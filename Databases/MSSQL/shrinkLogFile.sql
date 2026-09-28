# Find the logical name and size
USE TCOP;
GO
SELECT name, size/128 AS SizeMB
FROM sys.database_files
WHERE type_desc = 'LOG';
GO

# Shrink
DBCC SHRINKFILE (N'TCOP_log', 7);  -- 7 = target size in MB
GO
