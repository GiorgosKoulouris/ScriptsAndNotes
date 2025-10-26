# Parameters for the script
param (
    [string]$DnsServers,
    [string]$DnsSearch,
    [string]$CommentHostfile
)

# Log function
function Log-Message {
    param (
        [string]$LogLevel,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$LogLevel] $Message"
    $logMessage | Out-File -FilePath "$env:USERPROFILE\dns_update.log" -Append
    Write-Host $logMessage
}

# Display usage function
function Show-Usage {
    Write-Host "Usage: .\$($MyInvocation.MyCommand.Name) [-DnsServers <DNS_SERVERS>] [-DnsSearch <DNS_SEARCH>] [-CommentHostfile <NETWORK_RANGE>]"
    Write-Host "Example: .\$($MyInvocation.MyCommand.Name) -DnsServers '8.8.8.8 8.8.4.4' -DnsSearch 'example.com' -CommentHostfile '10.10.10.0/23'"
    exit 1
}

# Check if the script is running as administrator
function Check-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not ([Security.Principal.WindowsPrincipal] $currentUser).IsInRole($adminRole)) {
        Write-Host "ERROR: This script must be run as an administrator."
        exit 1
    }
}

# Update DNS servers on IPv4 settings
function Update-DnsServers {
    param (
        [string]$DesiredDnsServers
    )
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        if ($DesiredDnsServers -eq "UseDHCP") {
            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
            Log-Message -LogLevel "INFO" -Message "Using DNS servers offered by DHCP on $($adapter.Name)"
        } else {
            $currentDnsServers = (Get-DnsClientServerAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4).ServerAddresses
            $desiredDnsArray = $DesiredDnsServers -split ' '
            if ($currentDnsServers -ne $desiredDnsArray) {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $desiredDnsArray
                Log-Message -LogLevel "INFO" -Message "Updated DNS servers for adapter $($adapter.Name) to: $DesiredDnsServers"
            } else {
                Log-Message -LogLevel "INFO" -Message "DNS servers for adapter $($adapter.Name) are already set to the desired value: $DesiredDnsServers"
            }
        }
    }
}

# Update DNS search suffix on IPv4 settings
function Update-DnsSearch {
    param (
        [string]$DesiredDnsSearch
    )
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    foreach ($adapter in $adapters) {
        if ($DesiredDnsSearch -eq "UseDHCP") {
            Set-DnsClientGlobalSetting -SuffixSearchList @()
            Log-Message -LogLevel "INFO" -Message "Using search suffixes offered by DHCP on $($adapter.Name)"
        } else {
            $currentDnsSearch = (Get-DnsClientGlobalSetting).SuffixSearchList
            if ($currentDnsSearch -notcontains $DesiredDnsSearch) {
                Set-DnsClientGlobalSetting -SuffixSearchList $DesiredDnsSearch
                Log-Message -LogLevel "INFO" -Message "Updated DNS search suffix for adapter $($adapter.Name) to: $DesiredDnsSearch"
            } else {
                Log-Message -LogLevel "INFO" -Message "DNS search suffix for adapter $($adapter.Name) is already set to the desired value: $DesiredDnsSearch"
            }
        }
    }
}

# Convert IP to integer
function IpToInt {
    param (
        [string]$IpAddress
    )
    try {
        $ipParts = $IpAddress -split '\.'
        if ($ipParts.Count -ne 4) {
            throw "Invalid IP address format: $IpAddress"
        }
        return [math]::Pow(256, 3) * [int]$ipParts[0] + [math]::Pow(256, 2) * [int]$ipParts[1] + 256 * [int]$ipParts[2] + [int]$ipParts[3]
    } catch {
        Log-Message -LogLevel "ERROR" -Message "Failed to convert IP address to integer: $_"
        throw
    }
}

# Calculate subnet range
function Get-SubnetRange {
    param (
        [string]$NetworkRange
    )
    try {
        $networkAddress, $subnetMask = $NetworkRange -split '/'
        if (-not $subnetMask) {
            throw "Invalid network range format: $NetworkRange"
        }
        $subnetMask = [int]$subnetMask
        $startIp = IpToInt -IpAddress $networkAddress
        $mask = [math]::Pow(2, 32) - [math]::Pow(2, 32 - $subnetMask)
        $endIp = $startIp -band $mask -bor -bnot $mask
        return $startIp, $endIp
    } catch {
        Log-Message -LogLevel "ERROR" -Message "Failed to calculate subnet range: $_"
        throw
    }
}

# Comment entries in hosts file within specified network range
function Comment-HostsFile {
    param (
        [string]$NetworkRange
    )
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backupPath = "$hostsPath.bak"

    # Create a backup of the hosts file
    Copy-Item -Path $hostsPath -Destination $backupPath -Force
    Log-Message -LogLevel "INFO" -Message "Backup of hosts file created at $backupPath"

    $startIp, $endIp = Get-SubnetRange -NetworkRange $NetworkRange

    Log-Message -LogLevel "INFO" -Message "Commenting out entries in $hostsPath for the network range: $NetworkRange"

    $hostsContent = Get-Content $hostsPath
    $newHostsContent = foreach ($line in $hostsContent) {
        $line = $line.Trim()  # Remove leading/trailing whitespace
        if ($line -match '^(\d+\.\d+\.\d+\.\d+)\s+(\S+)') {
            $ip = $matches[1]
            $hostname = $matches[2]
            try {
                $ipInt = IpToInt -IpAddress $ip
                if ($ipInt -ge $startIp -and $ipInt -le $endIp) {
                    "# $line"
                    Log-Message -LogLevel "INFO" -Message "Commented out: $line"
                } else {
                    $line
                }
            } catch {
                Log-Message -LogLevel "ERROR" -Message "Failed to process line: $line"
                $line
            }
        } else {
            $line
        }
    }
    $newHostsContent | Set-Content $hostsPath
}

# Main program
Check-Admin

# Ensure the log file is writable
$logFilePath = "$env:USERPROFILE\dns_update.log"
if (-not (Test-Path $logFilePath)) {
    New-Item -ItemType File -Path $logFilePath
    Set-ItemProperty -Path $logFilePath -Name IsReadOnly -Value $false
}

# Check that at least one of the parameters is provided
if (-not $DnsServers -and -not $DnsSearch -and -not $CommentHostfile) {
    Show-Usage
}

# Log start of script execution
Log-Message -LogLevel "INFO" -Message "Starting DNS configuration update"

# Check and update DNS servers if provided
if ($DnsServers) {
    Update-DnsServers -DesiredDnsServers $DnsServers
}

# Check and update DNS search if provided
if ($DnsSearch) {
    Update-DnsSearch -DesiredDnsSearch $DnsSearch
}

# Comment entries in hosts file if network range is provided
if ($CommentHostfile) {
    Comment-HostsFile -NetworkRange $CommentHostfile
}

# Log end of script execution
Log-Message -LogLevel "INFO" -Message "DNS configuration update completed successfully"