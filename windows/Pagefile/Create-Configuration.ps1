# Define variables
$SwapDriveLetter = "X"
$SwapDriveName = "SWAP"
$SwapSizeGB = 16
$PerformReboot = $true

$scriptsPath = "C:\Scripts"
$scriptURL = "https://tcop-github-repos.s3.eu-central-1.amazonaws.com/ScriptsAndNotes/windows/Pagefile/Configure-Pagefile.ps1"
$scriptFileName = "Configure-Pagefile.ps1"
$cmdFileName = "configure_pagefile.cmd"
$taskName = "PagefileConfigurationOnBoot"

if ($PerformReboot) {
    $cmdContent = (
        "powershell.exe -ExecutionPolicy Bypass -Command " + 
        "`"$scriptsPath\$scriptFileName -SwapDriveLetter '$SwapDriveLetter' -SwapDriveName '$SwapDriveName' -SwapSizeGB $SwapSizeGB -PerformReboot`""
    )
} else {
    $cmdContent = (
        "powershell.exe -ExecutionPolicy Bypass -Command " + 
        "`"$scriptsPath\$scriptFileName -SwapDriveLetter '$SwapDriveLetter' -SwapDriveName '$SwapDriveName' -SwapSizeGB $SwapSizeGB`""
    )
}

# Create folder if it doesn't exist
if (-Not (Test-Path $scriptsPath)) {
    New-Item -Path $scriptsPath -ItemType Directory
}

# Download the file
$downloadPath = Join-Path $scriptsPath $scriptFileName
Invoke-WebRequest -Uri $scriptURL -OutFile $downloadPath

# Create the CMD file
$cmdFilePath = Join-Path $scriptsPath $cmdFileName
Set-Content -Path $cmdFilePath -Value $cmdContent -Encoding ASCII

# Create a scheduled task to run the CMD file at startup as admin
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$cmdFilePath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

# Register the scheduled task
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force


