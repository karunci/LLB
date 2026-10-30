' Project Name: PROS CoreUtils - cat
' Filename: apps/cli/coreutils/cat/CatMain.bas
' Summary: Standalone Ring 3 concatenate and print file utility.

Import "../../../../include/pros.bas"

Module CatMain

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        If argc < 2 Or argv(1) = 0 Then
            ConsoleWriteLine "Usage: cat <path>"
            user_main = 1
            Exit Function
        End If

        Dim targetPath As String = argv(1)
        Dim buf(65536) As Byte
        Dim bytesRead As UInt32 = ReadAllText(targetPath, @buf(0), 65535)

        If bytesRead > 0 Then
            buf(bytesRead) = 0
            ConsoleWrite @buf(0)
        Else
            ConsoleWriteLine "cat: file not found or empty"
        End If

        user_main = 0
    End Function

End Module
