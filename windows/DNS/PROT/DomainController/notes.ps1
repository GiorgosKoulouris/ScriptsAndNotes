# DR Domain Controller
$Desktop = [Environment]::GetFolderPath("Desktop")
cd $Desktop
mkdir DR_Drill_2025
cd .\DR_Drill_2025

notepad .\Update-DNS-Records.ps1
notepad .\dns-entries.json

.\Update-DNS-Records.ps1 -ZoneName "bauer.loc"

