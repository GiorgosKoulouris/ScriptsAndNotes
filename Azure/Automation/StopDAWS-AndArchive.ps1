$SubscriptionName = "TSBR-PROD"
$VmName = "TSBRDAWS00"
$ResourceGroupName = "TSBR-VMs"
$RestorePointCollectionName = "$VmName-Archive"

# Connect to Azure (Automation Runbook will use Managed Identity or service principal)
Connect-AzAccount -Identity -Subscription $SubscriptionName

$rpcName = $RestorePointCollectionName
$vm = Get-AzVM -Name $VmName -ResourceGroupName $ResourceGroupName -ErrorAction Stop

# Check if RPC exists
$rpc = Get-AzRestorePointCollection -ResourceGroupName $ResourceGroupName -Name $rpcName -ErrorAction SilentlyContinue
if (-not $rpc) {
    try {
        Write-Output "Creating Restore Point Collection: $rpcName"
        $rpc = New-AzRestorePointCollection `
            -Name $rpcName `
            -ResourceGroupName $ResourceGroupName `
            -Location $vm.Location `
            -VmId $vm.Id
    } catch {
        Write-Error "Failed to create restore point collection. Exiting..."
        exit 1          
    }
}

# Create restore point
try {
    $timestamp = Get-Date -Format o
    $datetime  = ([DateTime]$timestamp).ToUniversalTime()
    $dateSuffix = Get-Date -Date $datetime -Format "yyyyMMdd_HHmm"
    $rpName = "$VmName-$dateSuffix"
    Write-Output "Creating Restore Point: $rpName"
    $restorePoint = New-AzRestorePoint `
        -ResourceGroupName $ResourceGroupName `
        -RestorePointCollectionName $rpcName `
        -Name $rpName

    Write-Output "Restore point created."

} catch {
    Write-Error "Failed to create restore point. Exiting..."
    exit 1 
}

try {
    $vmId = $vm.Id
    $nicID = $vm.NetworkProfile.NetworkInterfaces.id
    $diskID = $vm.StorageProfile.OsDisk.ManagedDisk.Id

    Write-Output "Deleting VM $vmName..."
    Remove-AzResource -ResourceId $vmId -Force
    
    Write-Output "Deleting NIC..."
    Remove-AzResource -ResourceId $nicID -Force
    
    Write-Output "Deleting OS Disk..."
    Remove-AzResource -ResourceId $diskID -Force

    Write-Output "VM $vmName and associated resources deleted successfully."

} catch {
    Write-Error "Failed to delete vm $vmName"
}
