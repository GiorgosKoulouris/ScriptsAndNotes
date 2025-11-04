@echo off
setlocal

REM === Settings ===
set SCRIPT=Manage-NetworkDrive.ps1
set SHARE=\\10.24.24.13\TsbTransfer

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0%SCRIPT%" -CreateCredentials -NetworkPath %SHARE%

endlocal
pause
