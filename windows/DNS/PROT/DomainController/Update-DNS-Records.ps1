<#
.SYNOPSIS
This script updates DNS records for multiple hosts in a specified DNS zone.

.DESCRIPTION
This script reads a JSON file containing details of hostnames, old IP addresses, and new IP addresses.
It then removes the old IP addresses associated with the hostnames and adds the new IP addresses to the specified DNS zone.
Detailed logging is provided for each step, and the output is written to a log file.

.PARAMETER ZoneName
Specifies the DNS zone name in which DNS records are to be updated.
.PARAMETER JsonFilePath
Specifies the path to the JSON file containing DNS entries. If not provided, the script will look for a file named "dns-entries.json" in the script directory.

.INPUTS
A JSON file containing an array of objects, each representing a DNS entry with the following properties:
- HostName: The hostname to update.
- OldIpAddress: The old IP address associated with the hostname.
- NewIpAddress: The new IP address to associate with the hostname.

.OUTPUTS
Updates the DNS records in the specified DNS zone and writes the output to a log file.

.NOTES
File Name: UpdateDns.ps1
Author: Spiros Drivas
Prerequisite: This script requires the DNS Server module to be installed on the system.
    To install the DNS Server module, run the following command:
    Install-WindowsFeature -Name RSAT-DNS-Server
Version: 1.1

.EXAMPLE
./UpdateDns.ps1 -ZoneName "your_zone_name"
./UpdateDns.ps1 -ZoneName "your_zone_name" -JsonFilePath "C:\path\to\dns-entries.json"
This command updates DNS records in the specified DNS zone.

#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Specify the zone name.")]
    [string]$ZoneName,
    [Parameter(Mandatory=$false, HelpMessage="Specify the JSON file containing DNS entries.")]
    [string]$JsonFilePath
)

# Define colors and levels for logging
$global:LogLevelInfo = "INFO"
$global:LogLevelSuccess = "SUCCESS"
$global:LogLevelError = "ERROR"
$global:LogLevelDebug = "DEBUG"
$global:ErrorColor = "Red"
$global:SuccessColor = "Green"
$global:InfoColor = "Yellow"
$global:DebugColor = "Cyan"

# Define log file path
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logFilePath = Join-Path -Path $scriptDirectory -ChildPath "UpdateDns_Log.txt"

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

# Function to return the network part of an IP address
function Get-NetworkPart {
    <#
    .SYNOPSIS
    Returns the network part of an IP address based on the subnet mask length.
    .DESCRIPTION
    This function returns the network part of an IP address based on the subnet mask length.
    .PARAMETER ipAddress
    The IP address for which the network part should be extracted.
    .PARAMETER subnetMaskLength
    The length of the subnet mask (default is 24 for /24 network).
    .EXAMPLE
    Get-NetworkPart -ipAddress "10.0.0.10" -subnetMaskLength 24
    This command gets the network part of the specified IP address.
    .OUTPUTS
    Returns the network part of the IP address.
    #>
    param (
        [string]$ipAddress,
        [int]$subnetMaskLength = 24  # Default to /24 network
    )

    # Calculate the number of octets to use for the network part based on the subnet mask
    $octetCount = [math]::Ceiling($subnetMaskLength / 8)

    # Extract the network part of the IP address
    $networkPart = ($ipAddress.Split('.')[0..($octetCount - 1)] -join '.')

    return $networkPart
}

# Function to get the reverse lookup zone name for an IP address
function Get-ReverseLookupZoneName {
    <#
    .SYNOPSIS
    Gets the reverse lookup zone name for an IP address.
    .DESCRIPTION
    This function gets the reverse lookup zone name for an IP address.
    .PARAMETER networkPart
    The network part of the IP address.
    .EXAMPLE
    Get-ReverseLookupZoneName -networkPart "192.168.1"
    This command gets the reverse lookup zone name for the specified network part.
    .OUTPUTS
    Returns the reverse lookup zone name for the IP address.
    #>
    param (
        [string]$networkPart
    )

    # Convert the network part to the reverse lookup zone name
    $octets = $networkPart.Split('.')
    [array]::Reverse($octets)
    $reverseLookupZoneName = ($octets -join '.') + '.in-addr.arpa'

    return $reverseLookupZoneName
}

