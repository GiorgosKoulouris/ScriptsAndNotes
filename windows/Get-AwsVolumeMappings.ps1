# Prints a table (or a line when executed from TANM) for each attached disk
# Columns
#   - Disk number
#   - Partition number
#   - Drive letter
#   - Volume ID (AWS EBS)
#
# Usage:
#    .\Get-AwsVolumeMappings.ps1
#
# To use as a sensor from TANM (comma-delimited):
#    .\Get-AwsVolumeMappings.ps1 -TaniumExecution
#

param (
    [switch]$TaniumExecution
)

function IsOnAwsHyperscaler {
    $biosInfo = Get-WmiObject -Class Win32_BIOS | Select-Object -ExpandProperty Manufacturer

    if ($biosInfo -ne "Amazon EC2") {
        return $false
    } else {
        return $true
    }
}

function GetEBSVolumeId {
    param($Path)
    $SerialNumber = (Get-Disk -Path $Path).SerialNumber
    if ($SerialNumber -clike 'vol*') {
        $EbsVolumeId = $SerialNumber.Substring(0,20).Replace("vol","vol-")
    }
    else {
       $EbsVolumeId = $SerialNumber.Substring(0,20).Replace("AWS","AWS-")
    }
    return $EbsVolumeId
}

function GetDriveLetter{
    param($Path)

    $DiskNumber =  (Get-Disk -Path $Path).Number
    if ($DiskNumber -eq 0) {
        $DriveLetter = "C"
        $PartitionNumber = (Get-Partition -DriveLetter C).PartitionNumber
    }
    else {

        $mainPartition = Get-Partition -DiskNumber $DiskNumber |
            Where-Object {
                $_.DriveLetter -and
                $_.Type -notin @('Reserved', 'Recovery', 'EFI System')
            } |
            Sort-Object -Property Size -Descending |
            Select-Object -First 1

        if ($mainPartition) {
            $DriveLetter = $mainPartition.DriveLetter
            $PartitionNumber = $mainPartition.PartitionNumber

            if(!$DriveLetter) {
                $DriveLetter = ((Get-Partition -DiskId $Path).AccessPaths).Split(",")[0]
            } 
        } else {
            $DriveLetter = "Offline"
            $PartitionNumber = "N/A"
        }
    }
    
    return $DriveLetter, $PartitionNumber

}

function ExecuteMain {
    param (
        [switch]$TaniumExecution
    )

    $Mappings = @()

    foreach ($Path in (Get-Disk).Path) {
        $Disk_ID = ( Get-Partition -DiskId $Path).DiskId
        $Disk = ( Get-Disk -Path $Path).Number
        $EbsVolumeId  = GetEBSVolumeId($Path)
        $Size =(Get-Disk -Path $Path).Size
        $DriveLetter, $PartitionNumber = (GetDriveLetter($Path))
        $Disk = New-Object PSObject -Property @{
        Disk          = $Disk
        DriveLetter   = $DriveLetter
        EbsVolumeId   = $EbsVolumeId
        PartitionNumber = $PartitionNumber
        }
        $Mappings += $Disk
    } 

    if ($TaniumExecution) {
        foreach ($Mapping in $Mappings) {
            $Disk = $Mapping.Disk
            $DriveLetter = $Mapping.DriveLetter
            $EbsVolumeId = $Mapping.EbsVolumeId
            $PartitionNumber = $Mapping.PartitionNumber
            Write-Host "$Disk,$PartitionNumber,$DriveLetter,$EbsVolumeId"
        }
    } else {
        $Mappings | Sort-Object Disk | Format-Table -AutoSize -Property Disk, DriveLetter, EbsVolumeId, PartitionNumber
    }

}

$IsOnAwsHyperscaler = IsOnAwsHyperscaler

if (-not $IsOnAwsHyperscaler) {
    Write-Error "ERROR: This script must be executed on an Amazon EC2 instance."
    exit 1
} else {
    if ($TaniumExecution) {
        ExecuteMain -TaniumExecution
    } else {
        ExecuteMain
    }
}
