' Project Name: PROS CoreUtils - ls
' Filename: apps/cli/coreutils/ls/LsMain.bas
' Summary: Standalone Ring 3 directory listing utility.

Import "../../../../include/pros.bas"

Module LsMain

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        Dim targetDir As String = "X:\\"
        If argc > 1 And argv(1) <> 0 Then
            targetDir = argv(1)
        End If

        Dim buf(65536) As Byte
        Dim count As UInt32 = DirectoryList(targetDir, @buf(0), 65536)

        If count = 0 Then
            If FileExists(targetDir) Then
                ConsoleWriteLine targetDir
            Else
                ConsoleWriteLine "ls: directory empty or not found"
            End If
            user_main = 0
            Exit Function
        End If

        ' Format and print null-separated entries
        Dim idx As UInt32 = 0
        Dim i As UInt32
        For i = 0 To count - 1
            Dim namePtr As Pointer To Byte = @buf(idx)
            ConsoleWriteLine namePtr
            While buf(idx) <> 0 And idx < 65530
                idx = idx + 1
            Wend
            idx = idx + 1
        Next i

        user_main = 0
    End Function

End Module
