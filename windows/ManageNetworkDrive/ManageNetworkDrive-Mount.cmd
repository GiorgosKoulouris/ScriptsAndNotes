@echo off
setlocal

REM === Set script path and parameters ===
set SCRIPT=Manage-NetworkDrive.ps1
set DRIVE=Z:
set SHARE=\\10.24.24.13\TsbTransfer

REM === Optional: Path to powershell (handles both 32-bit and 64-bit)
set PS=powershell.exe

REM === Call PowerShell script with ExecutionPolicy Bypass
%PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0%SCRIPT%" -Mount -DriveLetter %DRIVE% -NetworkPath %SHARE%

endlocal
pause
