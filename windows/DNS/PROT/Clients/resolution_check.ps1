<#
.Synopsis
    This script resolves hostnames to IP addresses and logs the results.
.DESCRIPTION
    This script reads a JSON file containing a list of hostnames and their corresponding IP addresses.
    It then resolves each hostname to an IP address and logs the results to a text file.
    The script also displays an overview of the resolution checks.
.PARAMETER JsonFilePath
    The path to the JSON file containing the list of hostnames and IP addresses.
.EXAMPLE
    .\resolution_check.ps1
    This example resolves the hostnames in the specified JSON file and logs the results.
.NOTES

    ┌─┐┬─┐┌─┐┌┬┐┌─┐┬─┐┌─┐    ┌┬┐┌─┐┌─┐┬ ┬┌┐┌┌─┐┬  ┌─┐┌─┐┬┌─┐┌─┐    ┬  ┬  ┌─┐
    ├─┘├┬┘│ │ │ ├┤ ├┬┘├─┤     │ ├┤ │  ├─┤││││ ││  │ ││ ┬│├┤ └─┐    │  │  │
    ┴  ┴└─└─┘ ┴ └─┘┴└─┴ ┴     ┴ └─┘└─┘┴ ┴┘└┘└─┘┴─┘└─┘└─┘┴└─┘└─┘    ┴─┘┴─┘└─┘
    #     Copyright (c) Protera Technologies LLC. All rights reserved.     #

    File Name      : resolution_check.ps1
    Author         : Spiros Drivas
    Prerequisite   : PowerShell v3.0
    Version        : 1.0

#>

# Define colors and levels for logging
$global:LogLevelInfo = "INFO"
$global:LogLevelSuccess = "SUCCESS"
$global:LogLevelError = "ERROR"
$global:ErrorColor = "Red"
$global:SuccessColor = "Green"
$global:InfoColor = "Yellow"

# Function to resolve hostnames to IP addresses
function Resolve-Hostname {
    <#
    .SYNOPSIS
    Resolves a hostname to an IP address and checks if it matches the expected IP address.
    .DESCRIPTION
    This function resolves a hostname to an IP address and checks if it matches the expected IP address.
    If the resolved IP address matches the expected IP address, the resolution check is considered successful.
    If the resolved IP address does not match the expected IP address, the resolution check is considered failed.
    .PARAMETER Hostname
    The hostname to resolve.
    .PARAMETER ExpectedIP
    The expected IP address for the hostname.
    .OUTPUTS
    Returns $true if the resolution check is successful, $false otherwise.
    #>
    param (
        [string]$Hostname,
        [string]$ExpectedIP
    )
    
    try {
        $resolvedIPs = [System.Net.Dns]::GetHostAddresses($Hostname) | Select-Object -ExpandProperty IPAddressToString
        foreach ($resolvedIP in $resolvedIPs) {
            if ($resolvedIP -eq $ExpectedIP) {
                Log "Resolution check passed for $Hostname. Resolved IP: $resolvedIP" -Level $global:LogLevelSuccess -Color $global:SuccessColor
                return $true
            }
        }
        Log "Resolution check failed for $Hostname. Expected IP: $ExpectedIP, Resolved IPs: $($resolvedIPs -join ', ')" -Level $global:LogLevelError -Color $global:ErrorColor
        return $false
    } catch {
        Log "Unable to resolve $Hostname" -Level $global:LogLevelError -Color $global:ErrorColor
        return $false
    }
}

# Function to log messages with colors and write to log file
function Log {

    <#
    .SYNOPSIS
    Logs messages with colors and writes to a log file.
    .DESCRIPTION
    This function logs messages with specified colors and writes them to a log file.
    .PARAMETER Message
    The message to log.
    .PARAMETER Level
    The log level of the message (INFO, SUCCESS, ERROR).
    .PARAMETER Color
    The color to display the message in the console.
    .EXAMPLE
    Log "This is an informational message." -Level $global:LogLevelInfo -Color $global:InfoColor
    .OUTPUTS
    Writes the log message to the console and log file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$true)]
        [string]$Level,
        [Parameter(Mandatory=$true)]
        [string]$Color
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "$timestamp [$Level] $Message"
    Add-content -Path $logFilePath -Value $logMessage
    Write-Host $logMessage -ForegroundColor $Color
}

