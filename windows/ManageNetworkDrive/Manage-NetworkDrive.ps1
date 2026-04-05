<#
.SYNOPSIS
    Mount network drives and manage credentials using built-in Windows tools (cmdkey, net use).

.PARAMETER CreateCredentials
    Prompts for username and password, then stores them using cmdkey.exe.

.PARAMETER DeleteCredentials
    Deletes stored credentials for the specified network path.

.PARAMETER Mount
    Mounts the specified network path to a drive letter using stored credentials.

.PARAMETER NetworkPath
    UNC path to the network share (e.g. \\server\share).

.PARAMETER DriveLetter
    The drive letter to assign (e.g. Z:).

.EXAMPLE
    .\Manage-NetworkDrive.ps1 -CreateCredentials -NetworkPath \\server\share

.EXAMPLE
    .\Manage-NetworkDrive.ps1 -Mount -NetworkPath \\server\share -DriveLetter Z:

.EXAMPLE
    .\Manage-NetworkDrive.ps1 -DeleteCredentials -NetworkPath \\server\share
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$CreateCredentials,

    [Parameter(Mandatory = $false)]
    [switch]$DeleteCredentials,

    [Parameter(Mandatory = $false)]
    [switch]$Mount,

    [Parameter(Mandatory = $false)]
    [string]$NetworkPath = "\\Server\Share",

    [Parameter(Mandatory = $false)]
    [string]$DriveLetter = "Z:",

    [Parameter(Mandatory = $false)]
    [switch]$Unmount
)

function Create-CredentialCmdKey {
    param (
        [string]$TargetUNC
    )

    # Extract server name only
    if ($TargetUNC -match "\\\\([^\\]+)\\") {
        $server = $Matches[1]
    } else {
        Write-Error "Invalid network path: $TargetUNC"
        return
    }

    $cred = Get-Credential -Message "Enter credentials for $server"
    $username = $cred.UserName
    $password = $cred.GetNetworkCredential().Password

    cmdkey /add:$server /user:$username /pass:$password | Out-Null
    Write-Host "Stored credentials for $server"
}


function Delete-CredentialCmdKey {
    param (
        [string]$TargetUNC
    )

    if ($TargetUNC -match "\\\\([^\\]+)\\") {
        $server = $Matches[1]
    } else {
        Write-Error "Invalid network path: $TargetUNC"
        return
    }

    cmdkey /delete:$server | Out-Null
    Write-Host "Deleted credentials for $server"
}


function Mount-NetworkDrive {
    param (
        [string]$Path,
        [string]$Drive
    )

    # Disconnect drive if already mapped
    net use $Drive /delete /yes | Out-Null

    # Map drive using credentials stored with cmdkey
    $output = net use $Drive $Path /persistent:yes
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully mounted $Path to $Drive"
    } else {
        Write-Warning "Failed to mount drive. Output:"
        Write-Host $output
    }
}

function Unmount-NetworkDrive {
    param (
        [string]$Drive
    )

    Write-Host "Attempting to unmount $Drive ..."
    $output = net use $Drive /delete /yes
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully unmounted $Drive"
    } else {
        Write-Warning "Failed to unmount drive. Output:"
        Write-Host $output
    }
}


# Run selected operations
if ($CreateCredentials) {
    Create-CredentialCmdKey -Target $NetworkPath
}

if ($DeleteCredentials) {
    Delete-CredentialCmdKey -Target $NetworkPath
}

if ($Mount) {
    Mount-NetworkDrive -Path $NetworkPath -Drive $DriveLetter
}

if ($Unmount) {
    Unmount-NetworkDrive -Drive $DriveLetter
}
