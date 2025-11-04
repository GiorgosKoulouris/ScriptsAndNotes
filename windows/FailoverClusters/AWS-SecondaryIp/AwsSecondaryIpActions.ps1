param (
    [string]$Operation,
    [string]$SecondaryIP
)

# Path to aws.exe CLI — update if different
$AwsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"

# Log file path
$LogFile = "C:\ClusterResources\aws-ip-resource.log"

Function Log {
    param([string]$msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$ts : $msg"
}

Function Get-IMDSv2Token {
    try {
        return (Invoke-RestMethod -Uri "http://169.254.169.254/latest/api/token" `
                                  -Method PUT `
                                  -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "21600" } `
                                  -TimeoutSec 3)
    } catch {
        Log "Failed to get IMDSv2 token: $_"
        throw
    }
}

Function Get-PrimaryENIFromMetadata {
    try {
        $token = Get-IMDSv2Token
        $headers = @{ "X-aws-ec2-metadata-token" = $token }

        $macList = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/" -Headers $headers

        if (-not $macList -or $macList.Count -eq 0) {
            throw "No MAC addresses found in metadata."
        }

        $primaryMac = $macList[0].TrimEnd('/')
        $eniId = Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/network/interfaces/macs/$primaryMac/interface-id" -Headers $headers

        return $eniId
    } catch {
        Log "Failed to retrieve primary ENI from metadata: $_"
        throw
    }
}

Function Get-ENIDetailsFromAWS {
    param([string]$eniId)

    try {
        $json = & $AwsCli ec2 describe-network-interfaces --network-interface-ids $eniId | ConvertFrom-Json
        return $json.NetworkInterfaces[0]
    } catch {
        Log "Failed to describe ENI ${eniId}: $_"
        throw
    }
}

Function Assign-IP {
    param([string]$secondaryIp)

    try {
        $eniId = Get-PrimaryENIFromMetadata
        Log "Assigning IP $secondaryIp to ENI $eniId"

        $output = & $AwsCli ec2 assign-private-ip-addresses --network-interface-id $eniId --private-ip-addresses $secondaryIp --allow-reassignment 2>&1

        if ($LASTEXITCODE -eq 0) {
            Log "Assigned IP $secondaryIp successfully."
            return 0
        } else {
            Log "Failed to assign IP: $output"
            return 1
        }
    } catch {
        Log "Exception in Assign-IP: $_"
        return 1
    }
}

Function Unassign-IP {
    param([string]$secondaryIp)

    try {
        $eniId = Get-PrimaryENIFromMetadata
        Log "Unassigning IP $secondaryIp from ENI $eniId"

        $output = & $AwsCli ec2 unassign-private-ip-addresses --network-interface-id $eniId --private-ip-addresses $secondaryIp 2>&1

        if ($LASTEXITCODE -eq 0) {
            Log "Unassigned IP $secondaryIp successfully."
            return 0
        } else {
            Log "Failed to unassign IP: $output"
            return 1
        }
    } catch {
        Log "Exception in Unassign-IP: $_"
        return 1
    }
}

Function Check-IP {
    param([string]$secondaryIp)

    try {
        $eniId = Get-PrimaryENIFromMetadata
        Log "Checking if IP $secondaryIp is assigned to ENI $eniId"

        $ips = & $AwsCli ec2 describe-network-interfaces --network-interface-ids $eniId `
            --query "NetworkInterfaces[0].PrivateIpAddresses[].PrivateIpAddress" --output text 2>&1

        if ($LASTEXITCODE -ne 0) {
            Log "Failed to check IPs: $ips"
            return 1
        }

        if ($ips -match [regex]::Escape($secondaryIp)) {
            Log "IP $secondaryIp is currently assigned."
            return 0
        } else {
            Log "IP $secondaryIp is NOT assigned."
            return 1
        }
    } catch {
        Log "Exception in Check-IP: $_"
        return 1
    }
}

# Main cluster operation handler
Log "----- Operation: $Operation | Secondary IP: $SecondaryIP -----"

switch ($Operation.ToLower()) {
    "online"     { exit (Assign-IP -secondaryIp $SecondaryIP) }
    "offline"    { exit (Unassign-IP -secondaryIp $SecondaryIP) }
    "isalive"    { exit (Check-IP -secondaryIp $SecondaryIP) }
    "looksalive" { exit 0 }
    "open"       { exit 0 }
    "close"      { exit 0 }
    "terminate"  { exit 0 }
    default {
        Log "Unknown operation: $Operation"
        exit 1
    }
}
