' Project Name: Low-Level Basic Standard Library Test Suite
' Filename: tests/stdlib/src/TestStdlibMain.bas
' Summary: Standalone Ring 3 verification test suite exercising all 22 pure LLB standard library routines.

Import "../../../include/pros.bas"

Module TestStdlibMain

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    ' 64x64 pixel buffer for Font rendering tests (64 * 64 = 4096 DWORDs = 16384 bytes)
    Private mockPixels(4095) As UInt32
    Private testSurf As Surface

    ''
    ' @brief Dual-mode string printer targeting both PROS Microkernel and Linux userland.
    ' @param strPtr Pointer to null-terminated ASCII string.
    ''
    Private Unsafe Sub DualPrint(ByVal strPtr As Pointer To Byte)
        If strPtr = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(strPtr)
        ' 1. PROS Microkernel console write: %rax=1, %rdi=strPtr, %rsi=length
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(strPtr), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        ' 2. Linux userland stdout write: %rax=1, %rdi=1 (stdout), %rsi=strPtr, %rdx=length
        Asm "movq $1, %%rax; movq $1, %%rdi; movq %0, %%rsi; movq %1, %%rdx; syscall" : : "r"(strPtr), "r"(length) : "rax", "rdi", "rsi", "rdx", "rcx", "r11", "memory"
    End Sub

    ''
    ' @brief Print message with newline.
    ''
    Private Unsafe Sub PrintMsg(ByVal strPtr As Pointer To Byte)
        DualPrint strPtr
        DualPrint CPtr(Pointer To Byte, "\r\n")
    End Sub

    ''
    ' @brief Atomically format prefix + 64-bit integer + suffix.
    ''
    Private Unsafe Sub PrintNum(ByVal prefix As Pointer To Byte, ByVal val As UInt64, ByVal suffix As Pointer To Byte)
        DualPrint prefix
        Dim nbuf(32) As Byte
        Dim nidx As UInt32 = 0
        AppendUInt val, @nbuf(0), nidx
        nbuf(nidx) = 0
        DualPrint @nbuf(0)
        DualPrint suffix
    End Sub

    ''
    ' @brief Assert condition is true. If false, log failure and increment failure counter.
    ' @param cond Boolean test condition.
    ' @param testName Human-readable description of test checkpoint.
    ''
    Private Unsafe Sub Assert(ByVal cond As Boolean, ByVal testName As Pointer To Byte)
        testsRun = testsRun + 1
        If cond Then
            testsPassed = testsPassed + 1
            PrintNum CPtr(Pointer To Byte, "  [PASS] #"), CType(UInt64, testsRun), CPtr(Pointer To Byte, " - ")
            PrintMsg testName
        Else
            testsFailed = testsFailed + 1
            PrintNum CPtr(Pointer To Byte, "  [FAIL] #"), CType(UInt64, testsRun), CPtr(Pointer To Byte, ": ")
            PrintMsg testName
        End If
    End Sub

    ' Local alias for Trim to bypass compiler built-in single-argument string intrinsic interception
    Private Declare Function StrTrim Lib "libpros" Alias "Pros_String_StringUtil_Trim" (ByVal src As Pointer To Byte, ByVal outBuf As Pointer To Byte) As UInt64

    ''
    ' @brief Test Suite 1: Pure Low-Level Basic String Utilities (String.bas)
    '        Exercises: StrLen, StrEquals, AppendStr, AppendUInt, AppendHex, Trim (6 APIs).
    ''
    Private Unsafe Sub TestStringSuite()
        PrintMsg CPtr(Pointer To Byte, "[TEST SUITE 1] Exercising Pros.String routines...")

        ' 1. StrLen
        Assert StrLen(0) = 0, CPtr(Pointer To Byte, "StrLen(NULL) == 0")
        Assert StrLen(CPtr(Pointer To Byte, "")) = 0, CPtr(Pointer To Byte, "StrLen('') == 0")
        Assert StrLen(CPtr(Pointer To Byte, "PROS")) = 4, CPtr(Pointer To Byte, "StrLen('PROS') == 4")
        Assert StrLen(CPtr(Pointer To Byte, "Low-Level Basic OS")) = 18, CPtr(Pointer To Byte, "StrLen('Low-Level Basic OS') == 18")

        ' 2. StrEquals
        Assert StrEquals(CPtr(Pointer To Byte, "kernel"), CPtr(Pointer To Byte, "kernel")), CPtr(Pointer To Byte, "StrEquals identical strings == True")
        Assert Not StrEquals(CPtr(Pointer To Byte, "kernel"), CPtr(Pointer To Byte, "userland")), CPtr(Pointer To Byte, "StrEquals different strings == False")
        Assert Not StrEquals(CPtr(Pointer To Byte, "abc"), CPtr(Pointer To Byte, "abcd")), CPtr(Pointer To Byte, "StrEquals prefix mismatch == False")
        Assert Not StrEquals(0, CPtr(Pointer To Byte, "abc")), CPtr(Pointer To Byte, "StrEquals(NULL, str) == False")
        Assert StrEquals(0, 0), CPtr(Pointer To Byte, "StrEquals(NULL, NULL) == True")

        ' 3. AppendStr
        Dim sbuf(64) As Byte
        Dim sidx As UInt32 = 0
        AppendStr CPtr(Pointer To Byte, "PROS "), @sbuf(0), sidx
        Assert sidx = 5, CPtr(Pointer To Byte, "AppendStr index updated to 5")
        AppendStr CPtr(Pointer To Byte, "Microkernel"), @sbuf(0), sidx
        Assert sidx = 16, CPtr(Pointer To Byte, "AppendStr index updated to 16")
        sbuf(sidx) = 0
        Assert StrEquals(@sbuf(0), CPtr(Pointer To Byte, "PROS Microkernel")), CPtr(Pointer To Byte, "AppendStr concatenated string matches")
        
        ' Defensive null append
        Dim prevIdx As UInt32 = sidx
        AppendStr 0, @sbuf(0), sidx
        Assert sidx = prevIdx, CPtr(Pointer To Byte, "AppendStr(NULL) preserves outIdx")

        ' 4. AppendUInt
        Dim ubuf(32) As Byte
        Dim uidx As UInt32 = 0
        AppendUInt 0, @ubuf(0), uidx
        ubuf(uidx) = 0
        Assert StrEquals(@ubuf(0), CPtr(Pointer To Byte, "0")), CPtr(Pointer To Byte, "AppendUInt(0) == '0'")

        uidx = 0
        AppendUInt 1234567890, @ubuf(0), uidx
        ubuf(uidx) = 0
        Assert StrEquals(@ubuf(0), CPtr(Pointer To Byte, "1234567890")), CPtr(Pointer To Byte, "AppendUInt(1234567890) == '1234567890'")

        ' 5. AppendHex
        Dim hbuf(32) As Byte
        Dim hidx As UInt32 = 0
        AppendHex 0, @hbuf(0), hidx
        hbuf(hidx) = 0
        Assert StrEquals(@hbuf(0), CPtr(Pointer To Byte, "0")), CPtr(Pointer To Byte, "AppendHex(0) == '0'")

        hidx = 0
        AppendHex &HCAFEBABE, @hbuf(0), hidx
        hbuf(hidx) = 0
        Assert StrEquals(@hbuf(0), CPtr(Pointer To Byte, "CAFEBABE")), CPtr(Pointer To Byte, "AppendHex(0xCAFEBABE) == 'CAFEBABE'")

        ' 6. Trim (exercising Pros_String_StringUtil_Trim via StrTrim / Trim)
        Dim tbuf(64) As Byte
        Dim tlen As UInt64 = 0
        tlen = StrTrim(CPtr(Pointer To Byte, "   hello trim   "), @tbuf(0))
        Assert tlen = 10, CPtr(Pointer To Byte, "Trim('   hello trim   ') length == 10")
        Assert StrEquals(@tbuf(0), CPtr(Pointer To Byte, "hello trim")), CPtr(Pointer To Byte, "Trim('   hello trim   ') content == 'hello trim'")

        tlen = StrTrim(CPtr(Pointer To Byte, "no_spaces"), @tbuf(0))
        Assert tlen = 9 And StrEquals(@tbuf(0), CPtr(Pointer To Byte, "no_spaces")), CPtr(Pointer To Byte, "Trim without whitespace preserved")

        tlen = StrTrim(CPtr(Pointer To Byte, "     "), @tbuf(0))
        Assert tlen = 0 And tbuf(0) = 0, CPtr(Pointer To Byte, "Trim all-whitespace == empty string")

        tlen = StrTrim(0, @tbuf(0))
        Assert tlen = 0 And tbuf(0) = 0, CPtr(Pointer To Byte, "Trim(NULL) == empty string")
    End Sub

    ''
    ' @brief Test Suite 2: Pure Low-Level Basic Memory Utilities (Memory.bas)
    '        Exercises: Copy, Move, SetBytes, MemSet, Compare (4 APIs + alias).
    ''
    Private Unsafe Sub TestMemorySuite()
        PrintMsg CPtr(Pointer To Byte, "[TEST SUITE 2] Exercising Pros.Memory routines...")

        ' 1. SetBytes & MemSet
        Dim mbuf1(32) As Byte
        Dim mi As UInt32 = 0
        While mi < 32
            mbuf1(mi) = 0
            mi = mi + 1
        Wend

        SetBytes @mbuf1(0), &H5A, 16
        Assert mbuf1(0) = &H5A And mbuf1(15) = &H5A, CPtr(Pointer To Byte, "SetBytes filled 16 bytes with 0x5A")
        Assert mbuf1(16) = 0, CPtr(Pointer To Byte, "SetBytes did not exceed boundary")

        ' MemSet alias
        MemSet @mbuf1(0), &H33, 8
        Assert mbuf1(0) = &H33 And mbuf1(7) = &H33, CPtr(Pointer To Byte, "MemSet alias filled first 8 bytes with 0x33")
        Assert mbuf1(8) = &H5A, CPtr(Pointer To Byte, "MemSet preserved tail bytes")

        ' 2. Copy
        Dim mbuf2(32) As Byte
        mi = 0
        While mi < 32
            mbuf2(mi) = 0
            mi = mi + 1
        Wend

        Copy @mbuf2(0), @mbuf1(0), 16
        Assert mbuf2(0) = &H33 And mbuf2(7) = &H33 And mbuf2(8) = &H5A And mbuf2(15) = &H5A, CPtr(Pointer To Byte, "Copy duplicated 16 bytes faithfully")
        Assert mbuf2(16) = 0, CPtr(Pointer To Byte, "Copy destination boundary preserved")

        ' 3. Move (Overlapping regions: test backward copy dest > src)
        Dim moveBuf(16) As Byte
        mi = 0
        While mi < 10
            moveBuf(mi) = CType(Byte, 48 + mi) ' '0'..'9'
            mi = mi + 1
        Wend
        moveBuf(10) = 0

        ' Overlapping move forward: move 6 bytes from index 0 to index 2
        ' Source was "0123456789", move 6 bytes -> dest index 2 receives "012345"
        Move @moveBuf(2), @moveBuf(0), 6
        Assert moveBuf(0) = 48 And moveBuf(1) = 49, CPtr(Pointer To Byte, "Move preserved untouched prefix")
        Assert moveBuf(2) = 48 And moveBuf(3) = 49 And moveBuf(4) = 50, CPtr(Pointer To Byte, "Move backward copy dest > src correctly copied overlapping bytes")
        Assert moveBuf(7) = 53, CPtr(Pointer To Byte, "Move tail of 6-byte overlapping span correct ('5')")

        ' 4. Compare
        Dim c1(8) As Byte
        Dim c2(8) As Byte
        c1(0) = 1: c1(1) = 2: c1(2) = 3: c1(3) = 4
        c2(0) = 1: c2(1) = 2: c2(2) = 3: c2(3) = 4

        Assert Compare(@c1(0), @c2(0), 4) = 0, CPtr(Pointer To Byte, "Compare identical buffers == 0")
        c2(3) = 5
        Assert Compare(@c1(0), @c2(0), 4) < 0, CPtr(Pointer To Byte, "Compare s1 < s2 returns negative")
        Assert Compare(@c2(0), @c1(0), 4) > 0, CPtr(Pointer To Byte, "Compare s1 > s2 returns positive")
        Assert Compare(@c1(0), @c2(0), 0) = 0, CPtr(Pointer To Byte, "Compare count 0 == 0")
    End Sub

    ''
    ' @brief Test Suite 3: Pure Low-Level Basic Math & Geometry (Math.bas)
    '        Exercises: Min, Max, Clamp, Abs, RectContains, UnionRect (6 APIs).
    ''
    Private Sub TestMathSuite()
        PrintMsg CPtr(Pointer To Byte, "[TEST SUITE 3] Exercising Pros.Math routines...")

        ' 1. Min
        Assert Min(10, 20) = 10, CPtr(Pointer To Byte, "Min(10, 20) == 10")
        Assert Min(-30, -10) = -30, CPtr(Pointer To Byte, "Min(-30, -10) == -30")
        Assert Min(-5, 5) = -5, CPtr(Pointer To Byte, "Min(-5, 5) == -5")
        Assert Min(42, 42) = 42, CPtr(Pointer To Byte, "Min(42, 42) == 42")

        ' 2. Max
        Assert Max(10, 20) = 20, CPtr(Pointer To Byte, "Max(10, 20) == 20")
        Assert Max(-30, -10) = -10, CPtr(Pointer To Byte, "Max(-30, -10) == -10")
        Assert Max(-5, 5) = 5, CPtr(Pointer To Byte, "Max(-5, 5) == 5")
        Assert Max(42, 42) = 42, CPtr(Pointer To Byte, "Max(42, 42) == 42")

        ' 3. Clamp
        Assert Clamp(5, 10, 50) = 10, CPtr(Pointer To Byte, "Clamp below minimum clamped to lowVal")
        Assert Clamp(25, 10, 50) = 25, CPtr(Pointer To Byte, "Clamp within range preserved")
        Assert Clamp(75, 10, 50) = 50, CPtr(Pointer To Byte, "Clamp above maximum clamped to highVal")
        Assert Clamp(-15, -10, 10) = -10, CPtr(Pointer To Byte, "Clamp negative boundary correct")

        ' 4. Abs
        Assert Abs(100) = 100, CPtr(Pointer To Byte, "Abs(100) == 100")
        Assert Abs(-100) = 100, CPtr(Pointer To Byte, "Abs(-100) == 100")
        Assert Abs(0) = 0, CPtr(Pointer To Byte, "Abs(0) == 0")

        ' 5. RectContains
        Dim r As Rect
        r.X = 10
        r.Y = 20
        r.Width = 30
        r.Height = 40

        Assert RectContains(r, 10, 20), CPtr(Pointer To Byte, "RectContains top-left inclusive == True")
        Assert RectContains(r, 25, 35), CPtr(Pointer To Byte, "RectContains interior point == True")
        Assert Not RectContains(r, 40, 60), CPtr(Pointer To Byte, "RectContains bottom-right exclusive == False")
        Assert Not RectContains(r, 5, 25), CPtr(Pointer To Byte, "RectContains outside left == False")
        Assert Not RectContains(r, 15, 5), CPtr(Pointer To Byte, "RectContains outside top == False")

        Dim emptyR As Rect
        emptyR.X = 0: emptyR.Y = 0: emptyR.Width = 0: emptyR.Height = 0
        Assert Not RectContains(emptyR, 0, 0), CPtr(Pointer To Byte, "RectContains degenerate rect == False")

        ' 6. UnionRect
        Dim r1 As Rect
        r1.X = 10: r1.Y = 20: r1.Width = 30: r1.Height = 40 ' covers [10..40, 20..60]
        Dim r2 As Rect
        r2.X = 20: r2.Y = 30: r2.Width = 50: r2.Height = 60 ' covers [20..70, 30..90]

        Dim outR As Rect
        UnionRect outR, r1, r2
        Assert outR.X = 10 And outR.Y = 20, CPtr(Pointer To Byte, "UnionRect origin top-left (10, 20)")
        Assert outR.Width = 60 And outR.Height = 70, CPtr(Pointer To Byte, "UnionRect span (60, 70)")

        ' Union with empty rect returns non-empty rect
        UnionRect outR, r1, emptyR
        Assert outR.X = 10 And outR.Y = 20 And outR.Width = 30 And outR.Height = 40, CPtr(Pointer To Byte, "UnionRect with empty rect returns active rect")
    End Sub

    ''
    ' @brief Test Suite 4: Pure Low-Level Basic Font Renderer (Font.bas)
    '        Exercises: DrawGlyph5x7, DrawText5x7, DrawGlyph8x16, DrawText8x16, DrawGlyph, DrawText (6 APIs).
    ''
    Private Unsafe Sub TestFontSuite()
        PrintMsg CPtr(Pointer To Byte, "[TEST SUITE 4] Exercising Pros.Drawing routines...")

        ' Initialize mock 64x64 Surface
        testSurf.Width = 64
        testSurf.Height = 64
        testSurf.Pitch = 64 * 4
        testSurf.Bpp = 32
        testSurf.Pixels = @mockPixels(0)

        ' Clear surface buffer
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384

        ' 1. DrawGlyph5x7
        ' Render 'A' (ASCII 65) at (8, 8) with color 0xFFFF0000
        DrawGlyph5x7 testSurf, 8, 8, 65, &HFFFF0000
        ' In 5x7 font, row 0 of 'A' is 14 (binary 01110) -> column 2 (px=10, py=8) is foreground
        Assert testSurf.Pixels(8 * 64 + 10) = &HFFFF0000, CPtr(Pointer To Byte, "DrawGlyph5x7 rendered foreground pixel (10, 8)")
        Assert testSurf.Pixels(8 * 64 + 8) = 0, CPtr(Pointer To Byte, "DrawGlyph5x7 background pixel untouched (8, 8)")

        ' Test clipping without crash
        DrawGlyph5x7 testSurf, -4, -4, 65, &HFFFF0000
        Assert True, CPtr(Pointer To Byte, "DrawGlyph5x7 negative clipping survived cleanly")
        DrawGlyph5x7 testSurf, 62, 62, 65, &HFFFF0000
        Assert True, CPtr(Pointer To Byte, "DrawGlyph5x7 right/bottom boundary clipping survived cleanly")

        ' 2. DrawText5x7
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384
        DrawText5x7 testSurf, 0, 0, CPtr(Pointer To Byte, "LLB"), &HFF00FF00
        ' Verify glyphs rendered: scan for set pixels in character 1 (0..5) and character 2 (6..11)
        Dim foundChar1 As Boolean = False
        Dim foundChar2 As Boolean = False
        Dim px As UInt32 = 0
        Dim py As UInt32 = 0
        While py < 7
            px = 0
            While px < 6
                If testSurf.Pixels(py * 64 + px) = &HFF00FF00 Then foundChar1 = True
                px = px + 1
            Wend
            px = 6
            While px < 12
                If testSurf.Pixels(py * 64 + px) = &HFF00FF00 Then foundChar2 = True
                px = px + 1
            Wend
            py = py + 1
        Wend
        Assert foundChar1 And foundChar2, CPtr(Pointer To Byte, "DrawText5x7 rendered multiple sequential glyphs")

        ' 3. DrawGlyph8x16
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384
        DrawGlyph8x16 testSurf, 16, 16, 66, &HFF0000FF ' 'B'
        Dim found8x16 As Boolean = False
        py = 16
        While py < 32
            px = 16
            While px < 24
                If testSurf.Pixels(py * 64 + px) = &HFF0000FF Then found8x16 = True
                px = px + 1
            Wend
            py = py + 1
        Wend
        Assert found8x16, CPtr(Pointer To Byte, "DrawGlyph8x16 rendered 8x16 glyph onto surface")
        Assert testSurf.Pixels(16 * 64 + 25) = 0, CPtr(Pointer To Byte, "DrawGlyph8x16 right boundary pixel untouched")

        ' 4. DrawText8x16
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384
        DrawText8x16 testSurf, 0, 32, CPtr(Pointer To Byte, "PROS"), &HFFFFFF00
        Dim foundText8x16 As Boolean = False
        py = 32
        While py < 48
            px = 0
            While px < 32
                If testSurf.Pixels(py * 64 + px) = &HFFFFFF00 Then foundText8x16 = True
                px = px + 1
            Wend
            py = py + 1
        Wend
        Assert foundText8x16, CPtr(Pointer To Byte, "DrawText8x16 rendered 8x16 text string across scanlines")

        ' 5. DrawGlyph (Generic wrapper selecting 5x7 and 8x16)
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384
        DrawGlyph testSurf, 0, 0, 67, &HFFFF00FF, False
        Assert testSurf.Pixels(0 * 64 + 2) = &HFFFF00FF Or testSurf.Pixels(1 * 64 + 2) = &HFFFF00FF, CPtr(Pointer To Byte, "DrawGlyph(useLargeFont=False) routed to 5x7")

        DrawGlyph testSurf, 16, 0, 67, &HFF00FFFF, True
        Dim foundLargeGlyph As Boolean = False
        py = 0
        While py < 16
            px = 16
            While px < 24
                If testSurf.Pixels(py * 64 + px) = &HFF00FFFF Then foundLargeGlyph = True
                px = px + 1
            Wend
            py = py + 1
        Wend
        Assert foundLargeGlyph, CPtr(Pointer To Byte, "DrawGlyph(useLargeFont=True) routed to 8x16")

        ' 6. DrawText (Generic wrapper selecting 5x7 and 8x16)
        SetBytes CPtr(Pointer To Byte, @mockPixels(0)), 0, 16384
        DrawText testSurf, 0, 0, CPtr(Pointer To Byte, "OK"), &HFF123456, False
        DrawText testSurf, 0, 16, CPtr(Pointer To Byte, "OK"), &HFF654321, True
        Assert testSurf.Pixels(0 * 64 + 1) = &HFF123456 Or testSurf.Pixels(1 * 64 + 1) = &HFF123456, CPtr(Pointer To Byte, "DrawText(useLargeFont=False) rendered 5x7 text")
        
        Dim foundLargeText As Boolean = False
        py = 16
        While py < 32
            px = 0
            While px < 16
                If testSurf.Pixels(py * 64 + px) = &HFF654321 Then foundLargeText = True
                px = px + 1
            Wend
            py = py + 1
        Wend
        Assert foundLargeText, CPtr(Pointer To Byte, "DrawText(useLargeFont=True) rendered 8x16 text")
    End Sub

    ''
    ' @brief Application entry point invoked by Basic Runtime (BRT0).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit status: 0 if 100% passed, 1 if any test failed.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg CPtr(Pointer To Byte, "========================================================")
        PrintMsg CPtr(Pointer To Byte, "[TEST-STDLIB] PROS Pure Low-Level Basic Standard Library Suite")
        PrintMsg CPtr(Pointer To Byte, "========================================================")

        TestStringSuite
        TestMemorySuite
        TestMathSuite
        TestFontSuite

        PrintMsg CPtr(Pointer To Byte, "--------------------------------------------------------")
        PrintNum CPtr(Pointer To Byte, "[TEST-STDLIB] Total Tests Run   : "), CType(UInt64, testsRun), CPtr(Pointer To Byte, "\r\n")
        PrintNum CPtr(Pointer To Byte, "[TEST-STDLIB] Total Tests Passed: "), CType(UInt64, testsPassed), CPtr(Pointer To Byte, "\r\n")
        PrintNum CPtr(Pointer To Byte, "[TEST-STDLIB] Total Tests Failed: "), CType(UInt64, testsFailed), CPtr(Pointer To Byte, "\r\n")
        PrintMsg CPtr(Pointer To Byte, "--------------------------------------------------------")

        If testsFailed = 0 Then
            PrintMsg CPtr(Pointer To Byte, "[TEST-STDLIB] ALL 22 STANDARD LIBRARY APIS VERIFIED [PASS]!")
            PrintMsg CPtr(Pointer To Byte, "========================================================")
            user_main = 0
        Else
            PrintMsg CPtr(Pointer To Byte, "[TEST-STDLIB] SUITE FAILED WITH REGRESSIONS [FAIL]!")
            PrintMsg CPtr(Pointer To Byte, "========================================================")
            user_main = 1
        End If
    End Function

End Module

