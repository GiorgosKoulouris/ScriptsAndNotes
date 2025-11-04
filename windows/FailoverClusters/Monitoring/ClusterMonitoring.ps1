<#
.SYNOPSIS
  Monitors a specific Failover Cluster resource for failures, restarts, or failovers.
  Maintains per-resource timestamps and results in a shared JSON file.

.PARAMETER ResourceName
  The cluster resource name to check.

.PARAMETER MinIntervalMinutes
  Minimum number of minutes since last check before performing a new one.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceName,

    [int]$MinIntervalMinutes = 6,

    [string]$StateFile = "C:\ClusterScripts\ClusterResourceMonitor.json"
)

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INF","WRN","ERR")][string]$Level = "INF",
        [datetime]$Time = (Get-Date)
    )

    $timestamp = $Time.ToString("yyyy-MM-dd HH:mm:ss")
    Write-Output "[$timestamp] [$Level]: $Message"
}

# Function to print a resource checks
function Print-Resource {
    param(
        [Parameter(Mandatory=$true)][pscustomobject]$Resource,
        [string[]]$DateProperties = @("LastCheckTime")
    )

    foreach ($prop in $Resource.PSObject.Properties) {
        $key = $prop.Name
        $value = $prop.Value

        # Format only specified date properties
        if ($key -in $DateProperties -and $value) {
            $value = ([datetime]$value).ToString("yyyy-MM-dd HH:mm:ss")
        }

        Write-Output "$key=$value"
    }
}

# Ensure folder exists
$folder = Split-Path $StateFile
if (-not (Test-Path $folder)) {
    Write-Log -Level "WRN" -Message "State file directory created"
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
} else {
    Write-Log -Level "INF" -Message "State file directory validated"
}

# Load or initialize state
if (Test-Path $StateFile) {
    try {
        $state = Get-Content $StateFile -Raw | ConvertFrom-Json
        Write-Log -Level "INF" -Message "State file validated"
    } catch {
        Write-Log -Level "WRN" -Message "Could not parse existing state file. Starting fresh."
        $state = [PSCustomObject]@{}
    }
} else {
    $state = [PSCustomObject]@{}
    Write-Log -Level "WRN" -Message "Could not locate existing state file. Starting fresh"
}

# Initialize resource if missing
$ResourceName = "DummyPrimitive"
if (-not ($state.PSObject.Properties.Name -contains $ResourceName)) {
    $state = [PSCustomObject]@{ 
        $ResourceName = [PSCustomObject]@{
            LastCheckTime = "1970-01-01T00:00:00Z"
            State         = 0
            Failover      = 0
            Restart       = 0
            OwnerNode     = ""
        }
    }
}

# Parse LastCheckTime safely
$lastCheckRaw = $state.PSObject.Properties[$ResourceName].Value.LastCheckTime

try {
    $lastCheck = [datetime]$lastCheckRaw
} catch {
    Write-Warning "Invalid LastCheckTime. Defaulting to 1970-01-01."
    $lastCheck = [datetime]"1970-01-01T00:00:00Z"
}

$now = Get-Date
$minutesSinceLast = ($now - $lastCheck).TotalMinutes

Write-Log -Level "INF" -Message "Checking resource: $ResourceName"
Write-Log -Level "INF" -Message "Last check: $lastCheck ($([math]::Round($minutesSinceLast,2)) minutes ago)"

# ------------------------------------------------------------
# If interval has not elapsed, skip heavy checks
# ------------------------------------------------------------
if ($minutesSinceLast -lt $MinIntervalMinutes) {
    Write-Log -Level "INF" -Message "Skipping checks - interval ($MinIntervalMinutes min) not elapsed."
    
    Write-Log -Level "INF" -Message "Printing check results for $ResourceName"
    $resource = $state.PSObject.Properties[$ResourceName].Value
    Print-Resource -Resource $resource

    exit 0
}

# ------------------------------------------------------------
# Perform new checks
# ------------------------------------------------------------
Write-Log -Level "INF" -Message "Performing checks for $ResourceName..."

$logName = "Microsoft-Windows-FailoverClustering/Operational"
$eventIDs = @(1200,1201,1203,1204,1637,1674,1817)

$resourceState = 0
$resourceFailover = 0
$resourceRestart = 0

try {
    # 1. Get resource state
    $res = Get-ClusterResource -Name $ResourceName -ErrorAction Stop
    $resState = $res.State
    $owner = $res.OwnerNode.Name
    if ($resState -in @("Failed","Offline")) {
        $resourceState = 1
    }

    $lastOwner = $state.PSObject.Properties[$ResourceName].Value.OwnerNode

    if ($lastOwner -ne $owner) {
        $resourceFailover = 1
    }

    # 2. Get recent events since last check
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = $logName
        StartTime = $lastCheck
        EndTime   = $now
        ID        = $eventIDs
    } -ErrorAction SilentlyContinue | Where-Object {
        $_.Message -match "Cluster resource '$ResourceName'" -or $_.Message -match "clustered role '$ResourceName'"
    }

    foreach ($e in $events) {
        $time = $e.TimeCreated
        $msg  = $e.Message

        if ($msg -match "moved from node" -or $msg -match "moved to node") {
            $resourceFailover = 1
        }
        elseif ($msg -match "transitioned to state Failed" -or $msg -match "going offline" -or $msg -match "Offline") {
            if ($resourceState -ne 1 -and $resourceFailover -ne 1) {
                $resourceRestart = 1
            }
        }
        elseif ($msg -match "transitioned to state Online" -or $msg -match "successfully brought" -or $msg -match "online state after failure") {
            if ($resourceState -ne 1 -and $resourceFailover -ne 1) {
                $resourceRestart = 1
            }
        }
    }

    $state.PSObject.Properties[$ResourceName].Value.LastCheckTime = $now.ToString("o")
    $state.PSObject.Properties[$ResourceName].Value.State = $resourceState
    $state.PSObject.Properties[$ResourceName].Value.Failover = $resourceFailover
    $state.PSObject.Properties[$ResourceName].Value.Restart = $resourceRestart
    $state.PSObject.Properties[$ResourceName].Value.OwnerNode = $owner

    $state | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding UTF8

    Write-Log -Level "INF" -Message "Printing results for $ResourceName"
    $resource = $state.PSObject.Properties[$ResourceName].Value
    Print-Resource -Resource $resource

} catch {
    Write-Log -Level "ERR" -Message "Error checking resource '$ResourceName': $_"
}
