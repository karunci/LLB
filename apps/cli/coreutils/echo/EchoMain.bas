' Project Name: PROS CoreUtils - echo
' Filename: apps/cli/coreutils/echo/EchoMain.bas
' Summary: Standalone Ring 3 echo arguments utility.

Import "../../../../include/pros.bas"

Module EchoMain

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        If argc <= 1 Then
            ConsoleWriteLine ""
            user_main = 0
            Exit Function
        End If

        Dim i As UInt64
        For i = 1 To argc - 1
            If argv(i) <> 0 Then
                ConsoleWrite argv(i)
                If i + 1 < argc Then
                    ConsoleWrite " "
                End If
            End If
        Next i
        ConsoleWriteLine ""

        user_main = 0
    End Function

End Module
