# --------- Graph module actions ---------
Install-Module Microsoft.Graph -Scope CurrentUser

Update-Module Microsoft.Graph

Uninstall-Module Microsoft.Graph -AllVersions
Get-InstalledModule Microsoft.Graph.* | ? Name -ne "Microsoft.Graph.Authentication" | Uninstall-Module
Uninstall-Module Microsoft.Graph.Authentication

Get-InstalledModule | ? Name -match "Microsoft.Graph"

Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All"
Disconnect-MgGraph

# --------- Basic actions ---------

# Show users
Get-MgUser
Get-MgUser -UserId XX
Get-MgGroup
Get-MgGroupMember -GroupId XX

# Set list of parameters
$params = @{  
    AccountEnabled = "false"  
}  
# Update the user with the parameters
Update-MgUser -UserId $id -BodyParameter $params

# Add user to group
New-MgGroupMember -GroupId $GroupID -DirectoryObjectId $UserID

# Remove user from group
Remove-MgGroupMemberByRef -GroupId $GroupID -DirectoryObjectId $UserID
