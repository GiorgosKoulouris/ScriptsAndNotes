# Client systems
$Desktop = [Environment]::GetFolderPath("Desktop")
cd $Desktop
mkdir DR_Drill_2025
cd .\DR_Drill_2025

notepad .\Update-DNS-Resolution.ps1

#### CHECK
.\Update-DNS-Resolution.ps1 -DnsServers '10.160.228.100 10.160.228.2' -DnsSearch 'bauer.loc' -CommentHostfile '10.160.126.0/24'
.\Update-DNS-Resolution.ps1 -DnsSearch 'UseDHCP' -DnsSearch 'bauer.loc' -CommentHostfile '10.160.126.0/24'

notepad .\resolution_check.ps1
notepad .\hostnames_and_ip.json

ipconfig /flushdns
.\resolution_check.ps1 -JsonFilePath ".\hostnames_and_ip.json"
