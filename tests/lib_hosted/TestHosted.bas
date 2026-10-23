' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/lib_hosted/TestHosted.bas
' Summary: Standalone test verification program for hosted dynamic shared library (libllb.so).

Module TestHosted

    Public Declare Function puts Lib "c" (ByVal str As Pointer To Byte) As Int32
    Public Declare Function Min Lib "libllb" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Max Lib "libllb" (ByVal a As Int64, ByVal b As Int64) As Int64
    Public Declare Function Clamp Lib "libllb" (ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64
    Public Declare Function IsDigit Lib "libllb" (ByVal c As Byte) As Boolean
    Public Declare Function IsHexDigit Lib "libllb" (ByVal c As Byte) As Boolean
    Public Declare Function Std_Strings_Length Lib "libllb" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_Compare Lib "libllb" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
    Public Declare Function Std_Memory_Compare Lib "libllb" (ByVal p1 As Pointer To Byte, ByVal p2 As Pointer To Byte, ByVal count As UInt64) As Int32
    Public Declare Function ParseUInt Lib "libllb" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function ToHex Lib "libllb" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32

    Public Function Main() As Int32
        puts CPtr(Pointer To Byte, "=== RUNNING LIBLLB HOSTED SHARED LIBRARY TESTS ===")

        Dim failCount As Int32 = 0

        ' 1. Math verification
        Dim clamped As Int64 = Clamp(50, 0, 30)
        If clamped <> 30 Then
            puts CPtr(Pointer To Byte, "[FAIL] Clamp(50, 0, 30) failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Math.Clamp via libllb.so")
        End If

        If Min(10, 20) <> 10 Or Max(10, 20) <> 20 Then
            puts CPtr(Pointer To Byte, "[FAIL] Min/Max failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Math.Min/Max via libllb.so")
        End If

        ' 2. Ascii verification
        If Not IsDigit(53) Or IsDigit(65) Then
            puts CPtr(Pointer To Byte, "[FAIL] IsDigit failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Ascii.IsDigit via libllb.so")
        End If

        If Not IsHexDigit(65) Or Not IsHexDigit(102) Or IsHexDigit(103) Then
            puts CPtr(Pointer To Byte, "[FAIL] IsHexDigit failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Ascii.IsHexDigit via libllb.so")
        End If

        ' 3. Strings verification
        Dim hello As Pointer To Byte = CPtr(Pointer To Byte, "Hello, LibLLB!")
        Dim lenVal As UInt64 = Std_Strings_Length(hello)
        If lenVal <> 14 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_Length failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.Length via libllb.so")
        End If

        Dim cmp1 As Int32 = Std_Strings_Compare(CPtr(Pointer To Byte, "abc"), CPtr(Pointer To Byte, "abc"))
        Dim cmp2 As Int32 = Std_Strings_Compare(CPtr(Pointer To Byte, "abc"), CPtr(Pointer To Byte, "abd"))
        If cmp1 <> 0 Or cmp2 >= 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_Compare failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.Compare via libllb.so")
        End If

        ' 4. Memory verification
        Dim memCmp As Int32 = Std_Memory_Compare(CPtr(Pointer To Byte, "TEST"), CPtr(Pointer To Byte, "TEST"), 4)
        If memCmp <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Memory_Compare failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Memory.Compare via libllb.so")
        End If

        ' 5. Conv verification
        Dim parsed As UInt64 = ParseUInt(CPtr(Pointer To Byte, "123456"))
        If parsed <> 123456 Then
            puts CPtr(Pointer To Byte, "[FAIL] ParseUInt failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Conv.ParseUInt via libllb.so")
        End If

        ' 6. Format verification
        Dim hexBuf(32) As Byte
        Dim hexPtr As Pointer To Byte = CPtr(Pointer To Byte, hexBuf)
        Dim hexLen As UInt32 = ToHex(255, hexPtr, False)
        If hexLen = 0 Or hexPtr(0) <> 70 Or hexPtr(1) <> 70 Then
            puts CPtr(Pointer To Byte, "[FAIL] ToHex failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Format.ToHex via libllb.so")
        End If

        puts CPtr(Pointer To Byte, "===================================================")
        If failCount = 0 Then
            puts CPtr(Pointer To Byte, "   ALL LIBLLB HOSTED SHARED LIBRARY TESTS PASSED!  ")
            puts CPtr(Pointer To Byte, "===================================================")
            Main = 0
        Else
            puts CPtr(Pointer To Byte, "   FAILED LIBLLB HOSTED SHARED LIBRARY TESTS       ")
            puts CPtr(Pointer To Byte, "===================================================")
            Main = 1
        End If
    End Function

End Module
