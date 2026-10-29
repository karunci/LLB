' Project Name: Low-Level Basic / M3 Adversarial Challenger Test Suite
' Filename: tests/m3_challenger_test/src/M3ChallengerMain.bas
' Summary: Empirical stress tests for Milestone 3 Service Cast Cleanups and Implicit Widening.

Module M3ChallengerMain

    Public Declare Function puts Lib "c" (ByVal str As Pointer To Byte) As Int32
    Public Declare Function memset Lib "c" (ByVal dest As Pointer To Byte, ByVal val As Int32, ByVal count As UInt64) As Pointer To Byte

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    Private Sub AssertTrue(ByVal cond As Boolean, ByVal name As Pointer To Byte)
        testsRun = testsRun + 1
        If cond Then
            testsPassed = testsPassed + 1
            Print "  [PASS] #", testsRun, " - ", name
        Else
            testsFailed = testsFailed + 1
            Print "  [FAIL] #", testsRun, " - ", name
        End If
    End Sub

    ' Mock helper functions mirroring service signatures
    Private Function MockReceiveUInt64(ByVal val As UInt64) As UInt64
        MockReceiveUInt64 = val
    End Function

    Private Structure MockSyscallPkt
        Public PacketType As UInt32
        Public Sequence   As UInt32
    End Structure

    ' =========================================================================
    ' SUITE 1: Implicit Widening Without Sign Extension (Byte -> UInt32, Byte -> UInt64)
    ' =========================================================================
    Private Unsafe Sub TestByteWideningZeroExtension()
        puts CPtr(Pointer To Byte, "[SUITE 1] Byte Widening & Zero-Extension Stress...")

        ' 1. Byte values with high-bit set assigned to UInt32 (mirrors rawRow(bOff) in CompositorMain)
        Dim bLow As Byte = 42
        Dim u32Low As UInt32 = bLow
        AssertTrue(u32Low = 42, CPtr(Pointer To Byte, "Byte(42) widens to UInt32(42)"))

        Dim bMid As Byte = 127
        Dim u32Mid As UInt32 = bMid
        AssertTrue(u32Mid = 127, CPtr(Pointer To Byte, "Byte(127) widens to UInt32(127)"))

        Dim bHigh As Byte = 128
        Dim u32High As UInt32 = bHigh
        AssertTrue(u32High = 128, CPtr(Pointer To Byte, "Byte(128) widens to UInt32(128) without negative sign-extension"))
        AssertTrue((u32High And &HFFFFFF00) = 0, CPtr(Pointer To Byte, "Byte(128) upper 24 bits are strictly zero"))

        Dim bMax As Byte = 255
        Dim u32Max As UInt32 = bMax
        AssertTrue(u32Max = 255, CPtr(Pointer To Byte, "Byte(255) widens to UInt32(255) without negative sign-extension"))
        AssertTrue((u32Max And &HFFFFFF00) = 0, CPtr(Pointer To Byte, "Byte(255) upper 24 bits are strictly zero"))

        ' 2. Compositor color DWORD reconstruction: &HFF000000 Or (r LShift 16) Or (g LShift 8) Or b
        Dim r As UInt32 = Byte(255)
        Dim g As UInt32 = Byte(128)
        Dim b As UInt32 = Byte(64)
        Dim packedColor As UInt32 = &HFF000000 Or (r LShift 16) Or (g LShift 8) Or b
        AssertTrue(packedColor = &HFFFF8040, CPtr(Pointer To Byte, "Compositor color packing with widened bytes produces exact ARGB (&HFFFF8040)"))

        ' 3. Passing Byte directly to function taking UInt64 (mirrors AppendUInt, ConsolePrintWithUInt)
        Dim resU64 As UInt64 = MockReceiveUInt64(bMax)
        AssertTrue(resU64 = 255, CPtr(Pointer To Byte, "Byte(255) argument widens directly to UInt64(255)"))
    End Sub

    ' =========================================================================
    ' SUITE 2: Implicit Widening of UInt32 to UInt64 (vfsCount, reqPkt.PacketType, kind, caps)
    ' =========================================================================
    Private Unsafe Sub TestUInt32ToUInt64Widening()
        puts CPtr(Pointer To Byte, "[SUITE 2] UInt32 to UInt64 Widening Stress...")

        Dim u32Zero As UInt32 = 0
        AssertTrue(MockReceiveUInt64(u32Zero) = 0, CPtr(Pointer To Byte, "UInt32(0) widens to UInt64(0)"))

        Dim u32Count As UInt32 = 31 ' vfsCount
        AssertTrue(MockReceiveUInt64(u32Count) = 31, CPtr(Pointer To Byte, "vfsCount(31) widens to UInt64(31)"))

        Dim pkt As MockSyscallPkt
        pkt.PacketType = 11 ' VFS_CMD_STAT
        AssertTrue(MockReceiveUInt64(pkt.PacketType) = 11, CPtr(Pointer To Byte, "reqPkt.PacketType widens to UInt64(11)"))

        ' Extreme bounds: UInt32 with bit 31 set (&H80000000)
        Dim u32HighBit As UInt32 = &H80000000
        Dim u64FromHighBit As UInt64 = MockReceiveUInt64(u32HighBit)
        AssertTrue(u64FromHighBit = 2147483648, CPtr(Pointer To Byte, "UInt32(&H80000000) zero-extends to UInt64(2147483648)"))
        AssertTrue((u64FromHighBit And &HFFFFFFFF00000000) = 0, CPtr(Pointer To Byte, "UInt32(&H80000000) upper 32 bits remain zero"))

        Dim u32Max As UInt32 = &HFFFFFFFF
        Dim u64FromMax As UInt64 = MockReceiveUInt64(u32Max)
        AssertTrue(u64FromMax = 4294967295, CPtr(Pointer To Byte, "UInt32(&HFFFFFFFF) zero-extends to UInt64(4294967295)"))
        AssertTrue((u64FromMax And &HFFFFFFFF00000000) = 0, CPtr(Pointer To Byte, "UInt32(&HFFFFFFFF) upper 32 bits remain zero"))
    End Sub

    ' =========================================================================
    ' SUITE 3: Signed Int32 Conversion and Negative Sign Preservation (ResolvePath, ResolveDev)
    ' =========================================================================
    Private Unsafe Sub TestSignedInt32Conversions()
        puts CPtr(Pointer To Byte, "[SUITE 3] Signed Int32 Concise Cast Stress...")

        ' Table index conversion: ResolvePath = Int32(i)
        Dim i As UInt32 = 0
        Dim sIdx0 As Int32 = Int32(i)
        AssertTrue(sIdx0 = 0, CPtr(Pointer To Byte, "Int32(0) == 0"))

        i = 15
        Dim sIdx15 As Int32 = Int32(i)
        AssertTrue(sIdx15 = 15, CPtr(Pointer To Byte, "Int32(15) == 15"))

        ' Error code preservation (-1)
        Dim negOne As Int32 = -1
        AssertTrue(negOne = -1, CPtr(Pointer To Byte, "Int32(-1) == -1"))
        AssertTrue(negOne < 0, CPtr(Pointer To Byte, "Int32(-1) is strictly less than 0"))

        ' Sign extension when Int32 is passed to Int64 or compared
        Dim s64FromNeg As Int64 = negOne
        AssertTrue(s64FromNeg = -1, CPtr(Pointer To Byte, "Int32(-1) sign-extends to Int64(-1)"))
    End Sub

    ' =========================================================================
    ' SUITE 4: Color Unpacking Concise Casts (Byte(col And &HFF), Byte(col RShift N))
    ' =========================================================================
    Private Unsafe Sub TestColorUnpackingConciseCasts()
        puts CPtr(Pointer To Byte, "[SUITE 4] Color Unpacking Concise Cast Stress...")

        Dim col1 As UInt32 = &HFF123456
        Dim b0 As Byte = Byte(col1 And &HFF)
        Dim b1 As Byte = Byte((col1 RShift 8) And &HFF)
        Dim b2 As Byte = Byte((col1 RShift 16) And &HFF)
        AssertTrue(b0 = &H56, CPtr(Pointer To Byte, "Byte(col And &HFF) extracts blue 0x56"))
        AssertTrue(b1 = &H34, CPtr(Pointer To Byte, "Byte((col RShift 8) And &HFF) extracts green 0x34"))
        AssertTrue(b2 = &H12, CPtr(Pointer To Byte, "Byte((col RShift 16) And &HFF) extracts red 0x12"))

        ' High-bit colors (&HFF808080)
        Dim col2 As UInt32 = &HFF808080
        Dim b0h As Byte = Byte(col2 And &HFF)
        Dim b1h As Byte = Byte((col2 RShift 8) And &HFF)
        Dim b2h As Byte = Byte((col2 RShift 16) And &HFF)
        AssertTrue(b0h = 128, CPtr(Pointer To Byte, "Byte(col2 And &HFF) extracts 128 (0x80)"))
        AssertTrue(b1h = 128, CPtr(Pointer To Byte, "Byte((col2 RShift 8) And &HFF) extracts 128 (0x80)"))
        AssertTrue(b2h = 128, CPtr(Pointer To Byte, "Byte((col2 RShift 16) And &HFF) extracts 128 (0x80)"))
    End Sub

    ' =========================================================================
    ' SUITE 5: Bitmask Generation and Shifts (UInt16(1) LShift col, Byte(16 RShift c))
    ' =========================================================================
    Private Unsafe Sub TestBitmaskConciseCasts()
        puts CPtr(Pointer To Byte, "[SUITE 5] Bitmask & Shift Concise Cast Stress...")

        ' WindowTheme: (mask And (UInt16(1) LShift col)) <> 0
        Dim mask As UInt16 = &H0005 ' bits 0 and 2 set
        Dim bit0 As UInt16 = UInt16(1) LShift 0
        Dim bit1 As UInt16 = UInt16(1) LShift 1
        Dim bit2 As UInt16 = UInt16(1) LShift 2
        AssertTrue((mask And bit0) <> 0, CPtr(Pointer To Byte, "UInt16(1) LShift 0 matches bit 0"))
        AssertTrue((mask And bit1) = 0,  CPtr(Pointer To Byte, "UInt16(1) LShift 1 does not match bit 1"))
        AssertTrue((mask And bit2) <> 0, CPtr(Pointer To Byte, "UInt16(1) LShift 2 matches bit 2"))

        Dim bit15 As UInt16 = UInt16(1) LShift 15
        AssertTrue(bit15 = &H8000, CPtr(Pointer To Byte, "UInt16(1) LShift 15 == &H8000"))

        ' Font: bitMask As Byte = Byte(16 RShift c)
        Dim c0 As Byte = Byte(16 RShift 0)
        Dim c1 As Byte = Byte(16 RShift 1)
        Dim c2 As Byte = Byte(16 RShift 2)
        Dim c3 As Byte = Byte(16 RShift 3)
        Dim c4 As Byte = Byte(16 RShift 4)
        AssertTrue(c0 = 16, CPtr(Pointer To Byte, "Byte(16 RShift 0) == 16"))
        AssertTrue(c1 = 8,  CPtr(Pointer To Byte, "Byte(16 RShift 1) == 8"))
        AssertTrue(c2 = 4,  CPtr(Pointer To Byte, "Byte(16 RShift 2) == 4"))
        AssertTrue(c3 = 2,  CPtr(Pointer To Byte, "Byte(16 RShift 3) == 2"))
        AssertTrue(c4 = 1,  CPtr(Pointer To Byte, "Byte(16 RShift 4) == 1"))
    End Sub

    ' =========================================================================
    ' SUITE 6: Large Multiplication Preservation (UInt64(W) * UInt64(H) * 4)
    ' =========================================================================
    Private Unsafe Sub TestCanvasDimensionMultiplication()
        puts CPtr(Pointer To Byte, "[SUITE 6] Canvas Dimension Multiplication Stress...")

        Dim canvasW As Int32 = 640
        Dim canvasH As Int32 = 480
        Dim surfBytes As UInt64 = UInt64(canvasW) * UInt64(canvasH) * 4
        AssertTrue(surfBytes = 1228800, CPtr(Pointer To Byte, "640x480x4 == 1228800 bytes"))

        ' 4K Canvas
        Dim canvas4KW As Int32 = 3840
        Dim canvas4KH As Int32 = 2160
        Dim surfBytes4K As UInt64 = UInt64(canvas4KW) * UInt64(canvas4KH) * 4
        AssertTrue(surfBytes4K = 33177600, CPtr(Pointer To Byte, "3840x2160x4 == 33177600 bytes"))

        ' Huge canvas that overflows 32-bit integer (65536 * 65536 * 4 = 17179869184)
        Dim giantW As Int32 = 65536
        Dim giantH As Int32 = 65536
        Dim giantBytes As UInt64 = UInt64(giantW) * UInt64(giantH) * 4
        AssertTrue(giantBytes = 17179869184, CPtr(Pointer To Byte, "65536x65536x4 safely computed without 32-bit truncation"))
    End Sub

    ' =========================================================================
    ' SUITE 7: Pointer to UInt64 Conversions & AddressOf
    ' =========================================================================
    Private Unsafe Sub TestPointerToUInt64Conversions()
        puts CPtr(Pointer To Byte, "[SUITE 7] Pointer to UInt64 Concise Cast Stress...")

        Dim localVal As UInt64 = &HCAFEBABE12345678
        Dim pVal As Pointer To UInt64 = AddressOf localVal

        Dim u64Addr As UInt64 = UInt64(pVal)
        AssertTrue(u64Addr <> 0, CPtr(Pointer To Byte, "UInt64(pVal) produces non-zero 64-bit integer address"))

        Dim pRestored As Pointer To UInt64 = CPtr(Pointer To UInt64, u64Addr)
        AssertTrue(pRestored(0) = &HCAFEBABE12345678, CPtr(Pointer To Byte, "Dereferencing restored pointer reads correct value"))

        Dim addrOfDirect As UInt64 = UInt64(AddressOf localVal)
        AssertTrue(addrOfDirect = u64Addr, CPtr(Pointer To Byte, "UInt64(AddressOf localVal) matches UInt64(pVal)"))
    End Sub

    ' =========================================================================
    ' SUITE 8: Memory Set with Byte Value Widening
    ' =========================================================================
    Private Unsafe Sub TestMemsetByteWidening()
        puts CPtr(Pointer To Byte, "[SUITE 8] Memset with Byte Value Widening Stress...")

        Dim buf(32) As Byte
        buf(16) = 0
        Dim fillVal As Byte = &HA5 ' 165
        memset @buf(0), fillVal, 16

        Dim allMatch As Boolean = True
        Dim i As UInt32 = 0
        While i < 16
            If buf(i) <> &HA5 Then allMatch = False
            i = i + 1
        Wend
        AssertTrue(allMatch, CPtr(Pointer To Byte, "memset populated 16 bytes with 0xA5 through widened Byte argument"))
        AssertTrue(buf(16) = 0, CPtr(Pointer To Byte, "Buffer byte 16 beyond count remains 0"))
    End Sub

    ' =========================================================================
    ' Main Runner
    ' =========================================================================
    Public Unsafe Function Main(ByVal argc As Int32, ByVal argv As Pointer To Pointer To Byte) As Int32
        puts CPtr(Pointer To Byte, "========================================================")
        puts CPtr(Pointer To Byte, "[CHALLENGER-M3] Empirical Adversarial Verification Suite")
        puts CPtr(Pointer To Byte, "========================================================")

        TestByteWideningZeroExtension
        TestUInt32ToUInt64Widening
        TestSignedInt32Conversions
        TestColorUnpackingConciseCasts
        TestBitmaskConciseCasts
        TestCanvasDimensionMultiplication
        TestPointerToUInt64Conversions
        TestMemsetByteWidening

        puts CPtr(Pointer To Byte, "--------------------------------------------------------")
        Print "[CHALLENGER-M3] Total Tests Run   : ", testsRun
        Print "[CHALLENGER-M3] Total Tests Passed: ", testsPassed
        Print "[CHALLENGER-M3] Total Tests Failed: ", testsFailed
        puts CPtr(Pointer To Byte, "--------------------------------------------------------")

        If testsFailed = 0 Then
            puts CPtr(Pointer To Byte, "[CHALLENGER-M3] ALL ADVERSARIAL STRESS TESTS PASSED (100%)!")
            puts CPtr(Pointer To Byte, "========================================================")
            Main = 0
        Else
            puts CPtr(Pointer To Byte, "[CHALLENGER-M3] ADVERSARIAL VERIFICATION FAILED!")
            puts CPtr(Pointer To Byte, "========================================================")
            Main = 1
        End If
    End Function

End Module
