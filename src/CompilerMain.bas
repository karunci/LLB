' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module CompilerMain

    ' Bind to standard C library functions provided by -lc
    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32
    Public Declare Function printf(ByVal fmt As Pointer To Byte, ByVal arg As Pointer To Byte) As Int32

    ' The Main function mapped to C's main() by our linker
    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        ' Print banner
        puts "[llbc-stage1] Low-Level Basic Self-Hosted Compiler Started!"

        ' Check CLI arguments
        If argc < 2 Then
            puts "Usage:"
            puts "  llbc-stage1 <source.bas> [-o output.elf]"
            Main = 1
            Exit Function
        End If

        ' argv(0) is the program name, argv(1) is the first argument
        Dim inputPath As Pointer To Byte
        inputPath = argv(1)

        printf("[llbc-stage1] Target source file: %s\n", inputPath)
        puts "[llbc-stage1] LLVM-C API bindings not yet implemented. Exiting."

        ' Return success
        Main = 0
    End Function

End Module