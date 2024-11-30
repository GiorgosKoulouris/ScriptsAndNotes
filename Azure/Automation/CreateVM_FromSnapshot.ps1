# 
# CreateVM_FromSnapshot
# Creates a VM with a pre-defined config by auto-selecting the snapshot to create the OS disk 
# 
# The snapshot must contain the VM name on its name and must be on the same RG
# The snapshot selected is the one having the tag SnapState=latest
# Unless changed, the new VM is created as a spot instance
# Unless changed, the new OS disk is StandardSSD_LRS
# 

$automationAccResourceGroupName = "TSBR-Utilities"
$automationAccount = "TSBR-Automation"
$UAMI = "TSBR-Automation-Mngd-identity"

$subscriptionID = 'XXXX-XXXX'
$location = "northeurope"
$vmRgName = "TSBR-VMs"
$newVmName = "TSBRDAWS00"
$vmSize = "Standard_E2_v4"
$snapshotRgName = $vmRgName
$vnetRgName = "TSBR-Infrastructure"
$vnetName = "TSBR-VNET"
$subnetName = "TSBR-Private-Subnet"
$privateIP = "10.120.10.5"

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

$latestSnapshots = $snapshots = Get-AzSnapshot -ResourceGroup $snapshotRgName | Where-Object {$_.tags['SnapState'] -eq "latest" -and $_.Name -match $newVmName}
$latestSnapCount = ($latestSnapshots | Measure-Object).count

if ($latestSnapCount -eq 0) {
    Write-Error "No snapshots found with the latest tag. Exiting..."
    exit
}
if ($latestSnapCount -gt 1) {
    Write-Error "Multiple snapshots found with the latest tag. Exiting..."
    exit
}

$snapshotName = $latestSnapshots.Name

# TrustedLaunch,ConfidentialVM,Standard
$securityType = "TrustedLaunch"

$osDiskName = "$newVmName-OsDisk"
# Standard_LRS, Premium_LRS, PremiumV2_LRS, StandardSSD_LRS, UltraSSD_LRS, Premium_ZRS, StandardSSD_ZRS
$storageType = "StandardSSD_LRS"

$subnetID = "/subscriptions/$subscriptionID/resourceGroups/$vnetRgName/providers/Microsoft.Network/virtualNetworks/$vnetName/subnets/$subnetName"

# Execute
try {
    Write-Output "Selecting subscription..."
    Select-AzSubscription -SubscriptionId $subscriptionId
} catch {
    Write-Error "Could not select the subscription"
    exit 1
}
try {
    Write-Output "Creating OS Disk..."
    $snapshot = Get-AzSnapshot -ResourceGroupName $snapshotRgName -Name $snapshotName
    #If you're creating a Premium SSD v2 or an Ultra Disk, add "-Zone $zone" to the end of the command
    $osDiskSize = $snapshot.DiskSizeGB
    $osDiskConfig = New-AzDiskConfig -SkuName $storageType -Location $location -CreateOption Copy -SourceResourceId $snapshot.Id -DiskSizeGB $osDiskSize
    $osDisk = New-AzDisk -Disk $osDiskConfig -ResourceGroupName $vmRgName -DiskName $osDiskName
} catch {
    Write-Error "Could not create the OS disk"
    exit 1
}
try {
    Write-Output "Creating the network interface..."
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $vnetRgName
    $ipConfig = New-AzNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $privateIP -SubnetId $subnetID
    $nic = New-AzNetworkInterface -Name "$newVmName-NIC"  -ResourceGroupName $vmRgName -Location $location -IpConfiguration $ipConfig
} catch {
    Write-Error "Could not create NIC"
    exit 1
}
try {
    Write-Output "Setting VM configuration..."
    $vm = New-AzVMConfig -VMName $newVmName -VMSize $vmSize -Priority "Spot" -MaxPrice -1 -EvictionPolicy Deallocate -SecurityType $securityType
    $vm = Set-AzVMOSDisk -VM $vm -ManagedDiskId $osDisk.Id -CreateOption Attach -Windows
    $vm = Add-AzVMNetworkInterface -VM $vm -Id $nic.Id
    $vm = Set-AzVMBootDiagnostic -VM $vm -Disable
} catch {
    Write-Error "Could not create the VM configuration"
    exit 1
}

try {
    Write-Output "Creating VM $newVmName..."
    New-AzVM -VM $vm -ResourceGroupName $vmRgName -Location $location
} catch {
    Write-Error "Could not create VM $newVmName. Exiting..."
    exit 1
}

