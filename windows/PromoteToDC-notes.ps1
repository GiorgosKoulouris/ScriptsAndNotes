Rename-Computer -NewName "TSBRUADC00";

Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools;
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

Install-ADDSForest -CreateDnsDelegation:$false -DomainName tsbr.local -DomainMode Win2012R2 -DomainNetbiosName "TSBR" -ForestMode Win2012R2 -InstallDns:$true;
