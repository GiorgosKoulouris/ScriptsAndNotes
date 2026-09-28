DECLARE @FileName nvarchar(4000);

SET @FileName =
  N'G:\TCOP\TCOP_Log_' +
  CONVERT(char(8), GETDATE(), 112) + '_' +
  REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '') +
  N'.trn';

BACKUP LOG TCOP
TO DISK = @FileName
WITH COMPRESSION;
GO