# Function to remove old IP address from DNS server
function RemoveOldIpAddress {
    <#
    .SYNOPSIS
    Removes the old IP address from the DNS server.
    .DESCRIPTION
    This function removes the old IP address associated with a hostname from the DNS server.
    .PARAMETER HostName
    The hostname for which the old IP address should be removed.
    .PARAMETER OldIpAddress
    The old IP address to be removed.
    .PARAMETER ZoneName
    The DNS zone name in which the record should be removed.
    .EXAMPLE
    RemoveOldIpAddress -HostName "hostname" -OldIpAddress "old_ip_address" -ZoneName "your_zone_name"
    This command removes the old IP address associated with the hostname from the specified DNS zone.
    .OUTPUTS
    Returns $true if the old IP address was successfully removed; otherwise, returns $false.
    #>
    param($HostName, $OldIpAddress, $ZoneName)

    # Remove old IP address record
    try {
        if(Get-DnsServerResourceRecord -ZoneName $ZoneName -Name $HostName -RRType "A" -ErrorAction SilentlyContinue){
            Remove-DnsServerResourceRecord -ZoneName $ZoneName -Name $HostName -RRType "A" -RecordData $OldIpAddress -Force -ErrorAction Stop
            Log "Old IP address '$OldIpAddress' removed successfully for host '$HostName'." -Level $global:LogLevelSuccess -Color $global:SuccessColor
            $true
        }
        else {
            Log "Dns record not found for host '$HostName' with IP address '$OldIpAddress'." -Level $global:LogLevelInfo -Color $global:InfoColor
            $true
        }
    }
    catch {
        Log "Failed to remove old IP address '$OldIpAddress' for host '$HostName'. Error: $_" -Level $global:LogLevelError -Color $global:ErrorColor
        $false
    }
}

# Function to add new IP address to DNS server
function AddNewIpAddress {
    <#
    .SYNOPSIS
    Adds a new IP address to the DNS server.
    .DESCRIPTION
    This function adds a new IP address to the DNS server for a specified hostname.
    .PARAMETER HostName
    The hostname for which the new IP address should be added.
    .PARAMETER NewIpAddress
    The new IP address to be added.
    .PARAMETER ZoneName
    The DNS zone name in which the record should be added.
    .EXAMPLE
    AddNewIpAddress -HostName "hostname" -NewIpAddress "new_ip_address" -ZoneName "your_zone_name"
    This command adds the new IP address to the specified DNS zone for the specified hostname.
    .OUTPUTS
    Writes the result of adding the new IP address to the console.
    #>
    param($HostName, $NewIpAddress, $ZoneName)

    # Add new IP address record
    try {
        # check if reverse lookup zone exists and create it
        if(-not (Get-DnsServerZone -Name (Get-ReverseLookupZoneName -networkPart (Get-NetworkPart -ipAddress $NewIpAddress)) -ErrorAction SilentlyContinue)){
            Log "Reverse lookup zone does not exist for IP address '$NewIpAddress'. Creating reverse lookup zone..." -Level $global:LogLevelInfo -Color $global:InfoColor
            try {
                $networkId = (Get-NetworkPart -ipAddress $NewIpAddress) + ".0/24"
                Add-DnsServerPrimaryZone -NetworkId $networkId -ReplicationScope "Forest" -ErrorAction Stop
                Log "Reverse lookup zone created successfully for IP address '$NewIpAddress'." -Level $global:LogLevelSuccess -Color $global:SuccessColor
            }
            catch {
                Log "Failed to create reverse lookup zone for IP address '$NewIpAddress'. Error: $_" -Level $global:LogLevelError -Color $global:ErrorColor
            }
        }
        Add-DnsServerResourceRecord -ZoneName $ZoneName -Name $HostName -A -IPv4Address $NewIpAddress -CreatePtr -TimeToLive 01:00:00 -ErrorAction Stop
        Log "New IP address '$NewIpAddress' added successfully for host '$HostName'." -Level $global:LogLevelSuccess -Color $global:SuccessColor
    }
    catch {
        Log "Failed to add new IP address '$NewIpAddress' for host '$HostName'. Error: $_" -Level $global:LogLevelError -Color $global:ErrorColor
    }
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

# JSON schema for DNS entries
$jsonSchema = @{
    HostName = $true
    OldIpAddress = $true
    NewIpAddress = $true
}
# Start of script execution
Log "DNS records update started." -Level $global:LogLevelInfo -Color $global:InfoColor

# Read the JSON file
if (!$JsonFilePath) {
    Log "JSON file path not provided. Using default file path." -Level $global:LogLevelInfo -Color $global:InfoColor
    $jsonFileName = "dns-entries.json"
    $jsonFilePath = Join-Path -Path $scriptDirectory -ChildPath $jsonFileName
}
$jsonInput = ReadAndValidateJson -JsonFilePath $jsonFilePath -Schema $jsonSchema
if ($jsonInput -eq $null) {
    # Error occurred while reading or validating JSON data
    Log "Failed to read or validate JSON data. Exiting script." -Level $global:LogLevelError -Color $global:ErrorColor
    Exit 1
}

# Loop through each entry in the JSON input
foreach ($entry in $jsonInput) {
    $HostName = $entry.HostName
    $OldIpAddress = $entry.OldIpAddress
    $NewIpAddress = $entry.NewIpAddress

    Log "Updating DNS records for host '$HostName'..." -Level $global:LogLevelInfo -Color $global:InfoColor

    # Attempt to remove old IP address
    $removeSuccess = RemoveOldIpAddress -HostName $HostName -OldIpAddress $OldIpAddress -ZoneName $ZoneName

    # If old IP address was successfully removed, add new IP address
    if ($removeSuccess) {
        AddNewIpAddress -HostName $HostName -NewIpAddress $NewIpAddress -ZoneName $ZoneName
    }
}

# End of script execution
Log "DNS records update completed." -Level $global:LogLevelInfo -Color $global:InfoColor