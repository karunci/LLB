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
    Public Declare Function Std_Strings_CompareN Lib "libllb" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal n As UInt64) As Int32
    Public Declare Function Std_Strings_Find Lib "libllb" (ByVal str As Pointer To Byte, ByVal c As Byte) As Pointer To Byte
    Public Declare Function Std_Strings_Concat Lib "libllb" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_SubString Lib "libllb" (ByVal src As Pointer To Byte, ByVal start As UInt64, ByVal count As UInt64, ByVal outBuf As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_CompareI Lib "libllb" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
    Public Declare Function Std_Memory_Compare Lib "libllb" (ByVal p1 As Pointer To Byte, ByVal p2 As Pointer To Byte, ByVal count As UInt64) As Int32
    Public Declare Function Std_Memory_Search Lib "libllb" (ByVal ptr As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64) As Pointer To Byte
    Public Declare Sub Std_Memory_SetBytes Lib "libllb" (ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
    Public Declare Function PopCount Lib "libllb" (ByVal value As UInt64) As UInt32
    Public Declare Function CountLeadingZeros Lib "libllb" (ByVal value As UInt64) As UInt32
    Public Declare Function CountTrailingZeros Lib "libllb" (ByVal value As UInt64) As UInt32
    Public Declare Function ParseUInt Lib "libllb" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function ToHex Lib "libllb" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
    Public Declare Function SprintF Lib "libllb" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt64, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32

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

        ' 7. CompareN & Find verification
        Dim cmpN As Int32 = Std_Strings_CompareN(CPtr(Pointer To Byte, "foobar"), CPtr(Pointer To Byte, "foobaz"), 4)
        If cmpN <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_CompareN failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.CompareN via libllb.so")
        End If

        Dim found As Pointer To Byte = Std_Strings_Find(CPtr(Pointer To Byte, "kernel:ok"), 58) ' 58 is ':'
        If found = 0 Or found(0) <> 58 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_Find failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.Find via libllb.so")
        End If

        ' 8. SprintF verification
        Dim sBuf(128) As Byte
        Dim sPtr As Pointer To Byte = CPtr(Pointer To Byte, sBuf)
        SprintF sPtr, 128, CPtr(Pointer To Byte, "Val=%d, Hex=0x%x, Str=%s"), 42, 255, CPtr(Pointer To Byte, "PASS")
        puts sPtr
        If Std_Strings_Compare(sPtr, CPtr(Pointer To Byte, "Val=42, Hex=0xFF, Str=PASS")) <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] SprintF output mismatch")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Format.SprintF via libllb.so")
        End If

        ' 9. Concat, SubString, CompareI verification
        Dim catBuf(64) As Byte
        Dim catPtr As Pointer To Byte = CPtr(Pointer To Byte, catBuf)
        catBuf(0) = 0
        Std_Strings_Concat catPtr, CPtr(Pointer To Byte, "Hello ")
        Std_Strings_Concat catPtr, CPtr(Pointer To Byte, "World")
        If Std_Strings_Compare(catPtr, CPtr(Pointer To Byte, "Hello World")) <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_Concat failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.Concat via libllb.so")
        End If

        Dim subBuf(32) As Byte
        Dim subPtr As Pointer To Byte = CPtr(Pointer To Byte, subBuf)
        Std_Strings_SubString CPtr(Pointer To Byte, "Supercalifragilistic"), 5, 4, subPtr
        If Std_Strings_Compare(subPtr, CPtr(Pointer To Byte, "cali")) <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_SubString failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.SubString via libllb.so")
        End If

        If Std_Strings_CompareI(CPtr(Pointer To Byte, "low-level"), CPtr(Pointer To Byte, "LOW-LEVEL")) <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Strings_CompareI failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Strings.CompareI via libllb.so")
        End If

        ' 10. Memory Search & SetBytes verification
        Dim mBuf(16) As Byte
        Dim mPtr As Pointer To Byte = CPtr(Pointer To Byte, mBuf)
        Std_Memory_SetBytes mPtr, 65, 8
        mBuf(8) = 0
        If Std_Strings_Compare(mPtr, CPtr(Pointer To Byte, "AAAAAAAA")) <> 0 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Memory_SetBytes failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Memory.SetBytes via libllb.so")
        End If

        Dim searched As Pointer To Byte = Std_Memory_Search(CPtr(Pointer To Byte, "data:1234"), 58, 9)
        If searched = 0 Or searched(0) <> 58 Then
            puts CPtr(Pointer To Byte, "[FAIL] Std_Memory_Search failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Std.Memory.Search via libllb.so")
        End If

        ' 11. Bitwise helpers verification
        If PopCount(255) <> 8 Or CountLeadingZeros(1) <> 63 Or CountTrailingZeros(8) <> 3 Then
            puts CPtr(Pointer To Byte, "[FAIL] Bitwise helpers (PopCount/CLZ/CTZ) failed")
            failCount = failCount + 1
        Else
            puts CPtr(Pointer To Byte, "[PASS] Math PopCount/CLZ/CTZ via libllb.so")
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
