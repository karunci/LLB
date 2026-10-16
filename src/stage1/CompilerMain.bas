' Project Name: PRK-OS / Low-Level Basic Compiler
' Filename: src/stage1/CompilerMain.bas
' Workspace Path: src/stage1/CompilerMain.bas
' Summary: Stage-1 compiler entry point written in LLB.

Module CompilerMain

    ' Bind to standard C library functions provided by -lc
    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32
    Public Declare Function printf(ByVal fmt As Pointer To Byte, ByVal arg As Pointer To Byte) As Int32

    ' The Main function mapped to C's main() by our linker
    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        ' Print banner
        puts CPtr(Pointer To Byte, "[llbc-stage1] Low-Level Basic Self-Hosted Compiler Started!")

        ' Check CLI arguments
        If argc < 2 Then
            puts CPtr(Pointer To Byte, "Usage:")
            puts CPtr(Pointer To Byte, "  llbc-stage1 <source.bas> [-o output.elf]")
            Main = 1
            Exit Function
        End If

        ' argv(0) is the program name, argv(1) is the first argument
        Dim inputPath As Pointer To Byte
        inputPath = argv(1)

        printf CPtr(Pointer To Byte, "[llbc-stage1] Target source file: %s\n"), inputPath
        puts CPtr(Pointer To Byte, "[llbc-stage1] LLVM-C API bindings not yet implemented. Exiting.")

        ' Return success
        Main = 0
    End Function

End Module