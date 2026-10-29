' Project Name: Low-Level Basic Geometric & Screen Dimension Stress Test
' Filename: tests/geometric_stress_test/src/GeometricStressMain.bas
' Summary: Comprehensive adversarial stress test for geometric clipping, signed Int32 dimensions, and drawing routines.

Import "../../../include/pros.bas"

Module GeometricStressMain

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    ' Canaries and pixel buffers for 32bpp and 24bpp
    Private preCanary32(7) As UInt64
    Private pixels32(4095) As UInt32
    Private postCanary32(7) As UInt64

    Private preCanary24(7) As UInt64
    Private pixels24(12287) As Byte
    Private postCanary24(7) As UInt64

    Private srcPixels32(4095) As UInt32
    Private srcPixels24(12287) As Byte

    Private testSurf32 As Surface
    Private testSurf24 As Surface
    Private testSrc32 As Surface
    Private testSrc24 As Surface

    Const CANARY_PRE  As UInt64 = &HDEADBEEFCAFEBABE
    Const CANARY_POST As UInt64 = &HFEEDFACEBAADF00D

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
            DualPrint " - "
            PrintMsg testName
        End If
    End Sub

    Private Unsafe Sub ResetCanaries()
        Dim i As UInt32 = 0
        While i < 8
            preCanary32(i) = CANARY_PRE
            postCanary32(i) = CANARY_POST
            preCanary24(i) = CANARY_PRE
            postCanary24(i) = CANARY_POST
            i = i + 1
        Wend
    End Sub

    Private Unsafe Function CheckCanaries() As Boolean
        Dim i As UInt32 = 0
        While i < 8
            If preCanary32(i) <> CANARY_PRE Then
                CheckCanaries = False
                Exit Function
            End If
            If postCanary32(i) <> CANARY_POST Then
                CheckCanaries = False
                Exit Function
            End If
            If preCanary24(i) <> CANARY_PRE Then
                CheckCanaries = False
                Exit Function
            End If
            If postCanary24(i) <> CANARY_POST Then
                CheckCanaries = False
                Exit Function
            End If
            i = i + 1
        Wend
        CheckCanaries = True
    End Function

    Private Unsafe Sub ClearBuffers()
        SetBytes CPtr(Pointer To Byte, @pixels32(0)), 0, 4096 * 4
        SetBytes CPtr(Pointer To Byte, @pixels24(0)), 0, 12288
        SetBytes CPtr(Pointer To Byte, @srcPixels32(0)), &HAA, 4096 * 4
        SetBytes CPtr(Pointer To Byte, @srcPixels24(0)), &H55, 12288
        ResetCanaries
    End Sub

    Private Unsafe Function CountPixels32() As UInt32
        Dim count As UInt32 = 0
        Dim i As UInt32 = 0
        While i < 4096
            If pixels32(i) <> 0 Then
                count = count + 1
            End If
            i = i + 1
        Wend
        CountPixels32 = count
    End Function

    Private Unsafe Function CountPixels24() As UInt32
        Dim count As UInt32 = 0
        Dim i As UInt32 = 0
        While i < 12288
            If pixels24(i) <> 0 Then
                count = count + 1
            End If
            i = i + 1
        Wend
        CountPixels24 = count
    End Function

    ' =========================================================================
    ' Suite 1: FillRect (32bpp) Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteFillRect32()
        PrintMsg "[SUITE 1] FillRect 32bpp Adversarial Stress..."

        ' 1.1 Partial negative coordinates
        ClearBuffers
        FillRect testSurf32, -10, -10, 30, 30, &HFFFF0000
        AssertTrue CountPixels32() = 400, "FillRect 32bpp partial negative coordinates (-10, -10, 30, 30) draws visible 20x20 region"
        AssertTrue testSurf32.Pixels(0) = &HFFFF0000, "FillRect 32bpp origin (0,0) filled"
        AssertTrue testSurf32.Pixels(19 * 64 + 19) = &HFFFF0000, "FillRect 32bpp (19,19) filled"
        AssertTrue testSurf32.Pixels(20 * 64 + 20) = 0, "FillRect 32bpp (20,20) untouched"

        ' 1.2 Completely negative coordinates
        ClearBuffers
        FillRect testSurf32, -50, -50, 20, 20, &HFFFF0000
        AssertTrue CountPixels32() = 0, "FillRect 32bpp completely negative coordinates (-50, -50, 20, 20) draws 0 pixels"

        ' 1.3 Partial out of bounds right/bottom
        ClearBuffers
        FillRect testSurf32, 50, 50, 30, 30, &HFF00FF00
        AssertTrue CountPixels32() = 196, "FillRect 32bpp partial right/bottom clipping (50, 50, 30, 30) draws visible 14x14 region"
        AssertTrue testSurf32.Pixels(50 * 64 + 50) = &HFF00FF00, "FillRect 32bpp (50,50) filled"
        AssertTrue testSurf32.Pixels(63 * 64 + 63) = &HFF00FF00, "FillRect 32bpp (63,63) filled"

        ' 1.4 Completely out of bounds right/bottom
        ClearBuffers
        FillRect testSurf32, 100, 100, 20, 20, &HFF00FF00
        AssertTrue CountPixels32() = 0, "FillRect 32bpp completely out of bounds (100, 100, 20, 20) draws 0 pixels"

        ' 1.5 Zero width or height
        ClearBuffers
        FillRect testSurf32, 0, 0, 0, 20, &HFF0000FF
        FillRect testSurf32, 0, 0, 20, 0, &HFF0000FF
        FillRect testSurf32, 0, 0, 0, 0, &HFF0000FF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp zero width or height draws 0 pixels"

        ' 1.6 Negative width or height
        ClearBuffers
        FillRect testSurf32, 10, 10, -10, 20, &HFF0000FF
        FillRect testSurf32, 10, 10, 20, -10, &HFF0000FF
        FillRect testSurf32, 10, 10, -20, -20, &HFF0000FF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp negative width or height draws 0 pixels"

        ' 1.7 Minimum Int32 dimensions (-2147483648)
        ClearBuffers
        FillRect testSurf32, 0, 0, &H80000000, 20, &HFF0000FF
        FillRect testSurf32, 0, 0, 20, &H80000000, &HFF0000FF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp min Int32 dimensions (&H80000000) draws 0 pixels"

        ' 1.8 Zero surface dimensions
        ClearBuffers
        Dim zeroSurf As Surface = testSurf32
        zeroSurf.Width = 0
        FillRect zeroSurf, 0, 0, 20, 20, &HFFFFFFFF
        zeroSurf.Width = 64
        zeroSurf.Height = 0
        FillRect zeroSurf, 0, 0, 20, 20, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp with zero surface dimensions draws 0 pixels"

        ' 1.9 Negative surface dimensions
        ClearBuffers
        Dim negSurf As Surface = testSurf32
        negSurf.Width = -10
        FillRect negSurf, 0, 0, 20, 20, &HFFFFFFFF
        negSurf.Width = 64
        negSurf.Height = -10
        FillRect negSurf, 0, 0, 20, 20, &HFFFFFFFF
        negSurf.Width = &H80000000
        negSurf.Height = &H80000000
        FillRect negSurf, 0, 0, 20, 20, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp with negative surface dimensions draws 0 pixels"

        ' 1.10 Extreme positive coordinates (near 2^31 - 1)
        ClearBuffers
        FillRect testSurf32, &H7FFFFFFF, 0, 10, 10, &HFFFFFFFF
        FillRect testSurf32, 0, &H7FFFFFFF, 10, 10, &HFFFFFFFF
        FillRect testSurf32, &H7FFFFFF0, &H7FFFFFF0, 100, 100, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp extreme positive coordinates (&H7FFFFFFF) draws 0 pixels"

        ' 1.11 Extreme negative coordinates (near -2^31)
        ClearBuffers
        FillRect testSurf32, &H80000000, 0, 10, 10, &HFFFFFFFF
        FillRect testSurf32, 0, &H80000000, 10, 10, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp extreme negative coordinates (&H80000000) draws 0 pixels"

        ' 1.12 Addition overflow in x1/y1
        ClearBuffers
        FillRect testSurf32, 2147483640, 0, 20, 10, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp addition overflow (rx=2147483640, rw=20) safely handled with 0 pixels"

        ' 1.13 Full surface span with negative rx
        ClearBuffers
        FillRect testSurf32, -10, 0, &H7FFFFFFF, 10, &HFF123456
        AssertTrue CountPixels32() = 640, "FillRect 32bpp giant width (rw=&H7FFFFFFF) clamped to full surface width (64 * 10 = 640 pixels)"

        ' 1.14 Null pixel pointer
        ClearBuffers
        Dim nullSurf As Surface = testSurf32
        nullSurf.Pixels = 0
        FillRect nullSurf, 0, 0, 10, 10, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "FillRect 32bpp with null Pixels pointer safely exits"

        ' 1.15 Canaries verification
        AssertTrue CheckCanaries(), "FillRect 32bpp stack/heap canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 2: FillRect (24bpp) Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteFillRect24()
        PrintMsg "[SUITE 2] FillRect 24bpp Adversarial Stress..."

        ' 2.1 Partial negative coordinates
        ClearBuffers
        FillRect testSurf24, -10, -10, 30, 30, &H00FFFFFF
        AssertTrue CountPixels24() = 400 * 3, "FillRect 24bpp partial negative coordinates (-10, -10, 30, 30) draws visible 20x20 region"

        ' 2.2 Completely negative coordinates
        ClearBuffers
        FillRect testSurf24, -50, -50, 20, 20, &H00FFFFFF
        AssertTrue CountPixels24() = 0, "FillRect 24bpp completely negative coordinates draws 0 bytes"

        ' 2.3 Partial right/bottom clipping
        ClearBuffers
        FillRect testSurf24, 50, 50, 30, 30, &H00FFFFFF
        AssertTrue CountPixels24() = 196 * 3, "FillRect 24bpp partial right/bottom clipping draws 14x14 region"

        ' 2.4 Completely out of bounds
        ClearBuffers
        FillRect testSurf24, 100, 100, 20, 20, &H0000FF00
        AssertTrue CountPixels24() = 0, "FillRect 24bpp completely out of bounds draws 0 bytes"

        ' 2.5 Zero and negative dimensions
        ClearBuffers
        FillRect testSurf24, 0, 0, 0, 10, &H00FFFFFF
        FillRect testSurf24, 0, 0, 10, -10, &H00FFFFFF
        FillRect testSurf24, 0, 0, &H80000000, 10, &H00FFFFFF
        AssertTrue CountPixels24() = 0, "FillRect 24bpp zero or negative dimensions draws 0 bytes"

        ' 2.6 Zero and negative surface dimensions
        ClearBuffers
        Dim negSurf As Surface = testSurf24
        negSurf.Width = 0
        FillRect negSurf, 0, 0, 10, 10, &H00FFFFFF
        negSurf.Width = -10
        FillRect negSurf, 0, 0, 10, 10, &H00FFFFFF
        AssertTrue CountPixels24() = 0, "FillRect 24bpp zero or negative surface dimensions draws 0 bytes"

        ' 2.7 Extreme coordinates
        ClearBuffers
        FillRect testSurf24, &H7FFFFFFF, 0, 10, 10, &H00FFFFFF
        FillRect testSurf24, &H80000000, 0, 10, 10, &H00FFFFFF
        AssertTrue CountPixels24() = 0, "FillRect 24bpp extreme coordinates (&H7FFFFFFF, &H80000000) draws 0 bytes"

        ' 2.8 Canaries verification
        AssertTrue CheckCanaries(), "FillRect 24bpp canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 3: Blit (32bpp) Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteBlit32()
        PrintMsg "[SUITE 3] Blit 32bpp Adversarial Stress..."

        ' 3.1 Partial negative destination coordinates
        ClearBuffers
        Blit testSurf32, -10, -10, testSrc32, 0, 0, 30, 30
        AssertTrue CountPixels32() = 400, "Blit 32bpp partial negative dest (-10, -10, w=30, h=30) copies visible 20x20 region"

        ' 3.2 Partial negative source coordinates
        ClearBuffers
        Blit testSurf32, 0, 0, testSrc32, -10, -10, 30, 30
        AssertTrue CountPixels32() = 400, "Blit 32bpp partial negative source (-10, -10, w=30, h=30) copies visible 20x20 region"

        ' 3.3 Completely negative destination coordinates
        ClearBuffers
        Blit testSurf32, -50, -50, testSrc32, 0, 0, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp completely negative dest draws 0 pixels"

        ' 3.4 Completely out of bounds positive destination
        ClearBuffers
        Blit testSurf32, 100, 100, testSrc32, 0, 0, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp completely out of bounds dest draws 0 pixels"

        ' 3.5 Completely negative source coordinates
        ClearBuffers
        Blit testSurf32, 0, 0, testSrc32, -50, -50, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp completely negative source draws 0 pixels"

        ' 3.6 Completely out of bounds positive source
        ClearBuffers
        Blit testSurf32, 0, 0, testSrc32, 100, 100, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp completely out of bounds source draws 0 pixels"

        ' 3.7 Partial out of bounds right/bottom
        ClearBuffers
        Blit testSurf32, 50, 50, testSrc32, 0, 0, 30, 30
        AssertTrue CountPixels32() = 196, "Blit 32bpp partial right/bottom clipping copies 14x14 region"

        ' 3.8 Zero or negative blit dimensions
        ClearBuffers
        Blit testSurf32, 0, 0, testSrc32, 0, 0, 0, 20
        Blit testSurf32, 0, 0, testSrc32, 0, 0, 20, 0
        Blit testSurf32, 0, 0, testSrc32, 0, 0, -10, 20
        Blit testSurf32, 0, 0, testSrc32, 0, 0, 20, -10
        Blit testSurf32, 0, 0, testSrc32, 0, 0, &H80000000, 10
        AssertTrue CountPixels32() = 0, "Blit 32bpp zero or negative width/height draws 0 pixels"

        ' 3.9 Zero or negative destination surface dimensions
        ClearBuffers
        Dim negDst As Surface = testSurf32
        negDst.Width = 0
        Blit negDst, 0, 0, testSrc32, 0, 0, 20, 20
        negDst.Width = -10
        Blit negDst, 0, 0, testSrc32, 0, 0, 20, 20
        negDst.Width = &H80000000
        Blit negDst, 0, 0, testSrc32, 0, 0, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp zero or negative destination surface dimensions draws 0 pixels"

        ' 3.10 Zero or negative source surface dimensions
        ClearBuffers
        Dim negSrc As Surface = testSrc32
        negSrc.Width = 0
        Blit testSurf32, 0, 0, negSrc, 0, 0, 20, 20
        negSrc.Width = -10
        Blit testSurf32, 0, 0, negSrc, 0, 0, 20, 20
        negSrc.Width = &H80000000
        Blit testSurf32, 0, 0, negSrc, 0, 0, 20, 20
        AssertTrue CountPixels32() = 0, "Blit 32bpp zero or negative source surface dimensions draws 0 pixels"

        ' 3.11 Extreme coordinates near 2^31 - 1 and -2^31
        ClearBuffers
        Blit testSurf32, &H7FFFFFFF, 0, testSrc32, 0, 0, 10, 10
        Blit testSurf32, &H80000000, 0, testSrc32, 0, 0, 10, 10
        Blit testSurf32, 0, 0, testSrc32, &H7FFFFFFF, 0, 10, 10
        Blit testSurf32, 0, 0, testSrc32, &H80000000, 0, 10, 10
        AssertTrue CountPixels32() = 0, "Blit 32bpp extreme coordinates (&H7FFFFFFF, &H80000000) draws 0 pixels"

        ' 3.12 Null pixel pointers
        ClearBuffers
        Dim nullSurf As Surface = testSurf32
        nullSurf.Pixels = 0
        Blit nullSurf, 0, 0, testSrc32, 0, 0, 10, 10
        Blit testSurf32, 0, 0, nullSurf, 0, 0, 10, 10
        AssertTrue CountPixels32() = 0, "Blit 32bpp with null Pixels pointers exits cleanly"

        ' 3.13 Canaries verification
        AssertTrue CheckCanaries(), "Blit 32bpp canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 4: Blit (24bpp) Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteBlit24()
        PrintMsg "[SUITE 4] Blit 24bpp Adversarial Stress..."

        ' 4.1 Partial negative destination coordinates
        ClearBuffers
        Blit testSurf24, -10, -10, testSrc24, 0, 0, 30, 30
        AssertTrue CountPixels24() = 400 * 3, "Blit 24bpp partial negative dest copies 20x20 region"

        ' 4.2 Completely negative destination coordinates
        ClearBuffers
        Blit testSurf24, -50, -50, testSrc24, 0, 0, 20, 20
        AssertTrue CountPixels24() = 0, "Blit 24bpp completely negative dest draws 0 bytes"

        ' 4.3 Partial out of bounds right/bottom
        ClearBuffers
        Blit testSurf24, 50, 50, testSrc24, 0, 0, 30, 30
        AssertTrue CountPixels24() = 196 * 3, "Blit 24bpp partial right/bottom clipping copies 14x14 region"

        ' 4.4 Completely out of bounds positive destination
        ClearBuffers
        Blit testSurf24, 100, 100, testSrc24, 0, 0, 20, 20
        AssertTrue CountPixels24() = 0, "Blit 24bpp completely out of bounds dest draws 0 bytes"

        ' 4.5 Zero and negative dimensions
        ClearBuffers
        Blit testSurf24, 0, 0, testSrc24, 0, 0, 0, 10
        Blit testSurf24, 0, 0, testSrc24, 0, 0, -10, 10
        AssertTrue CountPixels24() = 0, "Blit 24bpp zero or negative dimensions draws 0 bytes"

        ' 4.6 Zero and negative surface dimensions
        ClearBuffers
        Dim negSurf As Surface = testSurf24
        negSurf.Width = 0
        Blit negSurf, 0, 0, testSrc24, 0, 0, 10, 10
        negSurf.Width = -10
        Blit negSurf, 0, 0, testSrc24, 0, 0, 10, 10
        AssertTrue CountPixels24() = 0, "Blit 24bpp zero or negative surface dimensions draws 0 bytes"

        ' 4.7 Extreme coordinates
        ClearBuffers
        Blit testSurf24, &H7FFFFFFF, 0, testSrc24, 0, 0, 10, 10
        Blit testSurf24, &H80000000, 0, testSrc24, 0, 0, 10, 10
        AssertTrue CountPixels24() = 0, "Blit 24bpp extreme coordinates draws 0 bytes"

        ' 4.8 Canaries verification
        AssertTrue CheckCanaries(), "Blit 24bpp canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 5: DrawGlyph5x7 Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteDrawGlyph5x7()
        PrintMsg "[SUITE 5] DrawGlyph5x7 Adversarial Stress..."

        ' 5.1 Partial negative X coordinates (-1..-4)
        ClearBuffers
        DrawGlyph5x7 testSurf32, -2, 0, 65, &HFFFF0000 ' 'A'
        AssertTrue CountPixels32() > 0, "DrawGlyph5x7 partial negative X (-2) renders visible columns"
        AssertTrue testSurf32.Pixels(0) = &HFFFF0000, "DrawGlyph5x7 row 0 col 2 (at screen 0) is rendered"

        ' 5.2 Complete negative X clipping (gx + 5 <= 0)
        ClearBuffers
        DrawGlyph5x7 testSurf32, -5, 0, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, -6, 0, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, -100, 0, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 complete negative X clipping (gx <= -5) draws 0 pixels"

        ' 5.3 Partial negative Y coordinates (-1..-6)
        ClearBuffers
        DrawGlyph5x7 testSurf32, 0, -3, 65, &HFFFF0000
        AssertTrue CountPixels32() > 0, "DrawGlyph5x7 partial negative Y (-3) renders visible bottom rows"

        ' 5.4 Complete negative Y clipping (gy + 7 <= 0)
        ClearBuffers
        DrawGlyph5x7 testSurf32, 0, -7, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 0, -8, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 0, -100, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 complete negative Y clipping (gy <= -7) draws 0 pixels"

        ' 5.5 Partial right clipping
        ClearBuffers
        DrawGlyph5x7 testSurf32, 61, 0, 65, &HFFFF0000 ' cols 0..2 at 61..63, cols 3..4 clipped
        AssertTrue CountPixels32() > 0, "DrawGlyph5x7 partial right clipping renders visible left columns"
        AssertTrue testSurf32.Pixels(63) = &HFFFF0000, "DrawGlyph5x7 pixel at edge (63,0) rendered"

        ' 5.6 Complete offscreen right
        ClearBuffers
        DrawGlyph5x7 testSurf32, 64, 0, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 100, 0, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 complete offscreen right (gx >= surf.Width) draws 0 pixels"

        ' 5.7 Partial bottom clipping
        ClearBuffers
        DrawGlyph5x7 testSurf32, 0, 60, 65, &HFFFF0000 ' rows 0..3 at 60..63, rows 4..6 clipped
        AssertTrue CountPixels32() > 0, "DrawGlyph5x7 partial bottom clipping renders visible top rows"

        ' 5.8 Complete offscreen bottom
        ClearBuffers
        DrawGlyph5x7 testSurf32, 0, 64, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 0, 100, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 complete offscreen bottom (gy >= surf.Height) draws 0 pixels"

        ' 5.9 Zero or negative surface dimensions
        ClearBuffers
        Dim negSurf As Surface = testSurf32
        negSurf.Width = 0
        DrawGlyph5x7 negSurf, 0, 0, 65, &HFFFF0000
        negSurf.Width = -10
        DrawGlyph5x7 negSurf, 0, 0, 65, &HFFFF0000
        negSurf.Width = 64
        negSurf.Height = 0
        DrawGlyph5x7 negSurf, 0, 0, 65, &HFFFF0000
        negSurf.Height = -10
        DrawGlyph5x7 negSurf, 0, 0, 65, &HFFFF0000
        negSurf.Width = &H80000000
        negSurf.Height = &H80000000
        DrawGlyph5x7 negSurf, 0, 0, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 with zero or negative surface dimensions draws 0 pixels"

        ' 5.10 Extreme coordinates near 2^31 - 1
        ClearBuffers
        DrawGlyph5x7 testSurf32, &H7FFFFFFF, 0, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 2147483645, 0, 65, &HFFFF0000 ' gx + 5 overflows signed 32-bit
        DrawGlyph5x7 testSurf32, 0, &H7FFFFFFF, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 0, 2147483641, 65, &HFFFF0000 ' gy + 7 overflows signed 32-bit
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 extreme coordinates (&H7FFFFFFF and overflow values) draws 0 pixels"

        ' 5.11 Extreme coordinates near -2^31
        ClearBuffers
        DrawGlyph5x7 testSurf32, &H80000000, 0, 65, &HFFFF0000
        DrawGlyph5x7 testSurf32, 0, &H80000000, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 extreme negative coordinates (&H80000000) draws 0 pixels"

        ' 5.12 ASCII bounds checking
        ClearBuffers
        DrawGlyph5x7 testSurf32, 0, 0, 0, &HFFFF0000   ' < 32
        DrawGlyph5x7 testSurf32, 0, 0, 31, &HFFFF0000  ' < 32
        DrawGlyph5x7 testSurf32, 0, 0, 127, &HFFFF0000 ' > 126
        DrawGlyph5x7 testSurf32, 0, 0, 255, &HFFFF0000 ' > 126
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 invalid ASCII byte values (0, 31, 127, 255) safely rejected"

        ' 5.13 Null pixel pointer
        ClearBuffers
        Dim nullSurf As Surface = testSurf32
        nullSurf.Pixels = 0
        DrawGlyph5x7 nullSurf, 0, 0, 65, &HFFFF0000
        AssertTrue CountPixels32() = 0, "DrawGlyph5x7 with null Pixels pointer exits cleanly"

        ' 5.14 24bpp rendering mode
        ClearBuffers
        DrawGlyph5x7 testSurf24, -2, -2, 65, &H00FF0000
        AssertTrue CountPixels24() > 0, "DrawGlyph5x7 24bpp partial negative coordinates renders correctly"

        ' 5.15 Canaries verification
        AssertTrue CheckCanaries(), "DrawGlyph5x7 canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 6: DrawGlyph8x16 Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteDrawGlyph8x16()
        PrintMsg "[SUITE 6] DrawGlyph8x16 Adversarial Stress..."

        ' 6.1 Partial negative X coordinates (-1..-7)
        ClearBuffers
        DrawGlyph8x16 testSurf32, -3, 0, 66, &HFF00FF00 ' 'B'
        AssertTrue CountPixels32() > 0, "DrawGlyph8x16 partial negative X (-3) renders visible columns"

        ' 6.2 Complete negative X clipping (gx + 8 <= 0)
        ClearBuffers
        DrawGlyph8x16 testSurf32, -8, 0, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, -9, 0, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, -100, 0, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 complete negative X clipping (gx <= -8) draws 0 pixels"

        ' 6.3 Partial negative Y coordinates (-1..-15)
        ClearBuffers
        DrawGlyph8x16 testSurf32, 0, -8, 66, &HFF00FF00
        AssertTrue CountPixels32() > 0, "DrawGlyph8x16 partial negative Y (-8) renders visible bottom rows"

        ' 6.4 Complete negative Y clipping (gy + 16 <= 0)
        ClearBuffers
        DrawGlyph8x16 testSurf32, 0, -16, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, -17, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, -100, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 complete negative Y clipping (gy <= -16) draws 0 pixels"

        ' 6.5 Partial right clipping
        ClearBuffers
        DrawGlyph8x16 testSurf32, 58, 0, 66, &HFF00FF00 ' cols 0..5 at 58..63, cols 6..7 clipped
        AssertTrue CountPixels32() > 0, "DrawGlyph8x16 partial right clipping renders visible left columns"

        ' 6.6 Complete offscreen right
        ClearBuffers
        DrawGlyph8x16 testSurf32, 64, 0, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 100, 0, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 complete offscreen right (gx >= surf.Width) draws 0 pixels"

        ' 6.7 Partial bottom clipping
        ClearBuffers
        DrawGlyph8x16 testSurf32, 0, 52, 66, &HFF00FF00 ' rows 0..11 at 52..63, rows 12..15 clipped
        AssertTrue CountPixels32() > 0, "DrawGlyph8x16 partial bottom clipping renders visible top rows"

        ' 6.8 Complete offscreen bottom
        ClearBuffers
        DrawGlyph8x16 testSurf32, 0, 64, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, 100, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 complete offscreen bottom (gy >= surf.Height) draws 0 pixels"

        ' 6.9 Zero or negative surface dimensions
        ClearBuffers
        Dim negSurf As Surface = testSurf32
        negSurf.Width = 0
        DrawGlyph8x16 negSurf, 0, 0, 66, &HFF00FF00
        negSurf.Width = -10
        DrawGlyph8x16 negSurf, 0, 0, 66, &HFF00FF00
        negSurf.Width = 64
        negSurf.Height = 0
        DrawGlyph8x16 negSurf, 0, 0, 66, &HFF00FF00
        negSurf.Height = -10
        DrawGlyph8x16 negSurf, 0, 0, 66, &HFF00FF00
        negSurf.Width = &H80000000
        negSurf.Height = &H80000000
        DrawGlyph8x16 negSurf, 0, 0, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 with zero or negative surface dimensions draws 0 pixels"

        ' 6.10 Extreme coordinates near 2^31 - 1
        ClearBuffers
        DrawGlyph8x16 testSurf32, &H7FFFFFFF, 0, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 2147483640, 0, 66, &HFF00FF00 ' gx + 8 overflows signed 32-bit
        DrawGlyph8x16 testSurf32, 0, &H7FFFFFFF, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, 2147483632, 66, &HFF00FF00 ' gy + 16 overflows signed 32-bit
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 extreme coordinates (&H7FFFFFFF and overflow values) draws 0 pixels"

        ' 6.11 Extreme coordinates near -2^31
        ClearBuffers
        DrawGlyph8x16 testSurf32, &H80000000, 0, 66, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, &H80000000, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 extreme negative coordinates (&H80000000) draws 0 pixels"

        ' 6.12 ASCII bounds checking (> 127)
        ClearBuffers
        DrawGlyph8x16 testSurf32, 0, 0, 128, &HFF00FF00
        DrawGlyph8x16 testSurf32, 0, 0, 255, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 ASCII > 127 safely rejected"

        ' 6.13 Null pixel pointer
        ClearBuffers
        Dim nullSurf As Surface = testSurf32
        nullSurf.Pixels = 0
        DrawGlyph8x16 nullSurf, 0, 0, 66, &HFF00FF00
        AssertTrue CountPixels32() = 0, "DrawGlyph8x16 with null Pixels pointer exits cleanly"

        ' 6.14 24bpp rendering mode
        ClearBuffers
        DrawGlyph8x16 testSurf24, -4, -4, 66, &H0000FF00
        AssertTrue CountPixels24() > 0, "DrawGlyph8x16 24bpp partial negative coordinates renders correctly"

        ' 6.15 Canaries verification
        AssertTrue CheckCanaries(), "DrawGlyph8x16 canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 7: DrawText5x7 & DrawText8x16 Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteDrawText()
        PrintMsg "[SUITE 7] DrawText5x7 and DrawText8x16 Adversarial Stress..."

        ' 7.1 Text starting far offscreen negative
        ClearBuffers
        DrawText5x7 testSurf32, -200, 0, "OFFSCREEN", &HFFFFFFFF
        DrawText8x16 testSurf32, -200, 0, "OFFSCREEN", &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "DrawText far negative offscreen (-200) draws 0 pixels"

        ' 7.2 Text starting offscreen positive
        ClearBuffers
        DrawText5x7 testSurf32, 200, 0, "OFFSCREEN", &HFFFFFFFF
        DrawText8x16 testSurf32, 200, 0, "OFFSCREEN", &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "DrawText far positive offscreen (200) draws 0 pixels"

        ' 7.3 Text with extreme coordinates
        ClearBuffers
        DrawText5x7 testSurf32, &H7FFFFFFF, 0, "EXTREME", &HFFFFFFFF
        DrawText5x7 testSurf32, &H80000000, 0, "EXTREME", &HFFFFFFFF
        DrawText8x16 testSurf32, &H7FFFFFFF, 0, "EXTREME", &HFFFFFFFF
        DrawText8x16 testSurf32, &H80000000, 0, "EXTREME", &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "DrawText extreme coordinates (&H7FFFFFFF, &H80000000) draws 0 pixels"

        ' 7.4 Text with null string pointer
        ClearBuffers
        Dim nullStr As String = 0
        DrawText5x7 testSurf32, 0, 0, nullStr, &HFFFFFFFF
        DrawText8x16 testSurf32, 0, 0, nullStr, &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "DrawText with null String pointer safely exits"

        ' 7.5 Text with empty string
        ClearBuffers
        DrawText5x7 testSurf32, 0, 0, "", &HFFFFFFFF
        DrawText8x16 testSurf32, 0, 0, "", &HFFFFFFFF
        AssertTrue CountPixels32() = 0, "DrawText with empty string safely exits"

        ' 7.6 Canaries verification
        AssertTrue CheckCanaries(), "DrawText canaries intact (no buffer underflow/overrun)"
    End Sub

    ' =========================================================================
    ' Suite 8: Geometry Math (RectContains, UnionRect) Adversarial Stress
    ' =========================================================================
    Private Unsafe Sub TestSuiteGeometryMath()
        PrintMsg "[SUITE 8] Geometry Math (RectContains, UnionRect) Adversarial Stress..."

        Dim r As Rect
        r.X = -10
        r.Y = -20
        r.Width = 40
        r.Height = 50

        ' 8.1 RectContains with negative coordinates inside
        AssertTrue RectContains(r, -10, -20), "RectContains top-left negative inclusive (-10, -20) == True"
        AssertTrue RectContains(r, 0, 0), "RectContains interior origin (0, 0) == True"
        AssertTrue RectContains(r, 29, 29), "RectContains interior bottom-right (29, 29) == True"

        ' 8.2 RectContains outside negative
        AssertTrue Not RectContains(r, -11, 0), "RectContains outside left (-11, 0) == False"
        AssertTrue Not RectContains(r, 0, -21), "RectContains outside top (0, -21) == False"
        AssertTrue Not RectContains(r, 30, 0), "RectContains right boundary exclusive (30, 0) == False"
        AssertTrue Not RectContains(r, 0, 30), "RectContains bottom boundary exclusive (0, 30) == False"

        ' 8.3 RectContains with zero and negative dimensions
        Dim degR As Rect
        degR.X = 10: degR.Y = 10: degR.Width = 0: degR.Height = 20
        AssertTrue Not RectContains(degR, 10, 10), "RectContains with width=0 == False"
        degR.Width = 20: degR.Height = 0
        AssertTrue Not RectContains(degR, 10, 10), "RectContains with height=0 == False"
        degR.Width = -10: degR.Height = 20
        AssertTrue Not RectContains(degR, 5, 10), "RectContains with negative width == False"
        degR.Width = &H80000000: degR.Height = 20
        AssertTrue Not RectContains(degR, 0, 0), "RectContains with min Int32 width (&H80000000) == False"

        ' 8.4 RectContains with extreme points
        AssertTrue Not RectContains(r, &H7FFFFFFF, 0), "RectContains px=&H7FFFFFFF == False"
        AssertTrue Not RectContains(r, &H80000000, 0), "RectContains px=&H80000000 == False"

        ' 8.5 UnionRect with negative coordinates
        Dim r1 As Rect
        r1.X = -30: r1.Y = -20: r1.Width = 50: r1.Height = 40 ' covers [-30..20, -20..20]
        Dim r2 As Rect
        r2.X = -10: r2.Y = -10: r2.Width = 60: r2.Height = 50 ' covers [-10..50, -10..40]
        Dim outR As Rect
        UnionRect outR, r1, r2
        AssertTrue outR.X = -30 And outR.Y = -20, "UnionRect negative origin (-30, -20)"
        AssertTrue outR.Width = 80 And outR.Height = 60, "UnionRect span spanning negative to positive (80, 60)"

        ' 8.6 UnionRect with degenerate/empty rects
        Dim emptyR As Rect
        emptyR.X = 0: emptyR.Y = 0: emptyR.Width = 0: emptyR.Height = 0
        UnionRect outR, r1, emptyR
        AssertTrue outR.X = -30 And outR.Y = -20 And outR.Width = 50 And outR.Height = 40, "UnionRect with empty rect preserves active rect"

        Dim negR As Rect
        negR.X = 10: negR.Y = 10: negR.Width = -5: negR.Height = -5
        UnionRect outR, r1, negR
        AssertTrue outR.X = -30 And outR.Y = -20 And outR.Width = 50 And outR.Height = 40, "UnionRect with negative dimensions rect preserves active rect"
    End Sub

    ' =========================================================================
    ' Main Entry Point
    ' =========================================================================
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[TEST-GEOMETRIC-STRESS] Adversarial Dimension & Drawing Stress Suite"
        PrintMsg "========================================================"

        ' Initialize mock surfaces
        testSurf32.Width = 64
        testSurf32.Height = 64
        testSurf32.Pitch = 64 * 4
        testSurf32.Bpp = 32
        testSurf32.Pixels = @pixels32(0)

        testSurf24.Width = 64
        testSurf24.Height = 64
        testSurf24.Pitch = 64 * 3
        testSurf24.Bpp = 24
        testSurf24.Pixels = CPtr(Pointer To UInt32, @pixels24(0))

        testSrc32.Width = 64
        testSrc32.Height = 64
        testSrc32.Pitch = 64 * 4
        testSrc32.Bpp = 32
        testSrc32.Pixels = @srcPixels32(0)

        testSrc24.Width = 64
        testSrc24.Height = 64
        testSrc24.Pitch = 64 * 3
        testSrc24.Bpp = 24
        testSrc24.Pixels = CPtr(Pointer To UInt32, @srcPixels24(0))

        TestSuiteFillRect32
        TestSuiteFillRect24
        TestSuiteBlit32
        TestSuiteBlit24
        TestSuiteDrawGlyph5x7
        TestSuiteDrawGlyph8x16
        TestSuiteDrawText
        TestSuiteGeometryMath

        PrintMsg "--------------------------------------------------------"
        Dim sRun(16) As Byte
        Dim sPass(16) As Byte
        Dim sFail(16) As Byte
        Dim idx As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @sRun(0), idx: sRun(idx) = 0
        idx = 0: AppendUInt CType(UInt64, testsPassed), @sPass(0), idx: sPass(idx) = 0
        idx = 0: AppendUInt CType(UInt64, testsFailed), @sFail(0), idx: sFail(idx) = 0

        DualPrint "[TEST-GEOMETRIC-STRESS] Total Tests Run   : "
        DualPrint @sRun(0)
        DualPrint "\r\n"
        DualPrint "[TEST-GEOMETRIC-STRESS] Total Tests Passed: "
        DualPrint @sPass(0)
        DualPrint "\r\n"
        DualPrint "[TEST-GEOMETRIC-STRESS] Total Tests Failed: "
        DualPrint @sFail(0)
        DualPrint "\r\n"
        PrintMsg "--------------------------------------------------------"

        If testsFailed = 0 And testsRun > 0 Then
            PrintMsg "[TEST-GEOMETRIC-STRESS] ALL GEOMETRIC & CLIPPING ADVERSARIAL TESTS PASSED [PASS]!"
            PrintMsg "========================================================"
            user_main = 0
        Else
            PrintMsg "[TEST-GEOMETRIC-STRESS] SUITE FAILED WITH REGRESSIONS [FAIL]!"
            PrintMsg "========================================================"
            user_main = 1
        End If
    End Function

End Module
