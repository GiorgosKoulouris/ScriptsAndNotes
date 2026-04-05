<#
.SYNOPSIS
Restores an Azure VM from a Restore Point and optionally attaches an NSG.

.DESCRIPTION
This script restores a virtual machine from an Azure Restore Point.
It recreates disks, network interface, and the VM configuration.

The script supports:
- Spot or standard VM creation
- Optional NSG attachment to the NIC
- OS and data disk restore from restore points

.PARAMETER VmName
Name of the virtual machine to create.

.PARAMETER ResourceGroupName
Resource group where the VM and disks will be created.

.PARAMETER RestorePointCollection
Name of the Restore Point Collection.

.PARAMETER RestorePointName
Name of the Restore Point to restore from.

.PARAMETER VnetResourceGroup
Resource group of the virtual network.

.PARAMETER VnetName
Name of the virtual network.

.PARAMETER SubnetName
Subnet name where the NIC will be created.

.PARAMETER VmSize
Azure VM size (e.g. Standard_D4s_v5).

.PARAMETER CreateSpot
Set to $true to create a Spot VM.

.PARAMETER NsgName
Name of the Network Security Group to attach to the NIC.
Use 'None' to create the NIC without an NSG.

.EXAMPLE
.\CreateVM_FromRestorePoint.ps1 `
  -VmName testvm `
  -ResourceGroupName rg1 `
  -RestorePointCollection rpc1 `
  -RestorePointName rp1 `
  -VnetResourceGroup net-rg `
  -VnetName vnet1 `
  -SubnetName subnet1 `
  -VmSize Standard_D4s_v5 `
  -CreateSpot $false `
  -NsgName None

.NOTES
Requires: Az PowerShell module
Authentication: Managed Identity or Service Principal
#>


param(
    [Parameter(Mandatory=$true)]
    [string]$VmName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$RestorePointCollection,

    [Parameter(Mandatory=$true)]
    [string]$RestorePointName,

    [Parameter(Mandatory=$true)]
    [string]$VnetResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$VnetName,

    [Parameter(Mandatory=$true)]
    [string]$subnetName,

    [Parameter(Mandatory=$true)]
    [string]$NsgName,

    [Parameter(Mandatory=$true)]
    [string]$VmSize,
    
    [Parameter(Mandatory=$true)]
    [boolean]$CreateSpot
)

# Connect to Azure (Automation Runbook will use Managed Identity or service principal)
Connect-AzAccount -Identity

# Fetch the restore point and disk restore points
try {
    $restorePoint = Get-AzRestorePoint -ResourceGroupName $ResourceGroupName -RestorePointCollectionName $RestorePointCollection -Name $RestorePointName
    
    $location = $restorePoint.SourceMetadata.Location
    $securityType = $restorePoint.SourceMetadata.SecurityProfile.SecurityType

    $osDiskRestorePoint = $restorePoint.SourceMetadata.StorageProfile.OsDisk.DiskRestorePoint.Id
    $diskRestorePoints = @($restorePoint.SourceMetadata.StorageProfile.OsDisk)
    foreach ($datadisk in $restorePoint.sourceMetadata.storageProfile.dataDisks) {
        $diskRestorePoints += $datadisk
    }

} catch {
    Write-Warning "Failed to fetch restore point and disk restore points. Exiting..."
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
    $ipConfig = New-AzNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -Subnet $subnet

    if ($NsgName -ne 'None') {
        Write-Output "Attaching NSG '$NsgName' to NIC"
        $nsg = Get-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $ResourceGroupName

        $nic = New-AzNetworkInterface `
            -Name "$VmName-NIC" `
            -ResourceGroupName $ResourceGroupName `
            -Location $location `
            -IpConfiguration $ipConfig `
            -NetworkSecurityGroup $nsg
    }
    else {
        Write-Output "No NSG will be attached to NIC"
        $nic = New-AzNetworkInterface `
            -Name "$VmName-NIC" `
            -ResourceGroupName $ResourceGroupName `
            -Location $location `
            -IpConfiguration $ipConfig
    }
}
catch {
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
