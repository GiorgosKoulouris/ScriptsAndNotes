' AWS-IP-Cluster.vbs
Const SecondaryIP = "10.0.10.95"  ' <- Set your floating IP here

Function RunOperation(op)
    Set shell = CreateObject("WScript.Shell")
    cmd = "powershell.exe -ExecutionPolicy Bypass -File ""C:\ClusterResources\AwsSecondaryIpActions.ps1"" -Operation " & op & " -SecondaryIP " & SecondaryIP
    RunOperation = shell.Run(cmd, 0, True)
End Function

Function Open()
    Open = 0
End Function

Function Online()
    Online = RunOperation("Online")
End Function

Function Offline()
    Offline = RunOperation("Offline")
End Function

Function Terminate()
    Terminate = 0
End Function

Function LooksAlive()
    LooksAlive = RunOperation("LooksAlive")
End Function

Function IsAlive()
    IsAlive = RunOperation("IsAlive")
End Function

Function Close()
    Close = 0
End Function
