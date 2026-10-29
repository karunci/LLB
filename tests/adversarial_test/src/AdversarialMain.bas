' Project Name: Low-Level Basic Adversarial Stress Test Suite
' Filename: tests/adversarial_test/src/AdversarialMain.bas
' Summary: Adversarial empirical validation for TypeAlias chaining, pointers, arrays, and string ABI.

Import "../../../include/pros.bas"

Module AdversarialMain

    Public TypeAlias ChainA = UInt64
    Public TypeAlias ChainB = ChainA
    Public TypeAlias ChainC = ChainB
    Public TypeAlias CustomPid = ProcessId

    Public Type AdversarialItem
        Public OwnerPid As ProcessId
        Public HandleVal As Handle
        Public Tag As String
    End Type

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        ' Microkernel syscall 1
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        ' Linux stdout syscall 1
        Asm "movq $1, %%rax; movq $1, %%rdi; movq %0, %%rsi; movq %1, %%rdx; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rdx", "rcx", "r11", "memory"
    End Sub

    Private Unsafe Sub PrintMsg(ByVal s As String)
        DualPrint s
        DualPrint "\r\n"
    End Sub

    Private Unsafe Sub AssertTrue(ByVal cond As Boolean, ByVal testName As String)
        testsRun = testsRun + 1
        Dim nbuf(16) As Byte
        Dim nidx As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @nbuf(0), nidx
        nbuf(nidx) = 0

        If cond Then
            testsPassed = testsPassed + 1
            DualPrint "  [PASS] #"
            DualPrint @nbuf(0)
            DualPrint " - "
            PrintMsg testName
        Else
            testsFailed = testsFailed + 1
            DualPrint "  [FAIL] #"
            DualPrint @nbuf(0)
            DualPrint ": "
            PrintMsg testName
        End If
    End Sub

    Private Unsafe Sub AssertFalse(ByVal cond As Boolean, ByVal testName As String)
        If cond Then
            AssertTrue False, testName
        Else
            AssertTrue True, testName
        End If
    End Sub

    Private Function EchoStr(ByVal inputStr As String) As String
        EchoStr = inputStr
    End Function

    Private Function GetStaticLiteral() As String
        GetStaticLiteral = "StaticLiteralReturn"
    End Function

    Private Function StrCompareHelper(ByVal a As String, ByVal b As String) As Boolean
        If a = b Then
            StrCompareHelper = True
        Else
            StrCompareHelper = False
        End If
    End Function

    Private Function AddChainC(ByVal val As ChainC, ByVal delta As UInt64) As ChainC
        AddChainC = val + delta
    End Function

    Private Function ConvertPidToChain(ByVal pid As CustomPid) As ChainB
        ConvertPidToChain = pid * 2
    End Function

    Private Unsafe Sub MutatePid(ByVal p As Pointer To ProcessId, ByVal newVal As ProcessId)
        p(0) = newVal
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[TEST-ADVERSARIAL] Empirical Adversarial Verification"
        PrintMsg "========================================================"

        ' ========================================================
        ' SECTION 1: Null String & Empty String Comparison Matrix
        ' ========================================================
        PrintMsg "[SUITE 1] Null string & empty string comparison matrix..."
        Dim sNull As String = 0
        Dim sNull2 As String = 0
        Dim sEmpty As String = ""
        Dim sVal As String = "PROS"
        Dim sDef As String

        ' Null checks with literal 0
        AssertTrue sNull = 0, "sNull = 0"
        AssertTrue 0 = sNull, "0 = sNull"
        AssertFalse sNull <> 0, "sNull <> 0 is False"
        AssertFalse 0 <> sNull, "0 <> sNull is False"

        ' Non-null string with literal 0
        AssertFalse sVal = 0, "sVal = 0 is False"
        AssertFalse 0 = sVal, "0 = sVal is False"
        AssertTrue sVal <> 0, "sVal <> 0"
        AssertTrue 0 <> sVal, "0 <> sVal"

        ' Empty string with literal ""
        AssertTrue sEmpty = "", "sEmpty = ''"
        AssertTrue "" = sEmpty, "'' = sEmpty"
        AssertFalse sEmpty <> "", "sEmpty <> '' is False"
        AssertFalse "" <> sEmpty, "'' <> sEmpty is False"

        ' Empty string with literal 0
        AssertFalse sEmpty = 0, "sEmpty = 0 is False"
        AssertFalse 0 = sEmpty, "0 = sEmpty is False"
        AssertTrue sEmpty <> 0, "sEmpty <> 0"
        AssertTrue 0 <> sEmpty, "0 <> sEmpty"

        ' Null string with empty string ""
        AssertFalse sNull = "", "sNull = '' is False"
        AssertFalse "" = sNull, "'' = sNull is False"
        AssertTrue sNull <> "", "sNull <> ''"
        AssertTrue "" <> sNull, "'' <> sNull"

        ' Two null strings compared with = and <>
        AssertTrue sNull = sNull2, "sNull = sNull2"
        AssertFalse sNull <> sNull2, "sNull <> sNull2 is False"

        ' Default uninitialized string
        AssertTrue sDef = 0, "sDef = 0 (uninitialized string is null)"
        AssertFalse sDef = "", "sDef = '' is False"

        ' ========================================================
        ' SECTION 2: String Parameters Passed to Functions & Returned
        ' ========================================================
        PrintMsg "[SUITE 2] String parameters passed and returned..."
        Dim retVal As String = EchoStr("Roundtrip")
        AssertTrue retVal = "Roundtrip", "EchoStr('Roundtrip') == 'Roundtrip'"
        AssertTrue StrLen(retVal) = 9, "StrLen(EchoStr('Roundtrip')) == 9"

        Dim retEmpty As String = EchoStr("")
        AssertTrue retEmpty = "", "EchoStr('') == ''"
        AssertTrue StrLen(retEmpty) = 0, "StrLen(EchoStr('')) == 0"

        Dim retNull As String = EchoStr(0)
        AssertTrue retNull = 0, "EchoStr(0) == 0"

        Dim retStatic As String = GetStaticLiteral()
        AssertTrue retStatic = "StaticLiteralReturn", "GetStaticLiteral() == 'StaticLiteralReturn'"

        AssertTrue StrCompareHelper("Match", "Match"), "StrCompareHelper('Match', 'Match') == True"
        AssertFalse StrCompareHelper("Match", "Mismatch"), "StrCompareHelper('Match', 'Mismatch') == False"
        AssertTrue StrCompareHelper(0, 0), "StrCompareHelper(0, 0) == True"
        AssertFalse StrCompareHelper(0, "Something"), "StrCompareHelper(0, 'Something') == False"
        AssertFalse StrCompareHelper("Something", 0), "StrCompareHelper('Something', 0) == False"
        AssertTrue StrCompareHelper("", ""), "StrCompareHelper('', '') == True"
        AssertFalse StrCompareHelper("", 0), "StrCompareHelper('', 0) == False"
        AssertFalse StrCompareHelper(0, ""), "StrCompareHelper(0, '') == False"

        ' ========================================================
        ' SECTION 3: Chained Type Aliases
        ' ========================================================
        PrintMsg "[SUITE 3] Chained Type Aliases..."
        Dim cVal As ChainC = &H1122334455667788
        AssertTrue cVal = &H1122334455667788, "ChainC value stored correctly"

        Dim cNext As ChainC = AddChainC(cVal, 1)
        AssertTrue cNext = &H1122334455667789, "AddChainC arithmetic correct"

        Dim cPid As CustomPid = 4096
        Dim converted As ChainB = ConvertPidToChain(cPid)
        AssertTrue converted = 8192, "CustomPid -> ChainB conversion and passing"

        ' ========================================================
        ' SECTION 4: Pointer to Type Alias
        ' ========================================================
        PrintMsg "[SUITE 4] Pointer to Type Alias..."
        Dim myPid As ProcessId = &HCAFEBABE
        Dim pPid As Pointer To ProcessId = AddressOf myPid

        AssertTrue pPid(0) = &HCAFEBABE, "pPid(0) dereference read matches original value"
        pPid(0) = &HDEADBEEF
        AssertTrue myPid = &HDEADBEEF, "pPid(0) store successfully mutated myPid"

        Dim pChain As Pointer To ChainC = AddressOf cVal
        AssertTrue pChain(0) = &H1122334455667788, "pChain(0) read matches cVal"
        pChain(0) = &H99887766
        AssertTrue cVal = &H99887766, "pChain(0) store successfully mutated cVal"

        MutatePid pPid, 12345
        AssertTrue myPid = 12345, "MutatePid procedure call through Pointer To ProcessId"

        ' ========================================================
        ' SECTION 5: Array of Type Alias
        ' ========================================================
        PrintMsg "[SUITE 5] Array of Type Alias..."
        Dim pidList(5) As ProcessId
        pidList(0) = 1001
        pidList(1) = 1002
        pidList(2) = 1003
        pidList(3) = 1004
        pidList(4) = 1005

        AssertTrue pidList(0) = 1001, "pidList(0) == 1001"
        AssertTrue pidList(1) = 1002, "pidList(1) == 1002"
        AssertTrue pidList(2) = 1003, "pidList(2) == 1003"
        AssertTrue pidList(3) = 1004, "pidList(3) == 1004"
        AssertTrue pidList(4) = 1005, "pidList(4) == 1005"

        Dim sumPids As ProcessId = 0
        sumPids = pidList(0) + pidList(1) + pidList(2) + pidList(3) + pidList(4)
        AssertTrue sumPids = 5015, "Array of ProcessId sum elements == 5015"

        Dim chainList(3) As ChainC
        chainList(0) = 10
        chainList(1) = 20
        chainList(2) = 30
        AssertTrue chainList(0) + chainList(1) + chainList(2) = 60, "Array of chained ChainC elements"

        Dim ptrList(2) As Pointer To ProcessId
        ptrList(0) = AddressOf myPid
        Dim readPtr As Pointer To ProcessId = ptrList(0)
        AssertTrue readPtr(0) = 12345, "Array of Pointer To ProcessId element dereference"

        ' ========================================================
        ' SECTION 6: Struct containing TypeAlias & String
        ' ========================================================
        PrintMsg "[SUITE 6] Struct containing TypeAlias and String..."
        Dim item As AdversarialItem
        item.OwnerPid = 999
        item.HandleVal = 888
        item.Tag = "TestTag"

        AssertTrue item.OwnerPid = 999, "item.OwnerPid == 999"
        AssertTrue item.HandleVal = 888, "item.HandleVal == 888"
        AssertTrue item.Tag = "TestTag", "item.Tag == 'TestTag'"

        item.Tag = 0
        AssertTrue item.Tag = 0, "item.Tag = 0 (null string field)"
        AssertFalse item.Tag = "TestTag", "item.Tag = 'TestTag' when null is False"

        ' ========================================================
        ' SUMMARY
        ' ========================================================
        PrintMsg "--------------------------------------------------------"
        Dim rBuf(16) As Byte
        Dim pBuf(16) As Byte
        Dim fBuf(16) As Byte
        Dim idxR As UInt32 = 0
        Dim idxP As UInt32 = 0
        Dim idxF As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @rBuf(0), idxR
        rBuf(idxR) = 0
        AppendUInt CType(UInt64, testsPassed), @pBuf(0), idxP
        pBuf(idxP) = 0
        AppendUInt CType(UInt64, testsFailed), @fBuf(0), idxF
        fBuf(idxF) = 0

        DualPrint "[TEST-ADVERSARIAL] Total Tests Run   : "
        PrintMsg @rBuf(0)
        DualPrint "[TEST-ADVERSARIAL] Total Tests Passed: "
        PrintMsg @pBuf(0)
        DualPrint "[TEST-ADVERSARIAL] Total Tests Failed: "
        PrintMsg @fBuf(0)
        PrintMsg "--------------------------------------------------------"

        If testsFailed = 0 Then
            PrintMsg "[TEST-ADVERSARIAL] ALL ADVERSARIAL STRESS TESTS PASSED!"
            PrintMsg "========================================================"
            user_main = 0
        Else
            PrintMsg "[TEST-ADVERSARIAL] ADVERSARIAL TESTS FAILED!"
            PrintMsg "========================================================"
            user_main = 1
        End If
    End Function

End Module

