' Project Name: Low-Level Basic M2 Empirical Stress Test Suite
' Filename: tests/m2_empirical_test/src/M2EmpiricalMain.bas
' Summary: Empirical verification and adversarial stress-testing of Milestone 2:
'          Compositor bounding box union math, fast_blit32 DWORD alignment (x0 * 4 % 8 == 4),
'          Window drag & resize coordinate offsets with signed Int32, and cursor boundary clipping.

Import "../../../include/pros.bas"

Module M2EmpiricalMain

    Public Declare Sub fast_blit32 Lib "libc" (ByVal dst As Pointer To UInt32, ByVal src As Pointer To UInt32, ByVal count As UInt64)

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    Private mockSrc(2048) As UInt32
    Private mockDst(2048) As UInt32

    Private mockBackbuffer(786432) As UInt32 ' 1024 * 768
    Private cursorSavedBg(320) As UInt32

    ''
    ' @brief Dual-mode printer for stdout in QEMU userland and microkernel.
    ''
    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
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

    ' =========================================================================
    ' SUITE 1: fast_blit32 and Odd-Pixel Boundary Alignment
    ' =========================================================================
    Private Unsafe Sub TestFastBlit32OddBoundaries()
        PrintMsg "[SUITE 1] fast_blit32 & Odd-Pixel Boundary Alignment..."

        Dim i As UInt32 = 0
        While i < 2048
            mockSrc(i) = &HAA000000 Or i
            mockDst(i) = &HDEADBEEF
            i = i + 1
        Wend

        ' 1. Even pixel column: x0 = 0 (64-bit aligned: (0 * 4) % 8 == 0)
        fast_blit32 @mockDst(0), @mockSrc(0), 100
        Dim evenOk As Boolean = True
        Dim j As UInt32 = 0
        While j < 100
            If mockDst(j) <> mockSrc(j) Then evenOk = False
            j = j + 1
        Wend
        AssertTrue(evenOk And (mockDst(100) = &HDEADBEEF), "fast_blit32 even x0=0 transfer clean")

        ' 2. Odd pixel column: x0 = 1 (32-bit aligned, NOT 64-bit: (1 * 4) % 8 == 4)
        i = 0
        While i < 2048
            mockDst(i) = &HDEADBEEF
            i = i + 1
        Wend
        Dim dstAddr1 As UInt64 = CType(UInt64, @mockDst(1))
        AssertTrue(((dstAddr1 And 7) = 4), "x0=1 memory address is strictly (addr % 8 == 4)")

        fast_blit32 @mockDst(1), @mockSrc(1), 15
        Dim oddOk As Boolean = True
        j = 1
        While j <= 15
            If mockDst(j) <> mockSrc(j) Then oddOk = False
            j = j + 1
        Wend
        AssertTrue(oddOk And (mockDst(0) = &HDEADBEEF) And (mockDst(16) = &HDEADBEEF), "fast_blit32 odd x0=1 (addr%8==4) exact 15 DWORD transfer")

        ' 3. Odd pixel column: x0 = 137 (addr % 8 == 4), count = 1
        i = 0
        While i < 2048
            mockDst(i) = &HDEADBEEF
            i = i + 1
        Wend
        fast_blit32 @mockDst(137), @mockSrc(137), 1
        AssertTrue((mockDst(137) = mockSrc(137)) And (mockDst(136) = &HDEADBEEF) And (mockDst(138) = &HDEADBEEF), "fast_blit32 single DWORD odd-column x0=137 transfer")

        ' 4. Odd offset x0 = 3 + odd count = 7
        i = 0
        While i < 2048
            mockDst(i) = &HDEADBEEF
            i = i + 1
        Wend
        fast_blit32 @mockDst(3), @mockSrc(3), 7
        Dim oddCountOk As Boolean = True
        j = 3
        While j < 10
            If mockDst(j) <> mockSrc(j) Then oddCountOk = False
            j = j + 1
        Wend
        AssertTrue(oddCountOk And (mockDst(2) = &HDEADBEEF) And (mockDst(10) = &HDEADBEEF), "fast_blit32 odd offset x0=3 + odd count=7 preserves exact bounds")

        ' 5. Full scanline burst transfer: x0 = 5, count = 1019
        i = 0
        While i < 2048
            mockDst(i) = &HDEADBEEF
            i = i + 1
        Wend
        fast_blit32 @mockDst(5), @mockSrc(5), 1019
        Dim burstOk As Boolean = True
        j = 5
        While j < 1024
            If mockDst(j) <> mockSrc(j) Then burstOk = False
            j = j + 1
        Wend
        AssertTrue(burstOk And (mockDst(4) = &HDEADBEEF) And (mockDst(1024) = &HDEADBEEF), "fast_blit32 large odd burst (count=1019) exact boundary check")
    End Sub

    ' =========================================================================
    ' SUITE 2: Compositor Bounding Box Union Math (Signed Int32)
    ' =========================================================================
    Private Unsafe Sub TestBoundingBoxUnionMath()
        PrintMsg "[SUITE 2] Compositor Bounding Box Union Math (Signed Int32)..."

        Dim screenW As Int32 = 1024
        Dim screenH As Int32 = 768

        Dim dirtyX0 As Int32 = screenW
        Dim dirtyY0 As Int32 = screenH
        Dim dirtyX1 As Int32 = 0
        Dim dirtyY1 As Int32 = 0

        ' Moving window from (2, 10) to (20, 15), W=200, H=150
        Dim oldX As Int32 = 2
        Dim oldY As Int32 = 10
        Dim oldW As Int32 = 200
        Dim oldH As Int32 = 150

        Dim newX As Int32 = 20
        Dim newY As Int32 = 15
        Dim newW As Int32 = 200
        Dim newH As Int32 = 150

        Dim r0X0 As Int32 = oldX - 4 ' 2 - 4 = -2 (Signed Negative!)
        Dim r0Y0 As Int32 = oldY - 4 ' 6
        Dim r0X1 As Int32 = oldX + oldW + 12 ' 214
        Dim r0Y1 As Int32 = oldY + oldH + 12 ' 172

        Dim r1X0 As Int32 = newX - 4 ' 16
        Dim r1Y0 As Int32 = newY - 4 ' 11
        Dim r1X1 As Int32 = newX + newW + 12 ' 232
        Dim r1Y1 As Int32 = newY + newH + 12 ' 177

        If r0X0 < dirtyX0 Then dirtyX0 = r0X0
        If r0Y0 < dirtyY0 Then dirtyY0 = r0Y0
        If r0X1 > dirtyX1 Then dirtyX1 = r0X1
        If r0Y1 > dirtyY1 Then dirtyY1 = r0Y1

        If r1X0 < dirtyX0 Then dirtyX0 = r1X0
        If r1Y0 < dirtyY0 Then dirtyY0 = r1Y0
        If r1X1 > dirtyX1 Then dirtyX1 = r1X1
        If r1Y1 > dirtyY1 Then dirtyY1 = r1Y1

        AssertTrue(dirtyX0 = -2, "Bounding box accumulated negative signed Int32 dirtyX0=-2")
        AssertTrue(dirtyX1 = 232, "Bounding box accumulated dirtyX1=232")

        ' Bounds clamping
        If dirtyX0 < 0 Then dirtyX0 = 0
        If dirtyY0 < 0 Then dirtyY0 = 0
        If dirtyX1 > screenW Then dirtyX1 = screenW
        If dirtyY1 > screenH Then dirtyY1 = screenH

        AssertTrue(dirtyX0 = 0, "Negative dirtyX0 successfully clamped to 0 via signed comparison")
        AssertTrue(dirtyX1 = 232, "dirtyX1 intact after screen clipping")

        Dim dirtyW As Int32 = dirtyX1 - dirtyX0
        Dim dirtyH As Int32 = dirtyY1 - dirtyY0
        AssertTrue((dirtyW = 232) And (dirtyH = 171), "dirtyW=232 and dirtyH=171 cleanly computed without underflow")

        ' Overflow right edge
        Dim rightX As Int32 = 950
        Dim rightW As Int32 = 200
        Dim rx1 As Int32 = rightX + rightW + 12 ' 1162 (> 1024)
        If rx1 > screenW Then rx1 = screenW
        AssertTrue(rx1 = 1024, "Right boundary overflow clamped to screenW=1024")
    End Sub

    ' =========================================================================
    ' SUITE 3: Window Manager Drag & Resize Coordinate Offsets (Signed Int32)
    ' =========================================================================
    Private Unsafe Sub TestWindowDragAndResize()
        PrintMsg "[SUITE 3] Window Drag & Resize Coordinate Offsets (Signed Int32)..."

        Dim screenW As Int32 = 1024
        Dim screenH As Int32 = 768

        Dim winX As Int32 = 100
        Dim winY As Int32 = 100
        Dim winW As Int32 = 300
        Dim winH As Int32 = 200

        ' 1. Titlebar click at mouse (150, 110)
        Dim mouseX As Int32 = 150
        Dim mouseY As Int32 = 110
        Dim dragOffsetX As Int32 = mouseX - winX ' 50
        Dim dragOffsetY As Int32 = mouseY - winY ' 10
        AssertTrue((dragOffsetX = 50) And (dragOffsetY = 10), "Drag offset calculation correct")

        ' 2. Drag to extreme left (mouse pushed off-screen to -500)
        Dim draggedMx As Int32 = -500
        Dim newX As Int32 = draggedMx - dragOffsetX ' -550
        If newX < -(winW - 48) Then newX = -(winW - 48) ' -(300 - 48) = -252
        AssertTrue(newX = -252, "Extreme negative mouseX clamp preserves 48px window visibility")

        ' 3. Resizing: Click bottom-right gripper at (395, 295) for window at (100, 100, 300, 200)
        Dim clickMx As Int32 = 395
        Dim clickMy As Int32 = 295
        Dim resizeOffsetX As Int32 = (winX + winW) - clickMx ' (100 + 300) - 395 = 5
        Dim resizeOffsetY As Int32 = (winY + winH) - clickMy ' (100 + 200) - 295 = 5
        AssertTrue((resizeOffsetX = 5) And (resizeOffsetY = 5), "Resize absolute corner offset correct")

        ' Resizing: Move mouse past minimum dimensions (mouse to 120, 120)
        Dim curMx As Int32 = 120
        Dim curMy As Int32 = 120
        Dim targetW As Int32 = (curMx + resizeOffsetX) - winX ' (120 + 5) - 100 = 25
        Dim targetH As Int32 = (curMy + resizeOffsetY) - winY ' (120 + 5) - 100 = 25
        If targetW < 160 Then targetW = 160
        If targetH < 100 Then targetH = 100
        AssertTrue((targetW = 160) And (targetH = 100), "Resize clamped to minimum dimensions (160x100)")

        ' Resizing: Move mouse to negative screen space (curMx = -100)
        curMx = -100
        targetW = (curMx + resizeOffsetX) - winX ' (-100 + 5) - 100 = -195 (NEGATIVE!)
        AssertTrue(targetW = -195, "targetW is negative signed Int32 (-195), NOT unsigned 4GB!")
        If targetW < 160 Then targetW = 160
        AssertTrue(targetW = 160, "Negative targetW properly clamped to 160 via signed compare")
    End Sub

    ' =========================================================================
    ' SUITE 4: Cursor Background Save and Restore at Screen Boundaries
    ' =========================================================================
    Private Unsafe Sub TestCursorBoundarySafety()
        PrintMsg "[SUITE 4] Cursor Background Save & Restore at Screen Boundaries..."

        Dim width As Int32 = 1024
        Dim height As Int32 = 768
        Dim pitchPix As UInt32 = 1024

        Dim y As Int32 = 0
        While y < height
            Dim x As Int32 = 0
            While x < width
                mockBackbuffer((y * width) + x) = CType(UInt32, (y * width) + x)
                x = x + 1
            Wend
            y = y + 1
        Wend

        Dim curX As Int32 = 0
        Dim curY As Int32 = 0
        Dim readCount As UInt32 = 0
        Dim cy As Int32 = 0
        Dim py As Int32 = 0
        Dim cx As Int32 = 0
        Dim px As Int32 = 0
        Dim rowPtr As Pointer To UInt32 = 0

        ' Test 1: Cursor at (0, 0) - Top-Left Corner
        curX = 0
        curY = 0
        readCount = 0
        cy = 0
        While cy < 18
            py = curY + cy
            If py >= 0 And py < height Then
                rowPtr = @mockBackbuffer(0) + (CType(UInt32, py) * pitchPix)
                cx = 0
                While cx < 16
                    px = curX + cx
                    If px >= 0 And px < width Then
                        cursorSavedBg((cy * 16) + cx) = rowPtr(px)
                        readCount = readCount + 1
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
        AssertTrue(readCount = (16 * 18), "Cursor at (0, 0) saves all 288 pixels")

        ' Test 2: Cursor at (width - 1, height - 1) - Bottom-Right Corner (1023, 767)
        curX = width - 1
        curY = height - 1
        readCount = 0
        cy = 0
        While cy < 18
            py = curY + cy
            If py >= 0 And py < height Then
                rowPtr = @mockBackbuffer(0) + (CType(UInt32, py) * pitchPix)
                cx = 0
                While cx < 16
                    px = curX + cx
                    If px >= 0 And px < width Then
                        cursorSavedBg((cy * 16) + cx) = rowPtr(px)
                        readCount = readCount + 1
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
        AssertTrue(readCount = 1, "Cursor at (1023, 767) saves exactly 1 pixel with 0 buffer overrun")
        AssertTrue(cursorSavedBg(0) = mockBackbuffer(((height - 1) * width) + (width - 1)), "Pixel value matches bottom-right corner")

        ' Test 3: Cursor partially off-screen at negative position (-5, -5)
        curX = -5
        curY = -5
        readCount = 0
        cy = 0
        While cy < 18
            py = curY + cy
            If py >= 0 And py < height Then
                rowPtr = @mockBackbuffer(0) + (CType(UInt32, py) * pitchPix)
                cx = 0
                While cx < 16
                    px = curX + cx
                    If px >= 0 And px < width Then
                        cursorSavedBg((cy * 16) + cx) = rowPtr(px)
                        readCount = readCount + 1
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
        AssertTrue(readCount = ((16 - 5) * (18 - 5)), "Cursor at (-5, -5) clips negative coords, saving exact visible region (143 px)")

        ' Test 4: Cursor completely off-screen (-20, -20)
        curX = -20
        curY = -20
        readCount = 0
        cy = 0
        While cy < 18
            py = curY + cy
            If py >= 0 And py < height Then
                rowPtr = @mockBackbuffer(0) + (CType(UInt32, py) * pitchPix)
                cx = 0
                While cx < 16
                    px = curX + cx
                    If px >= 0 And px < width Then
                        cursorSavedBg((cy * 16) + cx) = rowPtr(px)
                        readCount = readCount + 1
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
        AssertTrue(readCount = 0, "Cursor completely off-screen (-20, -20) reads 0 pixels")

        ' Test 5: Cursor restore symmetry
        y = 0
        While y < height
            Dim rx As Int32 = 0
            While rx < width
                mockBackbuffer((y * width) + rx) = 0
                rx = rx + 1
            Wend
            y = y + 1
        Wend

        Dim writeCount As UInt32 = 0
        curX = width - 1
        curY = height - 1
        cy = 0
        While cy < 18
            py = curY + cy
            If py >= 0 And py < height Then
                rowPtr = @mockBackbuffer(0) + (CType(UInt32, py) * pitchPix)
                cx = 0
                While cx < 16
                    px = curX + cx
                    If px >= 0 And px < width Then
                        rowPtr(px) = cursorSavedBg((cy * 16) + cx)
                        writeCount = writeCount + 1
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
        AssertTrue(writeCount = 1, "Cursor restore at (1023, 767) writes exactly 1 pixel")
        AssertTrue(mockBackbuffer(((height - 1) * width) + (width - 1)) = CType(UInt32, ((height - 1) * width) + (width - 1)), "Restored pixel matches original background value identically")
    End Sub

    ' =========================================================================
    ' Entry Point
    ' =========================================================================
    Public Unsafe Function Main() As UInt64
        PrintMsg "========================================================"
        PrintMsg "[CHALLENGER-M2] Empirical Compositor, WM & Display Stress"
        PrintMsg "========================================================"

        TestFastBlit32OddBoundaries
        TestBoundingBoxUnionMath
        TestWindowDragAndResize
        TestCursorBoundarySafety

        PrintMsg "--------------------------------------------------------"
        Dim rBuf(16) As Byte
        Dim rIdx As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @rBuf(0), rIdx
        rBuf(rIdx) = 0
        DualPrint "[CHALLENGER-M2] Total Tests Run   : "
        PrintMsg @rBuf(0)

        Dim pBuf(16) As Byte
        Dim pIdx As UInt32 = 0
        AppendUInt CType(UInt64, testsPassed), @pBuf(0), pIdx
        pBuf(pIdx) = 0
        DualPrint "[CHALLENGER-M2] Total Tests Passed: "
        PrintMsg @pBuf(0)

        Dim fBuf(16) As Byte
        Dim fIdx As UInt32 = 0
        AppendUInt CType(UInt64, testsFailed), @fBuf(0), fIdx
        fBuf(fIdx) = 0
        DualPrint "[CHALLENGER-M2] Total Tests Failed: "
        PrintMsg @fBuf(0)
        PrintMsg "--------------------------------------------------------"

        If testsFailed = 0 Then
            PrintMsg "[CHALLENGER-M2] ALL EMPIRICAL CHALLENGE TESTS PASSED!"
            PrintMsg "========================================================"
            Main = 0
        Else
            PrintMsg "[CHALLENGER-M2] SOME TESTS FAILED!"
            PrintMsg "========================================================"
            Main = 1
        End If
    End Function

End Module