# Main function to process JSON input
function Resolve-Checks {
    <#
    .SYNOPSIS
    Resolves hostnames to IP addresses and logs the results.
    .DESCRIPTION
    This function reads a JSON file containing a list of hostnames and their corresponding IP addresses.
    It then resolves each hostname to an IP address and logs the results to a text file.
    The function also displays an overview of the resolution checks.
    .PARAMETER JsonFilePath
    The path to the JSON file containing the list of hostnames and IP addresses.
    .EXAMPLE
    Resolve-Checks -JsonFilePath "C:\hostnames_and_ip.json"
    This example resolves the hostnames in the specified JSON file and logs the results.
    #>
    param (
        [string]$JsonFilePath
    )

    if (-not (Test-Path -Path $logFilePath)) {
        New-Item -Path $logFilePath -ItemType File | Out-Null
    }

    $data = Get-Content $JsonFilePath | ConvertFrom-Json

    $totalHosts = $data.Count
    $successfulResolutions = 0
    $failedResolutions = 0

    foreach ($entry in $data) {
        $hostname = $entry.Hostname
        $expectedIP = $entry.IP

        Log "Checking resolution for $hostname..." -Level $global:LogLevelInfo -Color $global:InfoColor
        $resolutionResult = Resolve-Hostname -Hostname $hostname -ExpectedIP $expectedIP

        if ($resolutionResult) {
            Log "Resolution check passed for $hostname" -Level $global:LogLevelSuccess -Color $global:SuccessColor
            $successfulResolutions++
        } else {
            Log "Resolution check failed for $hostname" -Level $global:LogLevelError -Color $global:ErrorColor
            $failedResolutions++
        }
    }

    $overviewMessage = "Resolution checks completed. Total hosts: $totalHosts, Successful resolutions: $successfulResolutions, Failed resolutions: $failedResolutions"
    Log $overviewMessage -Level $global:LogLevelInfo -Color $global:InfoColor
}

# Function to read and validate JSON data
function ReadAndValidateJson {
    <#
    .SYNOPSIS
    Reads and validates JSON data from a file.
    .DESCRIPTION
    This function reads and validates JSON data from a file and checks if it contains the required fields.
    .PARAMETER JsonFilePath
    The path to the JSON file to read and validate.
    .EXAMPLE
    ReadAndValidateJson -JsonFilePath "dns-entries.json"
    This command reads and validates JSON data from the specified file.
    .OUTPUTS
    Returns the JSON data if it is valid; otherwise, returns $null.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$JsonFilePath,
        [Parameter(Mandatory=$true)]
        [hashtable]$Schema
    )

    try {
        # Check if the JSON file exists
        if (-not (Test-Path -Path $JsonFilePath)) {
            Log "JSON file not found: $JsonFilePath" -Level $global:LogLevelError -Color $global:ErrorColor
            return $null
        }

        # Read the JSON file
        $jsonContent = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json

        # Validate JSON structure
        foreach ($entry in $jsonContent) {
            foreach ($field in $Schema.Keys) {
                if (-not $entry.PSObject.Properties.Name.Contains($field)) {
                    Log "JSON data does not contain required fields (HostName, OldIpAddress, NewIpAddress)." -Level $global:LogLevelError -Color $global:ErrorColor
                    return $null
                }
            }
        }

        return $jsonContent
    }
    catch {
        Log "Error occurred while reading or validating JSON data: $_" -Level $global:LogLevelError -Color $global:ErrorColor
        return $null
    }
}

# Get the current directory
$currentDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Specify the log file name
$logFilePath = Join-Path -Path $currentDirectory -ChildPath "resolution_log.txt"
# Construct the full path to the JSON file
$jsonFileName = "hostnames_and_ip.json"
$jsonFilePath = Join-Path -Path $currentDirectory -ChildPath $jsonFileName

# Specify the JSON file name
$jsonSchema = @{
    Hostname = $true
    IP = $true
}
$jsonContent = ReadAndValidateJson -JsonFilePath $jsonFilePath -Schema $jsonSchema
if ($null -eq $jsonContent) {
    <# Action to perform if the condition is true #>
    Log "Error occurred while reading or validating JSON data." -Level $global:LogLevelError -Color $global:ErrorColor
    exit 1
}

# Execute the main function with JSON file path
Resolve-Checks -JsonFilePath $jsonFilePath