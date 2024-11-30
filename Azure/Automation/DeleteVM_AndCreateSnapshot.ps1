# 
# DeleteVM_AndCreateSnapshot
# Deletes a VM after creating a snapshot of its OS disk
# Also tags tags the snapshot with SnapState=latest and removes the tag from other snaps. This is to work with the CreateVM_FromSnapshot script
#

$automationAccResourceGroupName = "TSBR-Utilities"
$automationAccount = "TSBR-Automation"
$UAMI = "TSBR-Automation-Mngd-identity"

$timestamp = Get-Date -Format o
$datetime  = ([DateTime]$timestamp).ToUniversalTime()
$dateSuffix = Get-Date -Date $datetime -Format "yyyyMMdd_HHmm"

$subscriptionID = 'XXXX-XXXX'
$location = "northeurope"
$resourceGroupName = "TSBR-VMs"
$vmName = "TSBRDAWS00"
$snapshotRgName = $vmRgName
$snapshotName = "$vmName-OsDisk-$dateSuffix"

# Ensures you do not inherit an AzContext in your runbook
$null = Disable-AzContextAutosave -Scope Process

# Connect using a Managed Service Identity
try {
    $AzureConnection = (Connect-AzAccount -Identity).context
}
catch {
    Write-Output "There is no system-assigned user identity. Aborting." 
    exit
}

$AzureContext = Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection

Write-Output "Using user-assigned managed identity"

# Connects using the Managed Service Identity of the named user-assigned managed identity
$identity = Get-AzUserAssignedIdentity -ResourceGroupName $automationAccResourceGroupName -Name $UAMI -DefaultProfile $AzureContext

# validates assignment only, not perms
$AzAutomationAccount = Get-AzAutomationAccount -ResourceGroupName $automationAccResourceGroupName -Name $automationAccount -DefaultProfile $AzureContext
if ($AzAutomationAccount.Identity.UserAssignedIdentities.Values.PrincipalId.Contains($identity.PrincipalId)) {
    $AzureConnection = (Connect-AzAccount -Identity -AccountId $identity.ClientId).context

    # set and store context
    $AzureContext = Set-AzContext -SubscriptionName $AzureConnection.Subscription -DefaultProfile $AzureConnection
}
else {
    Write-Output "Invalid or unassigned user-assigned managed identity"
    exit
}

try {
    Write-Output "Stopping VM $vmName..."
    Stop-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -Force
} catch {
    Write-Error "Failed to stop $vmName. Exiting..."
    exit 1
}

try {
    Write-Output "Fetching VM $vmName..."
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
} catch {
    Write-Error "Could not fetch VM. Exiting..."
    exit 1
}

try {
    Write-Output "Creating snapshot config..."
    $snapshotConfig =  New-AzSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy -Sku "Standard_LRS"
} catch {
    Write-Error "Could not create snapshot. Exiting..."
    exit 1
}

try {
    Write-Output "Creating snapshot $snapshotName..."
    $newSnapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $resourceGroupName
} catch {
    Write-Error "Could not create snapshot. Exiting..."
    exit 1
}

try {
    $dawsSnapshots = Get-AzSnapshot TSBR-VMs | Where-Object {$_.name -match $vmName}
    if ($dawsSnapshots) {
        Write-Output "Untagging old snapshots..."
        foreach ($snap in $dawsSnapshots) {
            $id = $snap.Id
            Remove-AzTag -ResourceId $id
        }
    } else {
        Write-Output "No old snapshots ov $vmName to untag"
    }
} catch {
    Write-Error "Failed to untag the old snapshots. Exiting..."
    exit 1
}

try {
    Write-Output "Tagging snapshot..."
    $Tags = @{"SnapState"="latest"}
    New-AzTag -ResourceId $newSnapshot.id -Tag $Tags
} catch {
    Write-Error "Could not tag the new snapshot. Exiting..."
    exit 1
}

try {
    $snapsToDelete = Get-AzSnapshot $resourceGroupName | Where-Object {$_.name -match $vmName -and $_.tags['SnapState'] -ne "latest"}
    if ($snapsToDelete) {
        Write-Output "Deleting old snapshots..."
        foreach ($snap in $snapsToDelete) {
            $name = $snap.name
            Write-Output "Deleting snapshot $name..."
            Remove-AzSnapshot -ResourceGroupName $resourceGroupName -Name $name -Force
        }
    } else {
        Write-Output "No old snapshots of $vmName to delete"
    }
} catch {
    Write-Error "Failed to delete old snapshots. Exiting..."
    exit 1
}

try {
    $vmId = $vm.Id
    $nicID = $vm.NetworkProfile.NetworkInterfaces.id
    $nicName = $vm.NetworkProfile.NetworkInterfaces.Name
    $diskID = $vm.StorageProfile.OsDisk.ManagedDisk.Id
    $diskName = $vm.StorageProfile.OsDisk.ManagedDisk.Name

    Write-Output "Deleting VM $vmName..."
    Remove-AzResource -ResourceId $vmId -Force
    
    Write-Output "Deleting NIC..."
    Remove-AzResource -ResourceId $nicID -Force
    
    Write-Output "Deleting OS Disk..."
    Remove-AzResource -ResourceId $diskID -Force
} catch {
    Write-Error "Failed to delete vm $vmName"
}