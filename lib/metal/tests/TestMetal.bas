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
    Public Declare Function Std_Strings_CompareN Lib "libllb_metal" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal n As UInt64) As Int32
    Public Declare Function Std_Strings_Find Lib "libllb_metal" (ByVal str As Pointer To Byte, ByVal c As Byte) As Pointer To Byte
    Public Declare Function Std_Strings_Concat Lib "libllb_metal" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_SubString Lib "libllb_metal" (ByVal src As Pointer To Byte, ByVal start As UInt64, ByVal count As UInt64, ByVal outBuf As Pointer To Byte) As UInt64
    Public Declare Function Std_Strings_CompareI Lib "libllb_metal" (ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32
    Public Declare Function Std_Memory_Compare Lib "libllb_metal" (ByVal p1 As Pointer To Byte, ByVal p2 As Pointer To Byte, ByVal count As UInt64) As Int32
    Public Declare Function Std_Memory_Search Lib "libllb_metal" (ByVal ptr As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64) As Pointer To Byte
    Public Declare Sub Std_Memory_SetBytes Lib "libllb_metal" (ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)
    Public Declare Function PopCount Lib "libllb_metal" (ByVal value As UInt64) As UInt32
    Public Declare Function CountLeadingZeros Lib "libllb_metal" (ByVal value As UInt64) As UInt32
    Public Declare Function CountTrailingZeros Lib "libllb_metal" (ByVal value As UInt64) As UInt32
    Public Declare Function ParseUInt Lib "libllb_metal" (ByVal str As Pointer To Byte) As UInt64
    Public Declare Function ToHex Lib "libllb_metal" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
    Public Declare Function SprintF Lib "libllb_metal" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt64, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32

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

        Dim cmpN As Int32 = Std_Strings_CompareN(CPtr(Pointer To Byte, "GDT_ENTRY"), CPtr(Pointer To Byte, "GDT_TABLE"), 4)
        If cmpN <> 0 Then
            failCount = failCount + 1
        End If

        Dim found As Pointer To Byte = Std_Strings_Find(CPtr(Pointer To Byte, "IDT#Vector"), 35) ' 35 is '#'
        If found = 0 Or found(0) <> 35 Then
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

        ' 7. SprintF verification
        Dim sBuf(64) As Byte
        Dim sPtr As Pointer To Byte = CPtr(Pointer To Byte, sBuf)
        SprintF sPtr, 64, CPtr(Pointer To Byte, "CPU=%d, Base=0x%x"), 1, 4096
        If Std_Strings_Compare(sPtr, CPtr(Pointer To Byte, "CPU=1, Base=0x1000")) <> 0 Then
            failCount = failCount + 1
        End If

        ' 8. Concat, SubString, CompareI verification
        Dim catBuf(32) As Byte
        Dim catPtr As Pointer To Byte = CPtr(Pointer To Byte, catBuf)
        catBuf(0) = 0
        Std_Strings_Concat catPtr, CPtr(Pointer To Byte, "IDT")
        Std_Strings_Concat catPtr, CPtr(Pointer To Byte, "_VEC")
        If Std_Strings_Compare(catPtr, CPtr(Pointer To Byte, "IDT_VEC")) <> 0 Then
            failCount = failCount + 1
        End If

        Dim subBuf(16) As Byte
        Dim subPtr As Pointer To Byte = CPtr(Pointer To Byte, subBuf)
        Std_Strings_SubString CPtr(Pointer To Byte, "APIC_TIMER"), 5, 5, subPtr
        If Std_Strings_Compare(subPtr, CPtr(Pointer To Byte, "TIMER")) <> 0 Then
            failCount = failCount + 1
        End If

        If Std_Strings_CompareI(CPtr(Pointer To Byte, "x86_64"), CPtr(Pointer To Byte, "X86_64")) <> 0 Then
            failCount = failCount + 1
        End If

        ' 9. Memory Search & SetBytes verification
        Dim mBuf(16) As Byte
        Dim mPtr As Pointer To Byte = CPtr(Pointer To Byte, mBuf)
        Std_Memory_SetBytes mPtr, 90, 4 ' 'Z'=90
        mBuf(4) = 0
        If Std_Strings_Compare(mPtr, CPtr(Pointer To Byte, "ZZZZ")) <> 0 Then
            failCount = failCount + 1
        End If

        Dim searched As Pointer To Byte = Std_Memory_Search(CPtr(Pointer To Byte, "GDT*TSS"), 42, 7) ' 42 is '*'
        If searched = 0 Or searched(0) <> 42 Then
            failCount = failCount + 1
        End If

        ' 10. Bitwise helpers verification
        If PopCount(15) <> 4 Or CountLeadingZeros(2) <> 62 Or CountTrailingZeros(16) <> 4 Then
            failCount = failCount + 1
        End If

        RunMetalVerification = failCount
    End Function

End Module
