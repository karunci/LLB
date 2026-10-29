' Project Name: Low-Level Basic Userland Service Deduplication Stress Test Suite
' Filename: tests/dedup_stress_test/src/DedupStressMain.bas
' Summary: Empirical verification and adversarial stress-testing of libpros deduplicated routines
'          (DrawText5x7, AppendUInt, AppendStr, AppendHex, StrEquals) across userland service contexts.

Import "../../../include/pros.bas"

Module DedupStressMain

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    ' Dedicated pixel buffers for font rendering tests
    ' 1. Small surface: 64x64 = 4096 DWORDs (allocated 8192 for safety)
    Private mockPixels64(8192) As UInt32
    Private surf64 As Surface

    ' 2. Emulated Service Surface: 480x280 = 134400 DWORDs (allocated 150000 for safety)
    Private mockPixelsService(150000) As UInt32
    Private serviceSurf As Surface

    ''
    ' @brief Dual-mode printer for stdout output in QEMU userland and microkernel.
    ''
    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        ' PROS Microkernel console write: %rax=1, %rdi=s, %rsi=length
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        ' Linux userland stdout write: %rax=1, %rdi=1 (stdout), %rsi=s, %rdx=length
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

    ''
    ' @brief Clear surface pixel buffer with zero.
    ''
    Private Unsafe Sub ClearSurface(ByRef surf As Surface, ByVal totalPixels As UInt32)
        If surf.Pixels = 0 Then Exit Sub
        Dim p As Pointer To UInt32 = surf.Pixels
        Dim i As UInt32 = 0
        While i < totalPixels
            p(i) = 0
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Count non-zero pixels within a bounding rectangle on a surface.
    ''
    Private Unsafe Function CountColoredPixels(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal w As Int32, ByVal h As Int32, ByVal targetColor As UInt32) As UInt32
        If surf.Pixels = 0 Then
            CountColoredPixels = 0
            Exit Function
        End If
        Dim count As UInt32 = 0
        Dim pitchPix As UInt32 = surf.Pitch / 4
        Dim pPix As Pointer To UInt32 = surf.Pixels
        Dim py As Int32 = y
        While py < y + h
            If py >= 0 And py < CType(Int32, surf.Height) Then
                Dim px As Int32 = x
                While px < x + w
                    If px >= 0 And px < CType(Int32, surf.Width) Then
                        Dim pixOffset As UInt32 = CType(UInt32, py) * pitchPix + CType(UInt32, px)
                        If pPix(pixOffset) = targetColor Then
                            count = count + 1
                        End If
                    End If
                    px = px + 1
                Wend
            End If
            py = py + 1
        Wend
        CountColoredPixels = count
    End Function

    ' =========================================================================
    ' SUITE 1: DrawText5x7 Adversarial Stress & Rendering Parity
    ' =========================================================================
    Private Unsafe Sub TestDrawText5x7Suite()
        PrintMsg "[SUITE 1] Adversarial DrawText5x7 Stress & Font Parity..."

        ' Initialize 64x64 surface
        surf64.Width = 64
        surf64.Height = 64
        surf64.Pitch = 64 * 4
        surf64.Bpp = 32
        surf64.Pixels = @mockPixels64(0)

        ' 1.1 Null and Empty Inputs (Safety & Crash Prevention)
        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, 0, &HFFFFFFFF
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 64, &HFFFFFFFF) = 0, "DrawText5x7 with null string (0) does not draw or crash"

        DrawText5x7 surf64, 0, 0, "", &HFFFFFFFF
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 64, &HFFFFFFFF) = 0, "DrawText5x7 with empty string ('') does not draw or crash"

        Dim nullSurf As Surface
        nullSurf.Pixels = 0
        nullSurf.Width = 64
        nullSurf.Height = 64
        nullSurf.Pitch = 256
        nullSurf.Bpp = 32
        DrawText5x7 nullSurf, 0, 0, "HELLO", &HFFFFFFFF
        AssertTrue True, "DrawText5x7 with null surface pixels survived cleanly"

        Dim zeroSizeSurf As Surface
        zeroSizeSurf.Pixels = @mockPixels64(0)
        zeroSizeSurf.Width = 0
        zeroSizeSurf.Height = 0
        zeroSizeSurf.Pitch = 0
        zeroSizeSurf.Bpp = 32
        DrawText5x7 zeroSizeSurf, 0, 0, "HELLO", &HFFFFFFFF
        AssertTrue True, "DrawText5x7 with zero dimension surface survived cleanly"

        ' 1.2 Coordinate Clipping Boundaries
        ClearSurface surf64, 4096
        ' Far negative coordinates
        DrawText5x7 surf64, -100, -100, "OFFSCREEN", &HFF00FF00
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 64, &HFF00FF00) = 0, "DrawText5x7 far negative off-screen survived and drew 0 pixels"

        ' Far positive coordinates
        DrawText5x7 surf64, 1000, 1000, "OFFSCREEN", &HFF00FF00
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 64, &HFF00FF00) = 0, "DrawText5x7 far positive off-screen survived and drew 0 pixels"

        ' Partial negative clipping: x = -2 (first 2 columns clipped, columns 2..4 visible on left edge)
        ClearSurface surf64, 4096
        DrawText5x7 surf64, -2, 0, "A", &HFFFF0000
        ' 'A' has foreground pixels in rows 0..6: row 0 is (col 1,2,3). With gx=-2, col 2 is at px = -2+2 = 0
        Dim leftEdgeCount As UInt32 = CountColoredPixels(surf64, 0, 0, 10, 10, &HFFFF0000)
        AssertTrue leftEdgeCount > 0, "DrawText5x7 partial negative X clipping renders visible portion"

        ' Partial right clipping: x = 60 on 64-wide surface. 3-char string "ABC" needs 3 * 6 = 18 px
        ClearSurface surf64, 4096
        DrawText5x7 surf64, 60, 0, "ABC", &HFF0000FF
        Dim rightEdgeCount As UInt32 = CountColoredPixels(surf64, 60, 0, 4, 10, &HFF0000FF)
        AssertTrue rightEdgeCount > 0, "DrawText5x7 partial right boundary clipping renders visible portion without overflow"

        ' Partial bottom clipping: y = 60 on 64-high surface (7 rows high font, bottom 3 rows clip)
        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 60, "A", &HFFFFFF00
        Dim bottomEdgeCount As UInt32 = CountColoredPixels(surf64, 0, 60, 10, 4, &HFFFFFF00)
        AssertTrue bottomEdgeCount > 0, "DrawText5x7 partial bottom boundary clipping renders top 4 rows without overflow"

        ' 1.3 Exact Glyph Row Pattern Verification
        ' Verify 'A' (ASCII 65): in FONT_5X7, row 0 is 14 (binary 01110)
        ' When rendered at (10, 10), px spans 10..14. row 0: px=11, 12, 13 should be set, px=10, 14 should be 0
        ClearSurface surf64, 4096
        DrawText5x7 surf64, 10, 10, "A", &HFF112233
        AssertTrue surf64.Pixels(10 * 64 + 10) = 0, "Glyph 'A' row 0 col 0 is background"
        AssertTrue surf64.Pixels(10 * 64 + 11) = &HFF112233, "Glyph 'A' row 0 col 1 is foreground"
        AssertTrue surf64.Pixels(10 * 64 + 12) = &HFF112233, "Glyph 'A' row 0 col 2 is foreground"
        AssertTrue surf64.Pixels(10 * 64 + 13) = &HFF112233, "Glyph 'A' row 0 col 3 is foreground"
        AssertTrue surf64.Pixels(10 * 64 + 14) = 0, "Glyph 'A' row 0 col 4 is background"

        ' 1.4 Character Spacing Parity
        ' In 5x7 font, each character advances cx by 6 (5 px glyph + 1 px spacing).
        ' "AB" at (0, 0): 'A' occupies cols 0..4, col 5 is space (all 0), 'B' occupies cols 6..10.
        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, "AB", &HFF55AA55
        ' Column 5 should be empty space
        Dim col5Count As UInt32 = CountColoredPixels(surf64, 5, 0, 1, 7, &HFF55AA55)
        AssertTrue col5Count = 0, "Character spacing column 5 is blank separator between 'A' and 'B'"
        Dim charA_Count As UInt32 = CountColoredPixels(surf64, 0, 0, 5, 7, &HFF55AA55)
        Dim charB_Count As UInt32 = CountColoredPixels(surf64, 6, 0, 5, 7, &HFF55AA55)
        AssertTrue charA_Count > 0, "Character 'A' has active foreground pixels"
        AssertTrue charB_Count > 0, "Character 'B' has active foreground pixels"

        ' 1.5 Full ASCII Range & Deduplicated Service String Parity
        ' Verify rendering of strings specifically used across the 5 GUI services:
        ClearSurface surf64, 4096
        ' Compositor strings:
        DrawText5x7 surf64, 0, 0, "REV: 2026.10.29-r37-re02", &HFF88C0D0
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 7, &HFF88C0D0) > 0, "Compositor REV banner renders successfully"

        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, "FPS: 60", &HFF88C0D0
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 7, &HFF88C0D0) > 0, "DispService FPS counter renders successfully"

        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, "pros:> sys.status", &HFFEBCB8B
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 7, &HFFEBCB8B) > 0, "Terminal shell prompt renders successfully"

        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, "ARCH: x86_64 SMP (4 Cores)", &HFF81A1C1
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 7, &HFF81A1C1) > 0, "SysMon microkernel telemetry renders successfully"

        ClearSurface surf64, 4096
        DrawText5x7 surf64, 0, 0, "#1000 kernel.core", &HFFA3BE8C
        AssertTrue CountColoredPixels(surf64, 0, 0, 64, 7, &HFFA3BE8C) > 0, "NodeViewer neural topology entry renders successfully"
    End Sub

    ' =========================================================================
    ' SUITE 2: String Formatting & Equality Adversarial Matrix
    ' =========================================================================
    Private Unsafe Sub TestStringSuite()
        PrintMsg "[SUITE 2] Adversarial String Formatting & Comparison Matrix..."

        ' 2.1 AppendUInt Comprehensive Test Matrix
        Dim ubuf(128) As Byte
        Dim uidx As UInt32 = 0

        ' Value 0
        uidx = 0
        AppendUInt 0, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "0"), "AppendUInt(0) == '0'"
        AssertTrue uidx = 1, "AppendUInt(0) advances index by 1"

        ' Small values
        uidx = 0
        AppendUInt 7, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "7"), "AppendUInt(7) == '7'"

        uidx = 0
        AppendUInt 10, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "10"), "AppendUInt(10) == '10'"

        uidx = 0
        AppendUInt 99, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "99"), "AppendUInt(99) == '99'"

        uidx = 0
        AppendUInt 100, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "100"), "AppendUInt(100) == '100'"

        ' Standard service values
        uidx = 0
        AppendUInt 60, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "60"), "AppendUInt(60) == '60' (FPS)"

        uidx = 0
        AppendUInt 1000, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "1000"), "AppendUInt(1000) == '1000' (Kernel Node ID)"

        ' Large values & Max 64-bit UInt
        uidx = 0
        AppendUInt 4294967295, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "4294967295"), "AppendUInt(2^32 - 1) == '4294967295'"

        uidx = 0
        AppendUInt &HFFFFFFFFFFFFFFFF, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "18446744073709551615"), "AppendUInt(2^64 - 1) == '18446744073709551615'"

        ' Multi-append sequential formatting without buffer reset
        uidx = 0
        AppendUInt 1, @ubuf(0), uidx
        AppendUInt 2, @ubuf(0), uidx
        AppendUInt 3, @ubuf(0), uidx
        ubuf(uidx) = 0
        AssertTrue StrEquals(@ubuf(0), "123"), "Sequential AppendUInt(1, 2, 3) == '123'"
        AssertTrue uidx = 3, "Sequential AppendUInt index == 3"

        ' Safety with null buffer pointer
        AppendUInt 1234, 0, uidx
        AssertTrue True, "AppendUInt with null buffer pointer survived without crash"

        ' 2.2 AppendHex Comprehensive Test Matrix
        Dim hbuf(128) As Byte
        Dim hidx As UInt32 = 0

        ' Value 0
        hidx = 0
        AppendHex 0, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "0"), "AppendHex(0) == '0'"
        AssertTrue hidx = 1, "AppendHex(0) advances index by 1"

        ' Single nibbles
        hidx = 0
        AppendHex 10, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "A"), "AppendHex(10) == 'A'"

        hidx = 0
        AppendHex 15, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "F"), "AppendHex(15) == 'F'"

        hidx = 0
        AppendHex 16, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "10"), "AppendHex(16) == '10'"

        hidx = 0
        AppendHex 255, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "FF"), "AppendHex(255) == 'FF'"

        ' Standard 32-bit & 64-bit Hex Magic
        hidx = 0
        AppendHex &HCAFEBABE, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "CAFEBABE"), "AppendHex(0xCAFEBABE) == 'CAFEBABE'"

        hidx = 0
        AppendHex &HDEADBEEF, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "DEADBEEF"), "AppendHex(0xDEADBEEF) == 'DEADBEEF'"

        hidx = 0
        AppendHex &H64000000, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "64000000"), "AppendHex(0x64000000) == '64000000' (SysMon SHM)"

        hidx = 0
        AppendHex &HFFFFFFFFFFFFFFFF, @hbuf(0), hidx
        hbuf(hidx) = 0
        AssertTrue StrEquals(@hbuf(0), "FFFFFFFFFFFFFFFF"), "AppendHex(0xFFFFFFFFFFFFFFFF) == 'FFFFFFFFFFFFFFFF'"

        ' Safety with null buffer pointer
        AppendHex &H1234, 0, hidx
        AssertTrue True, "AppendHex with null buffer pointer survived without crash"

        ' 2.3 AppendStr Formatting & Concatenation Matrix
        Dim sbuf(128) As Byte
        Dim sidx As UInt32 = 0

        ' Standard append
        sidx = 0
        AppendStr "PROS", @sbuf(0), sidx
        sbuf(sidx) = 0
        AssertTrue StrEquals(@sbuf(0), "PROS"), "AppendStr('PROS') == 'PROS'"
        AssertTrue sidx = 4, "AppendStr('PROS') advances index by 4"

        ' Empty string append
        Dim prevIdx As UInt32 = sidx
        AppendStr "", @sbuf(0), sidx
        AssertTrue sidx = prevIdx, "AppendStr('') preserves index without modification"

        ' Null string append
        AppendStr 0, @sbuf(0), sidx
        AssertTrue sidx = prevIdx, "AppendStr(0) preserves index without modification"

        ' Null buffer pointer append
        AppendStr "TEST", 0, sidx
        AssertTrue True, "AppendStr with null buffer survived without crash"

        ' Composite telemetry formatting (exact emulation of SysMon dynamic line)
        sidx = 0
        AppendStr "UPTIME: ", @sbuf(0), sidx
        AppendUInt 120, @sbuf(0), sidx
        AppendStr " SEC  |  TICKS: ", @sbuf(0), sidx
        AppendUInt 120000, @sbuf(0), sidx
        sbuf(sidx) = 0
        AssertTrue StrEquals(@sbuf(0), "UPTIME: 120 SEC  |  TICKS: 120000"), "Composite SysMon telemetry formatted identically"

        ' Composite coordinate formatting (exact emulation of Compositor cursor status)
        sidx = 0
        AppendStr "X: ", @sbuf(0), sidx
        AppendUInt 512, @sbuf(0), sidx
        AppendStr "  Y: ", @sbuf(0), sidx
        AppendUInt 384, @sbuf(0), sidx
        sbuf(sidx) = 0
        AssertTrue StrEquals(@sbuf(0), "X: 512  Y: 384"), "Composite Compositor coordinate line formatted identically"

        ' 2.4 StrEquals Comprehensive Adversarial Matrix
        ' Identical
        AssertTrue StrEquals("hello", "hello"), "StrEquals('hello', 'hello') == True"
        AssertTrue StrEquals("", ""), "StrEquals('', '') == True"
        AssertTrue StrEquals(0, 0), "StrEquals(0, 0) == True"

        ' Different contents
        AssertFalse StrEquals("hello", "world"), "StrEquals('hello', 'world') == False"
        AssertFalse StrEquals("hello", "hell"), "StrEquals prefix mismatch length == False"
        AssertFalse StrEquals("hell", "hello"), "StrEquals suffix mismatch length == False"
        AssertFalse StrEquals("hello", "Hello"), "StrEquals case sensitivity mismatch == False"

        ' Mismatch at specific indices
        AssertFalse StrEquals("xello", "hello"), "StrEquals 1st byte mismatch == False"
        AssertFalse StrEquals("hexlo", "hello"), "StrEquals middle byte mismatch == False"
        AssertFalse StrEquals("hellx", "hello"), "StrEquals last byte mismatch == False"

        ' Null combinations
        AssertFalse StrEquals(0, "hello"), "StrEquals(0, 'hello') == False"
        AssertFalse StrEquals("hello", 0), "StrEquals('hello', 0) == False"
        AssertFalse StrEquals(0, ""), "StrEquals(0, '') == False"
        AssertFalse StrEquals("", 0), "StrEquals('', 0) == False"

        ' Service daemon path/name lookups
        AssertTrue StrEquals("srv.compositor", "srv.compositor"), "StrEquals service name 'srv.compositor'"
        AssertTrue StrEquals("srv.wm", "srv.wm"), "StrEquals service name 'srv.wm'"
        AssertTrue StrEquals("/dev/fb0", "/dev/fb0"), "StrEquals device path '/dev/fb0'"
        AssertFalse StrEquals("srv.vfs", "srv.wm"), "StrEquals service name mismatch"
    End Sub

    ' =========================================================================
    ' SUITE 3: Stack Integrity & Canary Protection
    ' =========================================================================
    Private Unsafe Sub TestStackCanarySuite()
        PrintMsg "[SUITE 3] Stack Integrity & Canary Preservation..."

        ' Place explicit canaries on stack surrounding format buffer
        Dim canaryBefore As UInt64 = &HDEADBEEFCAFEBABE
        Dim stackBuf(32) As Byte
        Dim canaryAfter As UInt64 = &H1122334455667788

        ' Perform heavy multi-type formatting inside stack buffer
        Dim sIdx As UInt32 = 0
        AppendStr "TEST:", @stackBuf(0), sIdx
        AppendUInt 123456789, @stackBuf(0), sIdx
        AppendHex &HABCDEF, @stackBuf(0), sIdx
        stackBuf(sIdx) = 0

        ' Verify canaries are completely untouched
        AssertTrue canaryBefore = &HDEADBEEFCAFEBABE, "Canary before stack buffer intact"
        AssertTrue canaryAfter = &H1122334455667788, "Canary after stack buffer intact"
        AssertTrue StrEquals(@stackBuf(0), "TEST:123456789ABCDEF"), "Formatted stack content matches expectation"

        ' Verify repeated rendering onto surface with stack Surface descriptor
        Dim stackSurf As Surface
        Dim localCanary1 As UInt64 = &HAAAAAAAAAAAAAAAA
        stackSurf.Width = 64
        stackSurf.Height = 64
        stackSurf.Pitch = 256
        stackSurf.Bpp = 32
        stackSurf.Pixels = @mockPixels64(0)
        Dim localCanary2 As UInt64 = &H5555555555555555

        DrawText5x7 stackSurf, 0, 0, "STACK_CANARY_TEST", &HFFFFFFFF
        AssertTrue localCanary1 = &HAAAAAAAAAAAAAAAA, "Stack canary 1 intact after DrawText5x7 call"
        AssertTrue localCanary2 = &H5555555555555555, "Stack canary 2 intact after DrawText5x7 call"
    End Sub

    ' =========================================================================
    ' SUITE 4: Emulated Multi-Service GUI Presentation Pipeline
    ' =========================================================================
    Private Unsafe Sub TestServiceSimulationSuite()
        PrintMsg "[SUITE 4] Emulated Multi-Service GUI Presentation Pipeline..."

        ' Initialize emulated service canvas (480x280)
        serviceSurf.Width = 480
        serviceSurf.Height = 280
        serviceSurf.Pitch = 480 * 4
        serviceSurf.Bpp = 32
        serviceSurf.Pixels = @mockPixelsService(0)

        ' ---------------------------------------------------------------------
        ' 4.1 Compositor Presentation Pipeline Simulation
        ' ---------------------------------------------------------------------
        ClearSurface serviceSurf, 480 * 280
        ' Top desktop menu bar
        DrawText5x7 serviceSurf, 16, 10, "PROS WORKSTATION  |  APPLICATIONS  NODES  SERVICES", &HFFECEFF4
        DrawText5x7 serviceSurf, 120, 10, "REV: 2026.10.29-r37-re02", &HFF88C0D0
        DrawText5x7 serviceSurf, 310, 10, "SMP 4 CORES  ONLINE", &HFFA3BE8C

        ' Status badges (FPS, Coordinates)
        Dim compFpsBuf(16) As Byte
        Dim compFpsIdx As UInt32 = 0
        AppendStr "FPS: ", @compFpsBuf(0), compFpsIdx
        AppendUInt 60, @compFpsBuf(0), compFpsIdx
        compFpsBuf(compFpsIdx) = 0
        DrawText5x7 serviceSurf, 200, 30, @compFpsBuf(0), &HFF88C0D0

        Dim compCoordBuf(32) As Byte
        Dim compCoordIdx As UInt32 = 0
        AppendStr "X: ", @compCoordBuf(0), compCoordIdx
        AppendUInt 1024, @compCoordBuf(0), compCoordIdx
        AppendStr "  Y: ", @compCoordBuf(0), compCoordIdx
        AppendUInt 768, @compCoordBuf(0), compCoordIdx
        compCoordBuf(compCoordIdx) = 0
        DrawText5x7 serviceSurf, 200, 45, @compCoordBuf(0), &HFFEBCB8B

        Dim compTotalPixels As UInt32 = CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFECEFF4) + _
                                        CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFF88C0D0) + _
                                        CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFA3BE8C) + _
                                        CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFEBCB8B)
        AssertTrue compTotalPixels > 0, "Compositor simulation rendered full desktop header and telemetry"

        ' ---------------------------------------------------------------------
        ' 4.2 Terminal Shell Pipeline Simulation
        ' ---------------------------------------------------------------------
        ClearSurface serviceSurf, 480 * 280
        DrawText5x7 serviceSurf, 10, 6, "PROS TERMINAL CONSOLE  [TTY 1]  CPL=3", &HFF88C0D0
        DrawText5x7 serviceSurf, 12, 28, "PRK-LLB Interactive Diagnostic Shell v1.0", &HFFD8DEE9
        DrawText5x7 serviceSurf, 12, 42, "Type 'help' for built-in diagnostic routines", &HFF4C566A
        DrawText5x7 serviceSurf, 12, 62, "pros:> sys.status", &HFFEBCB8B

        Dim termPixels As UInt32 = CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFF88C0D0) + _
                                   CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFD8DEE9) + _
                                   CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFEBCB8B)
        AssertTrue termPixels > 0, "Terminal simulation rendered diagnostic console and command prompt"

        ' ---------------------------------------------------------------------
        ' 4.3 SysMon Telemetry Pipeline Simulation
        ' ---------------------------------------------------------------------
        ClearSurface serviceSurf, 480 * 280
        ' Microkernel Card
        DrawText5x7 serviceSurf, 22, 16, "PROS MICROKERNEL TELEMETRY [CPL=3]", &HFFECEFF4
        DrawText5x7 serviceSurf, 22, 30, "ARCH: x86_64 SMP (4 Cores Online)", &HFF81A1C1
        DrawText5x7 serviceSurf, 22, 44, "KERNEL REV: 2026.10.29-r37-re02", &HFFEBCB8B
        DrawText5x7 serviceSurf, 22, 58, "STATUS: SYSTEM HEALTH OPTIMAL", &HFFA3BE8C

        ' Dynamic Uptime/Ticks Line
        Dim sysMonBuf(64) As Byte
        Dim smIdx As UInt32 = 0
        AppendStr "UPTIME: ", @sysMonBuf(0), smIdx
        AppendUInt 3600, @sysMonBuf(0), smIdx
        AppendStr " SEC  |  TICKS: ", @sysMonBuf(0), smIdx
        AppendUInt 3600000, @sysMonBuf(0), smIdx
        sysMonBuf(smIdx) = 0
        DrawText5x7 serviceSurf, 22, 214, @sysMonBuf(0), &HFFEBCB8B

        Dim sysMonPixels As UInt32 = CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFECEFF4) + _
                                     CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFEBCB8B)
        AssertTrue sysMonPixels > 0, "SysMon simulation rendered telemetry cards and dynamic uptime line"

        ' ---------------------------------------------------------------------
        ' 4.4 NodeViewer Neural Topology Simulation
        ' ---------------------------------------------------------------------
        ClearSurface serviceSurf, 480 * 280
        DrawText5x7 serviceSurf, 10, 6, "NEURAL NODE TOPOLOGY & SYNAPSE PLANE", &HFF88C0D0
        DrawText5x7 serviceSurf, 10, 26, "ID      NAME            ROLE          STATUS", &HFF4C566A
        DrawText5x7 serviceSurf, 10, 42, "#1000   kernel.core     CONTROL       ONLINE", &HFFA3BE8C
        DrawText5x7 serviceSurf, 10, 56, "#1003   srv.display     DISPLAY_DRV   ACTIVE", &HFF81A1C1
        DrawText5x7 serviceSurf, 10, 70, "#1007   srv.input       INPUT_ROUTER  ACTIVE", &HFFEBCB8B
        DrawText5x7 serviceSurf, 10, 84, "#1009   srv.wm          COMPOSITOR    ACTIVE", &HFF88C0D0
        DrawText5x7 serviceSurf, 10, 98, "#1011   srv.vfs         STORAGE_NODE  ACTIVE", &HFF88C0D0

        Dim nodeViewerPixels As UInt32 = CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFF88C0D0) + _
                                         CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFA3BE8C)
        AssertTrue nodeViewerPixels > 0, "NodeViewer simulation rendered neural node table and roles"

        ' ---------------------------------------------------------------------
        ' 4.5 DispService FPS Driver Simulation
        ' ---------------------------------------------------------------------
        ClearSurface serviceSurf, 480 * 280
        Dim dispFpsBuf(16) As Byte
        Dim dfIdx As UInt32 = 0
        AppendStr "FPS: ", @dispFpsBuf(0), dfIdx
        AppendUInt 59, @dispFpsBuf(0), dfIdx
        dispFpsBuf(dfIdx) = 0
        DrawText5x7 serviceSurf, 10, 10, @dispFpsBuf(0), &HFFFFFFFF

        Dim dispFpsPixels As UInt32 = CountColoredPixels(serviceSurf, 0, 0, 480, 280, &HFFFFFFFF)
        AssertTrue dispFpsPixels > 0, "DispService simulation formatted and rendered active FPS counter"
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[TEST-DEDUP-STRESS] Empirical Userland Deduplication Stress Test"
        PrintMsg "========================================================"

        TestDrawText5x7Suite
        TestStringSuite
        TestStackCanarySuite
        TestServiceSimulationSuite

        ' Summary Output
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

        DualPrint "[TEST-DEDUP-STRESS] Total Tests Run   : "
        PrintMsg @rBuf(0)
        DualPrint "[TEST-DEDUP-STRESS] Total Tests Passed: "
        PrintMsg @pBuf(0)
        DualPrint "[TEST-DEDUP-STRESS] Total Tests Failed: "
        PrintMsg @fBuf(0)
        PrintMsg "--------------------------------------------------------"

        If testsFailed = 0 Then
            PrintMsg "[TEST-DEDUP-STRESS] ALL DEDUPLICATION ADVERSARIAL TESTS PASSED!"
            PrintMsg "========================================================"
            user_main = 0
        Else
            PrintMsg "[TEST-DEDUP-STRESS] ADVERSARIAL STRESS TESTS FAILED!"
            PrintMsg "========================================================"
            user_main = 1
        End If
    End Function

End Module
