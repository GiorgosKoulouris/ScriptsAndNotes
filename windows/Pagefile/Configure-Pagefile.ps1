param (
    [string]$SwapDriveLetter,
    [string]$SwapDriveName,
    [int]$SwapSizeGB,
    [switch]$PerformReboot
)

$LogFile = "C:\Scripts\Configure-Pagefile.log"

function Write-Logs {
    param (
        [string]$Level,
        [string]$Message
    )

    $DateString = Get-Date -Format "MM-dd-yyyy HH:mm:ss"
    $MessageString = "${DateString}: [$Level] - $Message"
    Add-Content -Path $LogFile -Value "$MessageString"

    if ($Level -eq "WARN") {
        Write-Warning "$Message"
    } else {
        Write-Host "$Message"
    }
}

function Create-LogFile {
    if (-Not (Test-Path -Path $LogFile)) {
        $null = New-Item -Path $LogFile -ItemType File
        Write-Logs -Level "INFO" -Message "Creating Log File ($LogFile)"
    }
}

# Function to get the instance store volume
function Get-InstanceStoreVolume {
    Get-Disk | Where-Object { $_.FriendlyName -like "*NVMe*" -or $_.FriendlyName -like "*Amazon Elastic Block Store*" } |
    Where-Object { $_.PartitionStyle -eq 'RAW' } |
    Select-Object -First 1
}


function Apply-Configuration {
    param (
        [string]$SwapDriveLetter,
        [string]$SwapDriveName
    )

    $isOkInTotal = $true
    $driveLetterHasSwap = $false
    # Check if swap is already active on target
    $existingPageFile = Get-CimInstance Win32_PageFileUsage | Where-Object { $_.Name -like "${SwapDriveLetter}:*" }
    if ($existingPageFile) {
        $driveLetterHasSwap = $true
        Write-Logs -Level "INFO" -Message "Pagefile already exists on target disk ($SwapDriveLetter)."
        $existing = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting" | Where-Object { $_.Name -like "${SwapDriveLetter}:*" }
        $SwapSizeMB = ($SwapSizeGB * 1024) - 6
        if (($existing.InitialSize -ne $SwapSizeMB) -or ($existing.MaximumSize -ne $SwapSizeMB)) {
            Write-Logs -Level "INFO" -Message "Pagefile configuration on $SwapDriveLetter is system managed or has different size setting."
            $isOkInTotal = $false
        } else {
            Write-Logs -Level "INFO" -Message "Pagefile configuration on $SwapDriveLetter is OK."
        }
    } else {
        Write-Logs -Level "INFO" -Message "Pagefile does not exist on target disk ($SwapDriveLetter)."
        $isOkInTotal = $false
    }

    $existingOthers = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting" | Where-Object { $_.Name -notlike "${SwapDriveLetter}:*" }
    if ($existingOthers) {
        Write-Logs -Level "INFO" -Message "Found pagefile configuration on other disks."
        $isOkInTotal = $false
    } else {
        Write-Logs -Level "INFO" -Message "No pagefile configurations found on other disks."
    }

    # Check if swap is already configured on target
    $existingPageFileConfig = Get-WmiObject Win32_PageFileSetting | Where-Object { $_.Name -like "${SwapDriveLetter}:*" }
    if (-not $isOkInTotal) {
        if (-not $driveLetterHasSwap) {
            Initiliaze-SwapDisk
        }
        Configure-Pagefile
    } else {
        if ($existingPageFileConfig -and (-not $existingPageFile)) {
            if ($PerformReboot) {
                Write-Logs -Level "WARN" -Message "Pagefile misconfiguration. Rebooting."
                Restart-Computer -Force
            } else {
                Write-Logs -Level "WARN" -Message "Pagefile misconfiguration. Skipping reboot. Investigate the issue manually."
                exit 1
            }
        } else {
            Write-Logs -Level "INFO" -Message "Configuration is OK."
        }
    }
}

