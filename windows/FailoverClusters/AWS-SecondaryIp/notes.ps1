mkdir "C:\Program Files\WindowsPowerShell\Modules\AWSSecondaryIPResource"
notepad "C:\Program Files\WindowsPowerShell\Modules\AWSSecondaryIPResource\AWSSecondaryIPResource.psm1"
# Copy the script above into the module file and save it.

Import-Module AWSSecondaryIPResource

Add-ClusterResourceType -Name "AWS Secondary IP" `
    -Dll "C:\Windows\System32\clusres.dll" `
    -DisplayName "Secondary IP"

Add-ClusterResource -Name "Cluster Sec IP" `
    -ResourceType "AWS Secondary IP" `
    -Group "Cluster Group"

Set-ClusterParameter -InputObject (Get-ClusterResource "Cluster Sec IP") `
    -Name "SecondaryIP" `
    -Value "10.0.10.95"

# Role Policy:
<#
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:AssignPrivateIpAddresses",
                "ec2:UnassignPrivateIpAddresses",
                "ec2:DescribeNetworkInterfaces"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:ec2:eu-central-1:XXXXX:network-interface/eni-XXXXX",
                "arn:aws:ec2:eu-central-1:XXXXX:network-interface/eni-XXXXX"
            ]
        },
        {
            "Action": [
                "ec2:DescribeNetworkInterfaces"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
#>

# Download the installer
Invoke-WebRequest "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "AWSCLIV2.msi"
Start-Process msiexec.exe -Wait -ArgumentList '/i AWSCLIV2.msi /qn'
Remove-Item AWSCLIV2.msi
# Restart powershell to load aws cli into path

mkdir "C:\ClusterResources\"
notepad "C:\ClusterResources\AwsSecondaryIpActions.ps1"
notepad "C:\ClusterResources\ClusterResource-RdpIP.vbs"

powershell -ExecutionPolicy Bypass -File "C:\ClusterResources\AwsSecondaryIpActions.ps1" -Operation Online -SecondaryIP 10.0.10.95

