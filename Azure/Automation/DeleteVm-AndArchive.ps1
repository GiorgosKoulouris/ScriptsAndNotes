param(
    [Parameter(Mandatory=$true)]
    [string]$VmName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

$rpcName = "$VmName-Archive"

# Connect to Azure (Automation Runbook will use Managed Identity or service principal)
Connect-AzAccount -Identity

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
    $nicName = $vm.NetworkProfile.NetworkInterfaces.Name
    $diskID = $vm.StorageProfile.OsDisk.ManagedDisk.Id
    $diskName = $vm.StorageProfile.OsDisk.ManagedDisk.Name

    Write-Output "Deleting VM $vmName..."
    Remove-AzResource -ResourceId $vmId -Force
    
    Write-Output "Deleting NIC ($nicName)..."
    Remove-AzResource -ResourceId $nicID -Force
    
    Write-Output "Deleting OS Disk ($diskName)..."
    Remove-AzResource -ResourceId $diskID -Force
} catch {
    Write-Error "Failed to delete vm $vmName"
}


