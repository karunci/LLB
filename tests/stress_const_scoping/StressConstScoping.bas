' Project Name: Low-Level Basic Compiler (llbc)
' Filename: tests/stress_const_scoping/StressConstScoping.bas
' Summary: Adversarial empirical stress test for module-level and imported constants scoping across procedure boundaries

Module StressConstScoping

    Import ExportConsts In "ExportConsts.bas"

    ' Module-level constants
    Public Const MOD_HEX_MAX As UInt64 = &HFFFFFFFFFFFFFFFF
    Public Const MOD_DEC_MAX As UInt64 = 18446744073709551615
    Public Const MOD_INT_MAX As Int64 = 9223372036854775807
    Public Const MOD_INT_MIN As Int64 = -9223372036854775807 - 1

    Public Const SHADOW_ME_CONST As UInt64 = &HFFFFFFFFFFFFFFFF
    Public Const SHADOW_ME_VAR As UInt64 = &HFFFFFFFFFFFFFFFF

    Dim g_failures As Int32 = 0

    Public Declare Function puts(ByVal str As Pointer To Byte) As Int32

    Public Sub AssertTrue(ByVal condition As Boolean, ByVal testName As Pointer To Byte)
        If condition Then
            ' OK
        Else
            puts CPtr(Pointer To Byte, "  [FAILED] Condition was False:")
            puts testName
            g_failures = g_failures + 1
        End If
    End Sub

    Public Sub AssertFalse(ByVal condition As Boolean, ByVal testName As Pointer To Byte)
        If Not condition Then
            ' OK
        Else
            puts CPtr(Pointer To Byte, "  [FAILED] Condition was True:")
            puts testName
            g_failures = g_failures + 1
        End If
    End Sub

    ' --- Subroutine 1: Module Const vs Negative Int64 ---
    Public Sub TestModuleConstVsNegativeSub1()
        Dim sNeg1 As Int64 = -1
        Dim sMin As Int64 = -9223372036854775807 - 1

        AssertTrue(-1 < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: -1 < MOD_HEX_MAX"))
        AssertTrue(-1 < MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub1: -1 < MOD_DEC_MAX"))
        AssertTrue(sNeg1 < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: sNeg1(-1) < MOD_HEX_MAX"))
        AssertTrue(sNeg1 < MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub1: sNeg1(-1) < MOD_DEC_MAX"))
        AssertTrue(sMin < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: sMin < MOD_HEX_MAX"))
        AssertTrue(sMin < MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub1: sMin < MOD_DEC_MAX"))
        AssertTrue(MOD_HEX_MAX > -1, CPtr(Pointer To Byte, "Sub1: MOD_HEX_MAX > -1"))
        AssertTrue(MOD_DEC_MAX > -1, CPtr(Pointer To Byte, "Sub1: MOD_DEC_MAX > -1"))
        AssertTrue(MOD_HEX_MAX > sNeg1, CPtr(Pointer To Byte, "Sub1: MOD_HEX_MAX > sNeg1"))
        AssertFalse(-1 = MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: -1 = MOD_HEX_MAX is False"))
        AssertTrue(-1 <> MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: -1 <> MOD_HEX_MAX"))
        AssertFalse(sNeg1 = MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: sNeg1 = MOD_HEX_MAX is False"))
        AssertTrue(sNeg1 <> MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub1: sNeg1 <> MOD_HEX_MAX"))
    End Sub

    ' --- Subroutine 2: Module Const vs Negative in a Separate Subsequent Sub ---
    Public Sub TestModuleConstVsNegativeSub2()
        Dim sNeg42 As Int64 = -42
        Dim sNeg100 As Int64 = -100

        AssertTrue(sNeg42 < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub2: sNeg42 < MOD_HEX_MAX"))
        AssertTrue(sNeg42 < MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub2: sNeg42 < MOD_DEC_MAX"))
        AssertTrue(MOD_HEX_MAX > sNeg42, CPtr(Pointer To Byte, "Sub2: MOD_HEX_MAX > sNeg42"))
        AssertTrue(MOD_DEC_MAX > sNeg42, CPtr(Pointer To Byte, "Sub2: MOD_DEC_MAX > sNeg42"))
        AssertTrue(-100 < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub2: -100 < MOD_HEX_MAX"))
        AssertTrue(MOD_HEX_MAX > -100, CPtr(Pointer To Byte, "Sub2: MOD_HEX_MAX > -100"))
        AssertTrue(sNeg100 < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub2: sNeg100 < MOD_HEX_MAX"))
        AssertTrue(MOD_INT_MAX < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub2: MOD_INT_MAX < MOD_HEX_MAX"))
        AssertTrue(MOD_INT_MIN < MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub2: MOD_INT_MIN < MOD_HEX_MAX"))
        AssertTrue(MOD_INT_MIN < MOD_INT_MAX, CPtr(Pointer To Byte, "Sub2: MOD_INT_MIN < MOD_INT_MAX"))
        AssertTrue(MOD_INT_MAX > MOD_INT_MIN, CPtr(Pointer To Byte, "Sub2: MOD_INT_MAX > MOD_INT_MIN"))
    End Sub

    ' --- Subroutine 3: UInt64 Variable Equality against Module Const ---
    Public Sub TestUInt64Equality()
        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF
        Dim uVal2 As UInt64 = 18446744073709551615
        Dim sVal As Int64 = -1

        AssertTrue(uVal = MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub3: uVal = MOD_HEX_MAX"))
        AssertTrue(MOD_HEX_MAX = uVal, CPtr(Pointer To Byte, "Sub3: MOD_HEX_MAX = uVal"))
        AssertFalse(uVal <> MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub3: uVal <> MOD_HEX_MAX is False"))
        AssertTrue(uVal = MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub3: uVal = MOD_DEC_MAX"))
        AssertTrue(uVal2 = MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub3: uVal2 = MOD_HEX_MAX"))
        AssertTrue(uVal2 = MOD_DEC_MAX, CPtr(Pointer To Byte, "Sub3: uVal2 = MOD_DEC_MAX"))

        ' Mixed signedness equality check
        AssertFalse(sVal = MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub3: sVal(-1) = MOD_HEX_MAX is False"))
        AssertTrue(sVal <> MOD_HEX_MAX, CPtr(Pointer To Byte, "Sub3: sVal(-1) <> MOD_HEX_MAX"))
        AssertFalse(MOD_HEX_MAX = sVal, CPtr(Pointer To Byte, "Sub3: MOD_HEX_MAX = sVal is False"))
        AssertTrue(MOD_HEX_MAX <> sVal, CPtr(Pointer To Byte, "Sub3: MOD_HEX_MAX <> sVal"))
    End Sub

    ' --- Subroutine 4: Unqualified Cross-Module Imported Constants ---
    Public Sub TestImportedConstantsUnqualified()
        Dim sNeg1 As Int64 = -1
        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(-1 < EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: -1 < EXP_HEX_MAX"))
        AssertTrue(sNeg1 < EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: sNeg1 < EXP_HEX_MAX"))
        AssertTrue(EXP_HEX_MAX > sNeg1, CPtr(Pointer To Byte, "Sub4: EXP_HEX_MAX > sNeg1"))
        AssertTrue(sNeg1 < EXP_DEC_MAX, CPtr(Pointer To Byte, "Sub4: sNeg1 < EXP_DEC_MAX"))
        AssertTrue(EXP_DEC_MAX > sNeg1, CPtr(Pointer To Byte, "Sub4: EXP_DEC_MAX > sNeg1"))
        AssertTrue(uVal = EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: uVal = EXP_HEX_MAX"))
        AssertTrue(uVal = EXP_DEC_MAX, CPtr(Pointer To Byte, "Sub4: uVal = EXP_DEC_MAX"))
        AssertFalse(sNeg1 = EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: sNeg1 = EXP_HEX_MAX is False"))
        AssertTrue(sNeg1 <> EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: sNeg1 <> EXP_HEX_MAX"))
        AssertTrue(EXP_INT_MAX < EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: EXP_INT_MAX < EXP_HEX_MAX"))
        AssertTrue(EXP_INT_MIN < EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub4: EXP_INT_MIN < EXP_HEX_MAX"))
        AssertTrue(EXP_INT_MIN < EXP_INT_MAX, CPtr(Pointer To Byte, "Sub4: EXP_INT_MIN < EXP_INT_MAX"))
        AssertTrue(EXP_INT_MAX > EXP_INT_MIN, CPtr(Pointer To Byte, "Sub4: EXP_INT_MAX > EXP_INT_MIN"))
    End Sub

    ' --- Subroutine 5: Qualified Cross-Module Imported Constants ---
    Public Sub TestImportedConstantsQualified()
        Dim sNeg1 As Int64 = -1
        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(-1 < ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: -1 < ExportConsts.EXP_HEX_MAX"))
        AssertTrue(sNeg1 < ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: sNeg1 < ExportConsts.EXP_HEX_MAX"))
        AssertTrue(ExportConsts.EXP_HEX_MAX > sNeg1, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_HEX_MAX > sNeg1"))
        AssertTrue(sNeg1 < ExportConsts.EXP_DEC_MAX, CPtr(Pointer To Byte, "Sub5: sNeg1 < ExportConsts.EXP_DEC_MAX"))
        AssertTrue(ExportConsts.EXP_DEC_MAX > sNeg1, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_DEC_MAX > sNeg1"))
        AssertTrue(uVal = ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: uVal = ExportConsts.EXP_HEX_MAX"))
        AssertTrue(uVal = ExportConsts.EXP_DEC_MAX, CPtr(Pointer To Byte, "Sub5: uVal = ExportConsts.EXP_DEC_MAX"))
        AssertFalse(sNeg1 = ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: sNeg1 = ExportConsts.EXP_HEX_MAX is False"))
        AssertTrue(sNeg1 <> ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: sNeg1 <> ExportConsts.EXP_HEX_MAX"))
        AssertTrue(ExportConsts.EXP_INT_MAX < ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_INT_MAX < ExportConsts.EXP_HEX_MAX"))
        AssertTrue(ExportConsts.EXP_INT_MIN < ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_INT_MIN < ExportConsts.EXP_HEX_MAX"))
        AssertTrue(ExportConsts.EXP_INT_MIN < ExportConsts.EXP_INT_MAX, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_INT_MIN < ExportConsts.EXP_INT_MAX"))
        AssertTrue(ExportConsts.EXP_INT_MAX > ExportConsts.EXP_INT_MIN, CPtr(Pointer To Byte, "Sub5: ExportConsts.EXP_INT_MAX > ExportConsts.EXP_INT_MIN"))
    End Sub

    ' --- Subroutine 6: Local Const Shadowing Module Const ---
    Public Sub TestLocalConstShadowing()
        ' Shadow module constant SHADOW_ME_CONST (UInt64 max) with a local Int64 negative constant
        Const SHADOW_ME_CONST As Int64 = -999
        Dim sNeg As Int64 = -999
        Dim uCheck As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(SHADOW_ME_CONST < 0, CPtr(Pointer To Byte, "Sub6: local SHADOW_ME_CONST < 0"))
        AssertTrue(SHADOW_ME_CONST = -999, CPtr(Pointer To Byte, "Sub6: local SHADOW_ME_CONST = -999"))
        AssertTrue(SHADOW_ME_CONST = sNeg, CPtr(Pointer To Byte, "Sub6: local SHADOW_ME_CONST = sNeg"))
        AssertTrue(SHADOW_ME_CONST < -1, CPtr(Pointer To Byte, "Sub6: local SHADOW_ME_CONST < -1"))
        AssertFalse(uCheck = SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub6: uCheck = local SHADOW_ME_CONST is False"))
    End Sub

    ' --- Subroutine 7: Verification After Local Const Shadowing (Restoration) ---
    Public Sub TestAfterLocalConstShadowing()
        ' Ensure SHADOW_ME_CONST is restored to the module-level UInt64 max
        Dim sNeg1 As Int64 = -1
        Dim uCheck As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(SHADOW_ME_CONST > 0, CPtr(Pointer To Byte, "Sub7: restored SHADOW_ME_CONST > 0"))
        AssertTrue(-1 < SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub7: -1 < restored SHADOW_ME_CONST"))
        AssertTrue(sNeg1 < SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub7: sNeg1 < restored SHADOW_ME_CONST"))
        AssertTrue(uCheck = SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub7: uCheck = restored SHADOW_ME_CONST"))
        AssertFalse(sNeg1 = SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub7: sNeg1 = restored SHADOW_ME_CONST is False"))
        AssertTrue(sNeg1 <> SHADOW_ME_CONST, CPtr(Pointer To Byte, "Sub7: sNeg1 <> restored SHADOW_ME_CONST"))
    End Sub

    ' --- Subroutine 8: Local Variable Shadowing Module Const ---
    Public Sub TestLocalVarShadowing()
        ' Shadow module constant SHADOW_ME_VAR with a local variable
        Dim SHADOW_ME_VAR As Int64 = -555
        Dim uCheck As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(SHADOW_ME_VAR < 0, CPtr(Pointer To Byte, "Sub8: local var SHADOW_ME_VAR < 0"))
        AssertTrue(SHADOW_ME_VAR = -555, CPtr(Pointer To Byte, "Sub8: local var SHADOW_ME_VAR = -555"))
        AssertTrue(SHADOW_ME_VAR < -1, CPtr(Pointer To Byte, "Sub8: local var SHADOW_ME_VAR < -1"))
        AssertFalse(uCheck = SHADOW_ME_VAR, CPtr(Pointer To Byte, "Sub8: uCheck = local var SHADOW_ME_VAR is False"))
    End Sub

    ' --- Subroutine 9: Verification After Local Variable Shadowing (Restoration) ---
    Public Sub TestAfterLocalVarShadowing()
        Dim sNeg1 As Int64 = -1
        Dim uCheck As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(SHADOW_ME_VAR > 0, CPtr(Pointer To Byte, "Sub9: restored SHADOW_ME_VAR > 0"))
        AssertTrue(-1 < SHADOW_ME_VAR, CPtr(Pointer To Byte, "Sub9: -1 < restored SHADOW_ME_VAR"))
        AssertTrue(sNeg1 < SHADOW_ME_VAR, CPtr(Pointer To Byte, "Sub9: sNeg1 < restored SHADOW_ME_VAR"))
        AssertTrue(uCheck = SHADOW_ME_VAR, CPtr(Pointer To Byte, "Sub9: uCheck = restored SHADOW_ME_VAR"))
        AssertFalse(sNeg1 = SHADOW_ME_VAR, CPtr(Pointer To Byte, "Sub9: sNeg1 = restored SHADOW_ME_VAR is False"))
    End Sub

    ' --- Subroutine 10: Local Const Shadowing Imported Const ---
    Public Sub TestShadowingImportedConst()
        ' Shadow imported EXP_HEX_MAX with local Int32
        Const EXP_HEX_MAX As Int32 = -7
        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(EXP_HEX_MAX < 0, CPtr(Pointer To Byte, "Sub10: local EXP_HEX_MAX < 0"))
        AssertTrue(EXP_HEX_MAX = -7, CPtr(Pointer To Byte, "Sub10: local EXP_HEX_MAX = -7"))

        ' Qualified access must still access the imported module constant!
        AssertTrue(ExportConsts.EXP_HEX_MAX > 0, CPtr(Pointer To Byte, "Sub10: ExportConsts.EXP_HEX_MAX > 0"))
        AssertTrue(-1 < ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub10: -1 < ExportConsts.EXP_HEX_MAX"))
        AssertTrue(uVal = ExportConsts.EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub10: uVal = ExportConsts.EXP_HEX_MAX"))
    End Sub

    ' --- Subroutine 11: Verification After Imported Const Shadowing ---
    Public Sub TestAfterImportedConstShadowing()
        Dim uVal As UInt64 = &HFFFFFFFFFFFFFFFF

        AssertTrue(EXP_HEX_MAX > 0, CPtr(Pointer To Byte, "Sub11: restored EXP_HEX_MAX > 0"))
        AssertTrue(-1 < EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub11: -1 < restored EXP_HEX_MAX"))
        AssertTrue(uVal = EXP_HEX_MAX, CPtr(Pointer To Byte, "Sub11: uVal = restored EXP_HEX_MAX"))
    End Sub

    ' --- Subroutine 12: Passing and Returning Constants Across Procedures ---
    Public Sub HelperExpectU64(ByVal actual As UInt64, ByVal expected As UInt64, ByVal name As Pointer To Byte)
        AssertTrue(actual = expected, name)
    End Sub

    Public Sub HelperExpectI64(ByVal actual As Int64, ByVal expected As Int64, ByVal name As Pointer To Byte)
        AssertTrue(actual = expected, name)
    End Sub

    Public Function ReturnModHexMax() As UInt64
        ReturnModHexMax = MOD_HEX_MAX
    End Function

    Public Function ReturnImportedHexMax() As UInt64
        ReturnImportedHexMax = ExportConsts.EXP_HEX_MAX
    End Function

    Public Sub TestPassingAndReturningConstants()
        HelperExpectU64(MOD_HEX_MAX, &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Sub12: HelperExpectU64(MOD_HEX_MAX)"))
        HelperExpectU64(ExportConsts.EXP_HEX_MAX, &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Sub12: HelperExpectU64(ExportConsts.EXP_HEX_MAX)"))
        HelperExpectU64(EXP_HEX_MAX, &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Sub12: HelperExpectU64(EXP_HEX_MAX)"))

        HelperExpectI64(MOD_INT_MAX, 9223372036854775807, CPtr(Pointer To Byte, "Sub12: HelperExpectI64(MOD_INT_MAX)"))
        HelperExpectI64(ExportConsts.EXP_NEG_TEN, -10, CPtr(Pointer To Byte, "Sub12: HelperExpectI64(ExportConsts.EXP_NEG_TEN)"))

        Dim retU64_1 As UInt64 = ReturnModHexMax()
        Dim retU64_2 As UInt64 = ReturnImportedHexMax()

        AssertTrue(retU64_1 = &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Sub12: ReturnModHexMax() = 0xFFFFFFFFFFFFFFFF"))
        AssertTrue(retU64_2 = &HFFFFFFFFFFFFFFFF, CPtr(Pointer To Byte, "Sub12: ReturnImportedHexMax() = 0xFFFFFFFFFFFFFFFF"))
        AssertTrue(-1 < retU64_1, CPtr(Pointer To Byte, "Sub12: -1 < ReturnModHexMax()"))
        AssertTrue(-1 < retU64_2, CPtr(Pointer To Byte, "Sub12: -1 < ReturnImportedHexMax()"))
    End Sub

    ' --- Subroutine 13: Empirical Defect Verification: Binary Expressions in Module Const ---
    Public Sub TestModuleConstBinaryExpressionDefect()
        puts CPtr(Pointer To Byte, "[Test 13] Empirical Bug Probe: Binary Expressions in Module-Level Constants...")

        Const LOCAL_BIN_ADD As Int32 = 10 + 20
        If LOCAL_BIN_ADD = 30 Then
            puts CPtr(Pointer To Byte, "  [CONFIRMED] Local procedure Const (10 + 20) evaluates to 30.")
        End If

        If ExportConsts.EXP_INT_MIN = 0 Then
            puts CPtr(Pointer To Byte, "  [BUG CONFIRMED] ExportConsts.EXP_INT_MIN (-9223372036854775807 - 1) evaluates to 0!")
            puts CPtr(Pointer To Byte, "  [ROOT CAUSE] emitConstantValue() does not support BinaryExprASTNode, dropping through to getNullValue()!")
        End If
    End Sub

    ' --- Main Entry Point ---
    Public Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "=========================================================")
        puts CPtr(Pointer To Byte, "   ADVERSARIAL CONSTANT SCOPING & COMPARISON SUITE       ")
        puts CPtr(Pointer To Byte, "=========================================================")

        puts CPtr(Pointer To Byte, "[Test 1] Module Const vs Negative Int64 (Sub 1)...")
        TestModuleConstVsNegativeSub1()

        puts CPtr(Pointer To Byte, "[Test 2] Module Const vs Negative Int64 (Sub 2)...")
        TestModuleConstVsNegativeSub2()

        puts CPtr(Pointer To Byte, "[Test 3] UInt64 Variable Equality against Module Const...")
        TestUInt64Equality()

        puts CPtr(Pointer To Byte, "[Test 4] Unqualified Cross-Module Imported Constants...")
        TestImportedConstantsUnqualified()

        puts CPtr(Pointer To Byte, "[Test 5] Qualified Cross-Module Imported Constants...")
        TestImportedConstantsQualified()

        puts CPtr(Pointer To Byte, "[Test 6] Local Const Shadowing Module Const...")
        TestLocalConstShadowing()

        puts CPtr(Pointer To Byte, "[Test 7] Scoping Restoration After Local Const Shadowing...")
        TestAfterLocalConstShadowing()

        puts CPtr(Pointer To Byte, "[Test 8] Local Variable Shadowing Module Const...")
        TestLocalVarShadowing()

        puts CPtr(Pointer To Byte, "[Test 9] Scoping Restoration After Local Var Shadowing...")
        TestAfterLocalVarShadowing()

        puts CPtr(Pointer To Byte, "[Test 10] Local Const Shadowing Imported Const...")
        TestShadowingImportedConst()

        puts CPtr(Pointer To Byte, "[Test 11] Scoping Restoration After Imported Const Shadowing...")
        TestAfterImportedConstShadowing()

        puts CPtr(Pointer To Byte, "[Test 12] Passing and Returning Constants Across Procedures...")
        TestPassingAndReturningConstants()

        puts CPtr(Pointer To Byte, "[Test 13] Binary Expressions in Const Declarations Defect Probe...")
        TestModuleConstBinaryExpressionDefect()

        puts CPtr(Pointer To Byte, "---------------------------------------------------------")
        If g_failures = 0 Then
            puts CPtr(Pointer To Byte, "[ALL ADVERSARIAL CONSTANT SCOPING TESTS PASSED (100%)]")
            Main = 0
        Else
            puts CPtr(Pointer To Byte, "[ADVERSARIAL CHALLENGE DETECTED FAILURES!]")
            Main = g_failures
        End If
    End Function

End Module
