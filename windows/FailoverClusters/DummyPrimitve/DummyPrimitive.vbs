' DummyPrimitive.vbs � cluster-safe dummy resource
Option Explicit

' Cluster return codes
Const CLUSTER_RESOURCE_UP = 0
Const CLUSTER_RESOURCE_FAILED = 4

Dim fso, flag
flag = "C:\ClusterScripts\dummyPrimitive_running.txt"
Set fso = CreateObject("Scripting.FileSystemObject")

' ========================
' Entry Points
' ========================

' Bring resource online
Sub Online()
    On Error Resume Next
    WScript.Echo "DummyPrimitive: Online called"
    
    ' Create a flag file to indicate resource is running
    Dim f
    Set f = fso.CreateTextFile(flag, True)
    If Err.Number <> 0 Then
        WScript.Echo "Error creating flag file: " & Err.Description
        Err.Clear
    Else
        f.WriteLine "RUNNING"
        f.Close
    End If
    On Error GoTo 0
End Sub

' Take resource offline
Sub Offline()
    On Error Resume Next
    WScript.Echo "DummyPrimitive: Offline called"
    
    ' Delete the flag file
    If fso.FileExists(flag) Then fso.DeleteFile(flag)
    On Error GoTo 0
End Sub

' Cluster calls this periodically to check health
Function IsAlive()
    On Error Resume Next
    WScript.Echo "DummyPrimitive: IsAlive called"
    
    If fso.FileExists(flag) Then
        IsAlive = CLUSTER_RESOURCE_UP
    Else
        IsAlive = CLUSTER_RESOURCE_FAILED
    End If
    On Error GoTo 0
End Function

' Cluster calls this frequently to see if resource looks alive
Function LooksAlive()
    On Error Resume Next
    WScript.Echo "DummyPrimitive: LooksAlive called"
    
    ' Simply return same as IsAlive
    LooksAlive = IsAlive()
    On Error GoTo 0
End Function

' ========================
' Optional: Custom monitoring logic
' ========================
' You can extend IsAlive or LooksAlive with checks like:
' - Process running
' - Service status
' - Custom file contents
' Example:
'   If fso.FileExists("C:\ClusterScripts\stopme.txt") Then IsAlive = CLUSTER_RESOURCE_FAILED
