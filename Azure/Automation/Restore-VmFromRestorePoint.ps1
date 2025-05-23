param (
    [Parameter(Mandatory=$true)]
    [string] $VmName,

    [Parameter(Mandatory=$true)]
    [string] $resourceGroupName,

    [Parameter(Mandatory=$true)]
    [string] $SubscriptionName,

    [Parameter(Mandatory=$true)]
    [string] $RestorePointName,

    [Parameter(Mandatory=$true)]
    [string] $CollectionName,

    [Parameter(Mandatory=$true)]
    [bool] $RestoreAllDisks,

    [Parameter(Mandatory=$true)]
    [string] $TicketNumber
)


try {
    # Authenticate using system-assigned managed identity and target subscription
    Connect-AzAccount -Identity -Subscription $SubscriptionName

    Import-Module Az.Compute
    Import-Module Az.Resources
} catch {
    Write-Warning "Failed to execute pre-steps. Exiting..."
    exit 1
}

try {
    # Get VM
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $VmName
    $location = $vm.Location

    # Get restore point
    $restorePoint = Get-AzRestorePoint -RestorePointName $RestorePointName -ResourceGroupName $resourceGroupName -RestorePointCollectionName $CollectionName
    if (-not $restorePoint) {
        throw "Restore point not found: $RestorePointName"
    }
} catch {
    Write-Warning "Failed to fetch basic info. Exiting..."
    exit 1
}

try {
    Write-Output "Fetching current disk configuration..."

    # Print current disk configuration for reference
    $currentDisks = @()

    # Add OS disk
    $osDisk = @{
        Name = $vm.StorageProfile.OsDisk.Name
        ResourceGroup = ($vm.StorageProfile.OsDisk.ManagedDisk.Id -split '/')[4]
        OS_Disk = $true
        LUN = ""
    }
    $currentDisks += New-Object psobject -Property $osDisk

    # Add data disks
    foreach ($dataDisk in $vm.StorageProfile.DataDisks) {
        $diskObj = @{
            Name = $dataDisk.Name
            ResourceGroup = ($dataDisk.ManagedDisk.Id -split '/')[4]
            OS_Disk = $false
            LUN = $dataDisk.Lun
        }
        $currentDisks += New-Object psobject -Property $diskObj
    }

    # Display the table
    $currentDisks | Format-Table Name, ResourceGroup, OS_Disk, LUN -AutoSize

} catch {
    Write-Warning "Failed to print current disk configuration. Exiting..."
    exit 1
}

try {
    Write-Output "Restoring VM $VmName from Restore Point: $RestorePointName"
    Write-Output "RestoreAllDisks: $RestoreAllDisks"
    Write-Output "TicketNumber: $TicketNumber"

    # Get restore point disks
    $diskRestorePoints = @($restorePoint.SourceMetadata.StorageProfile.OsDisk)
    if ($RestoreAllDisks) {
        foreach ($datadisk in $restorePoint.sourceMetadata.storageProfile.dataDisks) {
            $diskRestorePoints += $datadisk
        }
    } 

    $restoredDiskNames = @()
    foreach ($disk in $diskRestorePoints) {
        # Fetch disk info
        $originalDiskName = $disk.Name
        $originalDisk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $originalDiskName

        # Set new disk name. Do not append 'restored' when already included in the name
        if ($originalDiskName -like "*Restored*") {
            $newDiskName = "$originalDiskName-$TicketNumber"
        } else {
            $newDiskName = "$originalDiskName-Restored-$TicketNumber"
        }

        # Get original SKU
        $diskSkuName = $originalDisk.Sku.Name
        $diskSkuNameStr = [string]$diskSkuName

        # Create the disk
        Write-Output "Creating disk $newDiskName from Restore Point: $RestorePointName"

        $sourceId = [string]$disk.diskRestorePoint.id

        if ($disk.OsType -ne $null) {
            $newDisk = New-AzDisk -DiskName $newDiskName -ResourceGroupName $resourceGroupName `
                (New-AzDiskConfig -Location $location `
                        -SkuName $diskSkuNameStr `
                        -CreateOption Restore `
                        -SourceResourceId $sourceId)
        } else {
            $diskTags = @{
                SourceDiskLun = [string]($disk.Lun)
            }

            $newDisk = New-AzDisk -DiskName $newDiskName -ResourceGroupName $resourceGroupName `
                (New-AzDiskConfig -Location $location `
                        -SkuName $diskSkuNameStr `
                        -CreateOption Restore `
                        -SourceResourceId $sourceId `
                        -Tag $diskTags)
        }

        $restoredDiskNames += $newDiskName
    }

} catch {
    Write-Warning "Failed to create disks from restore point. Exiting..."
    $_
    exit 1
}


try {
    # Stop the VM
    Write-Output "Stopping VM $VmName..."
    Stop-AzVM -ResourceGroupName $resourceGroupName -Name $VmName -Force
} catch {
    Write-Warning "Failed to stop the VM. Exiting..."
    exit 1
}

try {
    # Wipe VM storage profile
    if ($RestoreAllDisks) {
        $vm.StorageProfile.DataDisks.Clear()
        Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm
    }

    foreach ($restoredDiskName in $restoredDiskNames) {
        $disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $restoredDiskName

        if ($disk.OsType) {
            Write-Output "Modifying VM configuration for OS Disk."
            $vm.StorageProfile.OsDisk.ManagedDisk.Id = $disk.Id
            $vm.StorageProfile.OsDisk.Name = $disk.Name
        } else {
            Write-Output "Modifying VM configuration for Data Disk ($restoredDiskName)."
            # Data disk — preserve LUN if possible
            if ($disk.Tags["SourceDiskLun"]) {
                $lun = $disk.Tags["SourceDiskLun"]
            } else {
                $lun = ($vm.StorageProfile.DataDisks | Measure-Object).Count
            }
            $vm = Add-AzVMDataDisk -VM $vm -Name $disk.Name -CreateOption Attach -ManagedDiskId $disk.Id -Lun $lun

        }
    }

    Write-Output "Updating VM with restored disks..."
    Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm

} catch {
    Write-Warning "Failed attach the new disks on the VM. Exiting..."
    exit 1
}

try {
    # Start the VM
    Write-Output "Starting VM $VmName..."
    Start-AzVM -ResourceGroupName $resourceGroupName -Name $VmName
    Write-Output "VM restoration complete."
} catch {
    Write-Warning "Failed to start the VM. Exiting..."
    exit 1
}
