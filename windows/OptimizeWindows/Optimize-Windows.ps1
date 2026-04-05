<#
.SYNOPSIS
    Toggle Windows 10 Performance Tweaks
.DESCRIPTION
    -Disable : Applies tweaks for maximum performance
    -Enable  : Reverts tweaks to defaults
#>

param (
    [switch]$Enable,
    [switch]$Disable
)

# --- Logging Setup ---
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path $ScriptPath
$LogFile    = Join-Path $ScriptDir "Optimize-Windows.log"

Start-Transcript -Path $LogFile -Append -Force

function Disable-Defender {
    Write-Host "Disabling Windows Defender (via registry)..."
    # Create policy key if missing
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force | Out-Null
    }
    # Apply registry flag
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Type DWord -Value 1 -Force

    # Also disable runtime protections (takes effect immediately)
    Set-MpPreference -DisableRealtimeMonitoring $true
    Set-MpPreference -DisableBehaviorMonitoring $true
    Set-MpPreference -DisableBlockAtFirstSeen $true
    Set-MpPreference -DisableIOAVProtection $true
    Set-MpPreference -DisableScriptScanning $true

    Write-Host "Defender will be fully disabled after reboot."
}

function Enable-Defender {
    Write-Host "Re-enabling Windows Defender..."
    # Remove policy key
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -ErrorAction SilentlyContinue

    # Re-enable runtime protections
    Set-MpPreference -DisableRealtimeMonitoring $false
    Set-MpPreference -DisableBehaviorMonitoring $false
    Set-MpPreference -DisableBlockAtFirstSeen $false
    Set-MpPreference -DisableIOAVProtection $false
    Set-MpPreference -DisableScriptScanning $false

    Write-Host "Defender will re-enable after reboot."
}

function Disable-Updates {
    Write-Host "Disabling Windows Update..."
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Set-Service wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service UsoSvc -Force -ErrorAction SilentlyContinue
    Set-Service UsoSvc -StartupType Disabled -ErrorAction SilentlyContinue
}

function Enable-Updates {
    Write-Host "Enabling Windows Update..."
    Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Set-Service UsoSvc -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service UsoSvc -ErrorAction SilentlyContinue
}

function Disable-SearchIndex {
    Write-Host "Disabling Search Indexing..."
    Stop-Service WSearch -Force -ErrorAction SilentlyContinue
    Set-Service WSearch -StartupType Disabled -ErrorAction SilentlyContinue
}

function Enable-SearchIndex {
    Write-Host "Enabling Search Indexing..."
    Set-Service WSearch -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service WSearch -ErrorAction SilentlyContinue
}

function Disable-BackgroundApps {
    Write-Host "Disabling Background Apps..."
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -PropertyType DWord -Value 1 -Force
}

function Enable-BackgroundApps {
    Write-Host "Enabling Background Apps..."
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -ErrorAction SilentlyContinue
}

function Disable-Visuals {
    Write-Host "Optimizing Visual Effects for Performance..."
    $PerformanceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-ItemProperty $PerformanceKey VisualFXSetting 2
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty $RegPath ListviewAlphaSelect 0
    Set-ItemProperty $RegPath ListviewShadow 0
    Set-ItemProperty $RegPath TaskbarAnimations 0
}

function Enable-Visuals {
    Write-Host "Restoring Visual Effects..."
    $PerformanceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Set-ItemProperty $PerformanceKey VisualFXSetting 0
    $RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Remove-ItemProperty $RegPath ListviewAlphaSelect -ErrorAction SilentlyContinue
    Remove-ItemProperty $RegPath ListviewShadow -ErrorAction SilentlyContinue
    Remove-ItemProperty $RegPath TaskbarAnimations -ErrorAction SilentlyContinue
}

function Disable-PowerThrottling {
    Write-Host "Disabling Power Throttling..."
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PowerThrottlingOff" -PropertyType DWord -Value 1 -Force
    powercfg -setactive SCHEME_MIN
}

function Enable-PowerThrottling {
    Write-Host "Enabling Power Throttling..."
    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue
    powercfg -setactive SCHEME_BALANCED
}

# --- Extreme Tweaks ---
function Disable-Extras {
    Write-Host "Disabling Telemetry, Cortana, OneDrive..."
    # Telemetry
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    # Cortana
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
    # OneDrive
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
}

function Enable-Extras {
    Write-Host "Restoring Telemetry, Cortana, OneDrive..."
    Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" -ErrorAction SilentlyContinue
    Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" -ErrorAction SilentlyContinue
}

# --- Main Logic ---
if ($Disable) {
    Disable-Defender
    Disable-Updates
    Disable-SearchIndex
    Disable-BackgroundApps
    Disable-Visuals
    Disable-PowerThrottling
    Disable-Extras
    Write-Host "Performance mode enabled. Please reboot."
}

if ($Enable) {
    Enable-Defender
    Enable-Updates
    Enable-SearchIndex
    Enable-BackgroundApps
    Enable-Visuals
    Enable-PowerThrottling
    Enable-Extras
    Write-Host "Defaults restored. Please reboot."
}
