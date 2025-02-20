# Identify disks

gcloud compute disks list # To get the names
gcloud compute disks describe diskName --zone=us-central1-a | grep "id:"

# Convert the decimal id to hexadecimal

# On windows, execute this to get the IDs
:'
Get-Disk | ForEach-Object { $disk = $_; Get-Partition -DiskNumber $disk.Number | Select-Object DriveLetter, UniqueId }
'

# Ignore brackets and the 1st part of the non-bracketed section

# The last part of the non-bracketed section is the disk ID. Hexadecimal pairs are printed reversed