function Initiliaze-SwapDisk {
    try {
        $driveLetterExists = $false
        if (Get-PSDrive -Name $SwapDriveLetter -ErrorAction SilentlyContinue) {
            Write-Logs -Level "INFO" -Message "Drive $SwapDriveLetter already exists."
            $driveFreeGB = [Math]::Floor( (Get-PSDrive -Name $SwapDriveLetter).Free / [Math]::Pow(1024,3) )
            if ($driveFreeGB -ge $SwapSizeGB) {
                Write-Logs -Level "INFO" -Message "Drive has sufficient free space."
            } else {
                Write-Logs -Level "WARN" -Message "Drive does not have sufficient free space. Exiting."
                exit 1
            }
            $driveLetterExists = $true
        } else {
            Write-Logs -Level "INFO" -Message "No disks found using letter '$SwapDriveLetter'. Proceeding."
        }

        if (-not $driveLetterExists) {
            # Check if there are any unformatted disks
            $rawdisks = Get-Disk | Where-Object { $_.FriendlyName -like "*NVMe*" -or $_.FriendlyName -like "*Amazon Elastic Block Store*" } |
                        Where-Object { $_.PartitionStyle -eq 'RAW' }
            if (-not $rawdisks) {
                Write-Logs -Level "WARN" -Message "No non-formatted disks could be found. Exiting."
                exit 1
            } else {
                Write-Logs -Level "INFO" -Message "Found RAW disks. Proceeding."
                $disk = Get-InstanceStoreVolume

                # Initialize the disk, create a partition, and format it
                Write-Logs -Level "INFO" -Message "Initializing disk..."
                Initialize-Disk -Number $disk.Number -PartitionStyle GPT
                Write-Logs -Level "INFO" -Message "Creating partition..."
                $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $SwapDriveLetter
                Write-Logs -Level "INFO" -Message "Formatting volume..."
                Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "$SwapDriveName" -Confirm:$false
            }
        }

    } catch {
        Write-Logs -Level "WARN" -Message "Failed to initialize disk. Exiting"
        exit 1
    }
}

function Configure-Pagefile {
    try {
        Write-Logs -Level "INFO" -Message "Removing existing pagefile settings..."
        $existing = Get-WmiObject -Query "SELECT * FROM Win32_PageFileSetting"
        foreach ($pf in $existing) {
            Write-Logs -Level "INFO" -Message "Removing: $($pf.Name)"
            $pf.Delete() | Out-Null
        }

        # Disable auto-managed pagefile
        $os = Get-WmiObject Win32_ComputerSystem
        if ($os.AutomaticManagedPagefile) {
            Write-Logs -Level "INFO" -Message "Disabling automatic pagefile management"
            $os.AutomaticManagedPagefile = $false
            $os.Put() | Out-Null
        }

        Write-Logs -Level "INFO" -Message "Creating pagefile configuration for drive $SwapDriveLetter"
        $pagefilePath = "$SwapDriveLetter`:\pagefile.sys"
        # Create fixed-size pagefile
        $SwapSizeMB = ($SwapSizeGB * 1024) - 6
        $pagefile = ([WMIClass]"Win32_PageFileSetting").CreateInstance()
        $pagefile.Name = $pagefilePath
        $pagefile.InitialSize = $SwapSizeMB
        $pagefile.MaximumSize = $SwapSizeMB
        $pagefile.Put() | Out-Null

    }
    catch {
        Write-Logs -Level "WARN" -Message "Configuration failed. Skipping reboot"
    }
    if ($PerformReboot) {
        Write-Logs -Level "INFO" -Message "Configuration completed. Rebooting to apply."
        Restart-Computer -Force
    } else {
        Write-Logs -Level "INFO" -Message "Configuration completed. Permorm a manual reboot to apply the changes."
    }
    
}

Create-Logfile
Apply-Configuration -SwapDriveLetter $SwapDriveLetter -SwapDriveName $SwapDriveName


#powershell.exe -ExecutionPolicy Bypass -Command "C:\Scripts\Configure-Pagefile.ps1 -SwapDriveLetter 'X' -SwapDriveName 'SWAP' -SwapSizeGB 32"
#powershell.exe -ExecutionPolicy Bypass -Command "C:\Scripts\Configure-Pagefile.ps1 -SwapDriveLetter 'X' -SwapDriveName 'SWAP' -SwapSizeGB 16 -PerformReboot"

