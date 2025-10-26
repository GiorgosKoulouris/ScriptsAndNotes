param(
    [Parameter(Mandatory=$false)]
    [string]$RestorePointName="Latest"
)

$VmName = "TSBRDAWS00"
$ResourceGroupName = "TSBR-VMs"
$RestorePointCollection = "$VmName-Archive"
$VnetResourceGroup = "TSBR-Infrastructure"
$VnetName = "TSBR-VNET"
$subnetName = "TSBR-Private-Subnet"
$PrivateIP = "10.120.10.5"
$CreateSpot = $true
$VmSize = "Standard_D2_v4"

# Connect to Azure (Automation Runbook will use Managed Identity or service principal)
Connect-AzAccount -Identity

# Fetch the restore point and disk restore points
try {

    if ($RestorePointName -eq "Latest") {
        Write-Output "Fetching the latest restore point..."
        $restorePoints = (Get-AzRestorePointCollection -ResourceGroupName $ResourceGroupName -Name $RestorePointCollection).RestorePoints
        if ($restorePoints.Count -eq 0) {
            Write-Error "No restore points found in collection $RestorePointCollection. Exiting..."
            exit 1
        }
        $restorePoint = $restorePoints | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $RestorePointName = $restorePoint.Name
        Write-Output "Latest restore point: $RestorePointName"
    } else {
        Write-Output "Fetching restore point: $RestorePointName"
        $restorePoint = Get-AzRestorePoint -ResourceGroupName $ResourceGroupName -RestorePointCollectionName $RestorePointCollection -Name $RestorePointName
    }

    if (-not $restorePoint) {
        Write-Error "Restore point $RestorePointName not found in collection $RestorePointCollection. Exiting..."
        exit 1
    }

    $location = $restorePoint.SourceMetadata.Location
    $securityType = $restorePoint.SourceMetadata.SecurityProfile.SecurityType

    $osDiskRestorePoint = $restorePoint.SourceMetadata.StorageProfile.OsDisk.DiskRestorePoint.Id
    $diskRestorePoints = @($restorePoint.SourceMetadata.StorageProfile.OsDisk)
    foreach ($datadisk in $restorePoint.sourceMetadata.storageProfile.dataDisks) {
        $diskRestorePoints += $datadisk
    }

} catch {
    Write-Error "Failed to fetch restore point and disk restore points. Exiting..."
    exit 1
}

# Create the disks
try{
    Write-Output "Creating disks from Restore Point: $RestorePointName"
    $dataDisks = @()
    foreach ($disk in $diskRestorePoints) {
        # Fetch disk info
        $diskName = $disk.name

        $existingDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $diskName -ErrorAction SilentlyContinue
        if ($existingDisk) {
            Write-Output "Disk $diskName already exists. Renaming to $diskName-new."
            $diskName = "$diskName-new"
        }

        # Get original SKU
        $diskSkuName = $disk.ManagedDisk.StorageAccountType
        $diskSkuNameStr = [string]$diskSkuName

        $diskSize = $disk.DiskSizeGB

        # Create the disk
        Write-Output "Creating disk $diskName from Restore Point: $RestorePointName"
        $sourceId = [string]$disk.DiskRestorePoint.id
        if ($disk.OsType -ne $null) {
            $osType = $disk.OsType
            $osDisk = New-AzDisk -DiskName $diskName -ResourceGroupName $ResourceGroupName `
                (New-AzDiskConfig -Location $location `
                        -SkuName $diskSkuNameStr `
                        -CreateOption Restore `
                        -OsType $disk.OsType `
                        -SourceResourceId $sourceId `
                        -DiskSizeGB $diskSize)
        } else {
            $newDisk = New-AzDisk -DiskName $diskName -ResourceGroupName $ResourceGroupName `
                (New-AzDiskConfig -Location $location `
                        -SkuName $diskSkuNameStr `
                        -CreateOption Restore `
                        -SourceResourceId $sourceId `
                        -DiskSizeGB $diskSize)

            $diskObj = @{
                Lun = $disk.Lun
                Caching = $disk.Caching
                Disk = $newDisk
            }
            $dataDisks += New-Object psobject -Property $diskObj
        }

        Write-Output "Disk $diskName created successfully."

    }
} catch {
    Write-Error "Failed to create disks from Restore Point. Exiting..."
    exit 1
}

# Create the network interface
try {
    Write-Output "Creating the network interface..."
    $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $VnetResourceGroup
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet
    $ipConfig = New-AzNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $PrivateIP -Subnet $subnet
    $nic = New-AzNetworkInterface -Name "$VmName-NIC" -ResourceGroupName $ResourceGroupName -Location $location -IpConfiguration $ipConfig
} catch {
    Write-Error "Could not create NIC"
    exit 1
}

# Create the VM configuration
try {
    Write-Output "Setting VM configuration..."

    if ($createSpot) {
        $vm = New-AzVMConfig -VMName $VmName -VMSize $VmSize -Priority "Spot" -MaxPrice -1 -EvictionPolicy Deallocate -SecurityType $securityType
    } else {
        $vm = New-AzVMConfig -VMName $VmName -VMSize $VmSize -SecurityType $securityType
    }

    if( $osType -eq "Windows") {
        $vm = Set-AzVMOSDisk -VM $vm -ManagedDiskId $osDisk.Id -CreateOption Attach -Windows
    } else {
        $vm = Set-AzVMOSDisk -VM $vm -ManagedDiskId $osDisk.Id -CreateOption Attach -Linux
    }

    foreach ($dataDisk in $dataDisks) {
        $dataDiskObject = $dataDisk.Disk
        $vm = Add-AzVMDataDisk -VM $vm -ManagedDiskId $dataDiskObject.Id -Lun $dataDisk.Lun -Caching $dataDisk.Caching -CreateOption Attach
    }

    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
    $vm = Set-AzVMBootDiagnostic -VM $vm -Enable
} catch {
    Write-Error "Could not create the VM configuration"
    exit 1
}

try {
    Write-Output "Creating VM $VmName..."
    New-AzVM -VM $vm -ResourceGroupName $ResourceGroupName -Location $location
} catch {
    Write-Error "Could not create VM $VmName. Exiting..."
    exit 1
}
