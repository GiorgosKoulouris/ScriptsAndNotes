mkdir "C:\ClusterScripts\"
notepad "C:\ClusterScripts\DummyPrimitive.vbs" # Save as ANSI

# Create a new role/group
Add-ClusterGroup -Name "DummyPrimitiveGroup"
# Create a Generic Script resource
Add-ClusterResource -Name "DummyPrimitive" -Group "DummyPrimitiveGroup" -ResourceType "Generic Script"
# Point it to your script
Set-ClusterParameter -InputObject (Get-ClusterResource "DummyPrimitive") `
    -Name ScriptFilePath -Value "C:\ClusterScripts\DummyPrimitive.vbs"

Get-ClusterParameter -InputObject (Get-ClusterResource "DummyPrimitive")
# Bring it online
Start-ClusterGroup -Name "DummyPrimitiveGroup"

Get-ClusterResource "DummyPrimitive"

Remove-Item C:\ClusterScripts\dummyPrimitive_running.txt
