' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/lib_metal/TestMetal.bas
' Summary: Standalone freestanding test verification program linking against LibLLB_Metal (libllb_metal.a).

Module TestMetal

    ' LibLLB_Metal Static Library Declarations
    Public Declare Function Min Lib "libllb_metal" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Max Lib "libllb_metal" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Clamp Lib "libllb_metal" (ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64
    Public Declare Function IsDigit Lib "libllb_metal" (ByVal c As Byte) As Boolean
    Public Declare Function IsHexDigit Lib "libllb_metal" (ByVal c As Byte) As Boolean
    Public Declare Function Std_Strings_Length Lib "libllb_metal" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_Compare Lib "libllb_metal" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
    Public Declare Function Std_Memory_Compare Lib "libllb_metal" (ByVal p1 As Pointer To Byte, ByVal p2 As Pointer To Byte, ByVal count As UInt64) As Int32
    Public Declare Function ParseUInt Lib "libllb_metal" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function ToHex Lib "libllb_metal" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32

    Public Function RunMetalVerification() As Int32
        Dim failCount As Int32 = 0

        ' 1. Math verification
        Dim clamped As Int64 = Clamp(85, 10, 50)
        If clamped <> 50 Then
            failCount = failCount + 1
        End If

        If Min(100, 200) <> 100 Or Max(100, 200) <> 200 Then
            failCount = failCount + 1
        End If

        ' 2. Ascii verification
        If Not IsDigit(55) Or IsDigit(66) Then ' '7'=55, 'B'=66
            failCount = failCount + 1
        End If

        If Not IsHexDigit(65) Or Not IsHexDigit(101) Or IsHexDigit(103) Then ' 'A'=65, 'e'=101, 'g'=103
            failCount = failCount + 1
        End If

        ' 3. Strings verification
        Dim msg As Pointer To Byte = CPtr(Pointer To Byte, "FreestandingMetal")
        Dim lenVal As UInt64 = Std_Strings_Length(msg)
        If lenVal <> 17 Then
            failCount = failCount + 1
        End If

        Dim cmp1 As Int32 = Std_Strings_Compare(CPtr(Pointer To Byte, "PRK"), CPtr(Pointer To Byte, "PRK"))
        Dim cmp2 As Int32 = Std_Strings_Compare(CPtr(Pointer To Byte, "PRK"), CPtr(Pointer To Byte, "QEMU"))
        If cmp1 <> 0 Or cmp2 >= 0 Then
            failCount = failCount + 1
        End If

        ' 4. Memory verification
        Dim memCmp As Int32 = Std_Memory_Compare(CPtr(Pointer To Byte, "PMM"), CPtr(Pointer To Byte, "PMM"), 3)
        If memCmp <> 0 Then
            failCount = failCount + 1
        End If

        ' 5. Conv verification
        Dim parsed As UInt64 = ParseUInt(CPtr(Pointer To Byte, "987654"))
        If parsed <> 987654 Then
            failCount = failCount + 1
        End If

        ' 6. Format verification
        Dim hexBuf(32) As Byte
        Dim hexPtr As Pointer To Byte = CPtr(Pointer To Byte, hexBuf)
        Dim hexLen As UInt32 = ToHex(4096, hexPtr, True)
        If hexLen = 0 Or hexPtr(0) <> 48 Or hexPtr(1) <> 120 Or hexPtr(2) <> 49 Then ' "0x1000"
            failCount = failCount + 1
        End If

        RunMetalVerification = failCount
    End Function

End Module
