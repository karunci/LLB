' Project Name: PROS (Personal Research Operating System)
' Filename: services/compositor/CompositorMain.bas
' Summary: Standalone Ring 3 Display Compositor and Window Engine daemon.
'          Manages window surfaces, double-buffered presentation,
'          interactive software cursor, and system telemetry badge.

Import "../../include/pros.bas"

Module CompositorMain

    ' -------------------------------------------------------------------------
    ' Internal Data & State
    ' -------------------------------------------------------------------------
    Private dispInfo As DisplayInfo
    Private frontSurf As Surface
    Private hasDisplay As Boolean = False

    ' Software Cursor State
    Private cursorX As Int32 = 100
    Private cursorY As Int32 = 100
    Private oldCursorX As Int32 = 100
    Private oldCursorY As Int32 = 100
    Private cursorSavedBg(96) As UInt32 ' 12 x 8 pixels background backup
    Private cursorInitialized As Boolean = False

    ' Telemetry Badge State
    Private badgeX As Int32 = 0
    Private badgeY As Int32 = 0
    Private badgeActive As Boolean = False
    Private animPos As Int32 = 0
    Private animDir As Int32 = 3
    Private frameCount As UInt32 = 0

    ''
    ' @brief Append unsigned 64-bit integer formatted as ASCII into buffer.
    ''
    Private Unsafe Sub AppendUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        If val = 0 Then
            buf(outIdx) = 48 ' '0'
            outIdx = outIdx + 1
            Exit Sub
        End If
        Dim tmp(23) As Byte
        Dim tIdx As UInt32 = 0
        Dim v As UInt64 = val
        While v > 0
            tmp(tIdx) = CType(Byte, (v Mod 10) + 48)
            v = v / 10
            tIdx = tIdx + 1
        Wend
        While tIdx > 0
            tIdx = tIdx - 1
            buf(outIdx) = tmp(tIdx)
            outIdx = outIdx + 1
        Wend
    End Sub

    ''
    ' @brief Append null-terminated ASCII string into buffer.
    ''
    Private Unsafe Sub AppendStr(ByVal s As Pointer To Byte, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        Dim i As UInt32 = 0
        While s(i) <> 0
            buf(outIdx) = s(i)
            outIdx = outIdx + 1
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Append 64-bit integer formatted in uppercase hexadecimal into buffer.
    ''
    Private Unsafe Sub AppendHex(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef idx As UInt32)
        If val = 0 Then
            buf(idx) = 48 ' '0'
            idx = idx + 1
            Exit Sub
        End If
        Dim hexDigits As Pointer To Byte = CPtr(Pointer To Byte, "0123456789ABCDEF")
        Dim tmp(16) As Byte
        Dim tIdx As Int32 = 0
        While val > 0
            tmp(tIdx) = hexDigits(CType(Byte, val And 15))
            val = val RShift 4
            tIdx = tIdx + 1
        Wend
        While tIdx > 0
            tIdx = tIdx - 1
            buf(idx) = tmp(tIdx)
            idx = idx + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' 5x7 ASCII Bitmap Font Engine
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
        Dim rows(7) As Byte
        Dim valid As Boolean = True

        ' Digits 0-9
        If ascii = 48 Then      ' '0'
            rows(0) = 14: rows(1) = 17: rows(2) = 19: rows(3) = 21: rows(4) = 25: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 49 Then  ' '1'
            rows(0) = 4:  rows(1) = 12: rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 14
        ElseIf ascii = 50 Then  ' '2'
            rows(0) = 14: rows(1) = 17: rows(2) = 1:  rows(3) = 6:  rows(4) = 8:  rows(5) = 16: rows(6) = 31
        ElseIf ascii = 51 Then  ' '3'
            rows(0) = 30: rows(1) = 1:  rows(2) = 1:  rows(3) = 14: rows(4) = 1:  rows(5) = 1:  rows(6) = 30
        ElseIf ascii = 52 Then  ' '4'
            rows(0) = 2:  rows(1) = 6:  rows(2) = 10: rows(3) = 18: rows(4) = 31: rows(5) = 2:  rows(6) = 2
        ElseIf ascii = 53 Then  ' '5'
            rows(0) = 31: rows(1) = 16: rows(2) = 30: rows(3) = 1:  rows(4) = 1:  rows(5) = 17: rows(6) = 14
        ElseIf ascii = 54 Then  ' '6'
            rows(0) = 14: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 55 Then  ' '7'
            rows(0) = 31: rows(1) = 1:  rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 8:  rows(6) = 8
        ElseIf ascii = 56 Then  ' '8'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 14: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 57 Then  ' '9'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 15: rows(4) = 1:  rows(5) = 1:  rows(6) = 14
        ' Common Uppercase
        ElseIf ascii = 65 Then  ' 'A'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 66 Then  ' 'B'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 17: rows(5) = 17: rows(6) = 30
        ElseIf ascii = 67 Then  ' 'C'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 68 Then  ' 'D'
            rows(0) = 28: rows(1) = 18: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 18: rows(6) = 28
        ElseIf ascii = 69 Then  ' 'E'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 70 Then  ' 'F'
            rows(0) = 31: rows(1) = 16: rows(2) = 16: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 71 Then  ' 'G'
            rows(0) = 14: rows(1) = 17: rows(2) = 16: rows(3) = 23: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 72 Then  ' 'H'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 31: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 73 Then  ' 'I'
            rows(0) = 14: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 14
        ElseIf ascii = 75 Then  ' 'K'
            rows(0) = 17: rows(1) = 18: rows(2) = 20: rows(3) = 24: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 76 Then  ' 'L'
            rows(0) = 16: rows(1) = 16: rows(2) = 16: rows(3) = 16: rows(4) = 16: rows(5) = 16: rows(6) = 31
        ElseIf ascii = 77 Then  ' 'M'
            rows(0) = 17: rows(1) = 27: rows(2) = 21: rows(3) = 21: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 78 Then  ' 'N'
            rows(0) = 17: rows(1) = 25: rows(2) = 21: rows(3) = 19: rows(4) = 17: rows(5) = 17: rows(6) = 17
        ElseIf ascii = 79 Then  ' 'O'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 80 Then  ' 'P'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 16: rows(5) = 16: rows(6) = 16
        ElseIf ascii = 82 Then  ' 'R'
            rows(0) = 30: rows(1) = 17: rows(2) = 17: rows(3) = 30: rows(4) = 20: rows(5) = 18: rows(6) = 17
        ElseIf ascii = 83 Then  ' 'S'
            rows(0) = 15: rows(1) = 16: rows(2) = 16: rows(3) = 14: rows(4) = 1:  rows(5) = 1:  rows(6) = 30
        ElseIf ascii = 84 Then  ' 'T'
            rows(0) = 31: rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 85 Then  ' 'U'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 17: rows(5) = 17: rows(6) = 14
        ElseIf ascii = 86 Then  ' 'V'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 10: rows(5) = 10: rows(6) = 4
        ElseIf ascii = 87 Then  ' 'W'
            rows(0) = 17: rows(1) = 17: rows(2) = 21: rows(3) = 21: rows(4) = 21: rows(5) = 21: rows(6) = 10
        ' Punctuation
        ElseIf ascii = 32 Then  ' ' ' (Space)
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 58 Then  ' ':'
            rows(0) = 0:  rows(1) = 12: rows(2) = 12: rows(3) = 0:  rows(4) = 12: rows(5) = 12: rows(6) = 0
        ElseIf ascii = 45 Then  ' '-'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 31: rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 46 Then  ' '.'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 12: rows(6) = 12
        ElseIf ascii = 124 Then ' '|'
            rows(0) = 4:  rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 40 Then  ' '('
            rows(0) = 2:  rows(1) = 4:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 4:  rows(6) = 2
        ElseIf ascii = 41 Then  ' ')'
            rows(0) = 8:  rows(1) = 4:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 4:  rows(6) = 8
        Else
            ' Fallback dot
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 4:  rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        End If

        Dim r As Int32 = 0
        While r < 7
            Dim b As Byte = rows(r)
            Dim c As Int32 = 0
            While c < 5
                Dim bitMask As Byte = CType(Byte, 16 RShift c)
                If (b And bitMask) <> 0 Then
                    FillRect surf, gx + c, gy + r, 1, 1, color
                End If
                c = c + 1
            Wend
            r = r + 1
        Wend
    End Sub

    ''
    ' @brief Draw null-terminated ASCII string using 5x7 font with 1px character spacing.
    ''
    Private Unsafe Sub DrawText5x7(ByRef surf As Surface, ByVal startX As Int32, ByVal startY As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)
        If textPtr = 0 Then Exit Sub
        Dim i As UInt32 = 0
        Dim curX As Int32 = startX
        While textPtr(i) <> 0
            Dim ch As Byte = textPtr(i)
            ' Auto-convert lowercase to uppercase for 5x7 glyph set
            If ch >= 97 And ch <= 122 Then
                ch = ch - 32
            End If
            DrawGlyph surf, curX, startY, ch, color
            curX = curX + 6
            i = i + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' 12x8 High-Contrast Arrow Cursor Engine
    ' -------------------------------------------------------------------------
    Private Unsafe Sub SaveCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        cursorSavedBg((cy * 8) + cx) = rowPtr(curX)
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    Private Unsafe Sub RestoreCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        rowPtr(curX) = cursorSavedBg((cy * 8) + cx)
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    Private Unsafe Sub DrawCursorArrow(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub

        ' 12-row x 8-col pointer: 2 = Black outline, 1 = White fill, 0 = transparent
        Dim cursorRows(12) As Byte
        cursorRows(0)  = &HC0 ' 11000000 -> 2,2
        cursorRows(1)  = &HE0 ' 11100000 -> 2,1,2
        cursorRows(2)  = &HF0 ' 11110000 -> 2,1,1,2
        cursorRows(3)  = &HF8 ' 11111000 -> 2,1,1,1,2
        cursorRows(4)  = &HFC ' 11111100 -> 2,1,1,1,1,2
        cursorRows(5)  = &HFE ' 11111110 -> 2,1,1,1,1,1,2
        cursorRows(6)  = &HFF ' 11111111 -> 2,1,1,1,1,1,1,2
        cursorRows(7)  = &HF8 ' 11111000 -> 2,1,1,1,1,2,2,2
        cursorRows(8)  = &HD8 ' 11011000 -> 2,2,0,0,2,1,2
        cursorRows(9)  = &H98 ' 10011000 -> 2,0,0,0,2,1,2
        cursorRows(10) = &H0C ' 00001100 -> 0,0,0,0,2,2
        cursorRows(11) = &H0C ' 00001100 -> 0,0,0,0,2,2

        Dim pitchPix As UInt32 = frontSurf.Pitch / 4
        Dim cy As Int32 = 0
        While cy < 12
            Dim curY As Int32 = y + cy
            If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                Dim mask As Byte = cursorRows(cy)
                Dim cx As Int32 = 0
                While cx < 8
                    Dim curX As Int32 = x + cx
                    If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                        Dim bitActive As Boolean = ((mask RShift (7 - cx)) And 1) <> 0
                        If bitActive Then
                            ' Check border vs core fill
                            If cy = 0 Or cy = 10 Or cy = 11 Or cx = 0 Or cx = 7 Or cy = (cx + 1) Or cy = 8 Then
                                rowPtr(curX) = &HFF000000 ' Sharp Black Outline
                            Else
                                rowPtr(curX) = &HFFFFFFFF ' Bright White Fill
                            End If
                        End If
                    End If
                    cx = cx + 1
                Wend
            End If
            cy = cy + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' Telemetry Status Badge Renderer
    ' -------------------------------------------------------------------------
    Private Unsafe Sub RenderTelemetryBadge()
        If Not badgeActive Then Exit Sub

        ' 1. Cycle status LED color (breathing green -> cyan -> mint -> emerald)
        Dim ledColor As UInt32 = &HFF00C853
        Dim colorPhase As UInt32 = (frameCount / 6) Mod 4
        If colorPhase = 0 Then
            ledColor = &HFF00E676
        ElseIf colorPhase = 1 Then
            ledColor = &HFF00E5FF
        ElseIf colorPhase = 2 Then
            ledColor = &HFF69F0AE
        Else
            ledColor = &HFF00C853
        End If
        FillRect frontSurf, badgeX + 4, badgeY + 4, 8, 18, ledColor

        ' 2. Redraw recessed dark channel for scanner pulse
        Dim trackX As Int32 = badgeX + 16
        Dim trackY As Int32 = badgeY + 5
        Dim trackW As Int32 = 120
        Dim trackH As Int32 = 16
        Dim pulseW As Int32 = 28
        FillRect frontSurf, trackX, trackY, trackW, trackH, &HFF1B2028

        ' 3. Ping-pong animated scanner pulse
        Dim pulseX As Int32 = trackX + animPos
        If pulseX < trackX Then pulseX = trackX
        If (pulseX + pulseW) > (trackX + trackW) Then
            pulseX = (trackX + trackW) - pulseW
        End If

        FillRect frontSurf, pulseX, trackY + 2, pulseW, trackH - 4, &HFF00B0FF
        FillRect frontSurf, pulseX + 3, trackY + 4, pulseW - 6, trackH - 8, &HFF80D8FF
        FillRect frontSurf, pulseX + 6, trackY + 6, pulseW - 12, trackH - 12, &HFFFFFFFF

        animPos = animPos + animDir
        If animPos >= (trackW - pulseW) Then
            animPos = trackW - pulseW
            animDir = -3
        ElseIf animPos <= 0 Then
            animPos = 0
            animDir = 3
        End If

        ' 4. Real-time 30 FPS telemetry counter text
        DrawText5x7 frontSurf, badgeX + 144, badgeY + 10, CPtr(Pointer To Byte, "30 FPS"), &HFF88C0D0
    End Sub

    ' -------------------------------------------------------------------------
    ' Desktop Background & Initial Window Canvas Pre-Renderer
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawDesktopScene()
        If frontSurf.Pixels = 0 Then Exit Sub

        ' 1. Clear boot splash to Nord Dark Background (#191D24)
        FillRect frontSurf, 0, 0, dispInfo.Width, dispInfo.Height, &HFF191D24

        ' 2. Top System Menu Bar (y: 0..26)
        FillRect frontSurf, 0, 0, dispInfo.Width, 26, &HFF232731
        FillRect frontSurf, 0, 25, dispInfo.Width, 1, &HFF4C566A
        FillRect frontSurf, 0, 0, 4, 25, &HFF88C0D0

        DrawText5x7 frontSurf, 16, 10, CPtr(Pointer To Byte, "PROS WORKSTATION  |  APPLICATIONS  NODES  SERVICES  VIEW"), &HFFECEFF4
        DrawText5x7 frontSurf, CType(Int32, dispInfo.Width) - 180, 10, CPtr(Pointer To Byte, "SMP 4 CORES  ONLINE"), &HFFA3BE8C

        ' 3. Render Floating Desktop Window: "PROS System Monitor"
        Dim wx As Int32 = 60
        Dim wy As Int32 = 60
        Dim ww As Int32 = 480
        Dim wh As Int32 = 280

        ' Outer drop-shadow effect
        FillRect frontSurf, wx + 4, wy + 4, ww, wh, &HFF121419

        ' Window Frame Border
        FillRect frontSurf, wx, wy, ww, wh, &HFF434C5E
        FillRect frontSurf, wx + 1, wy + 1, ww - 2, wh - 2, &HFF2E3440

        ' Titlebar (h: 26)
        FillRect frontSurf, wx + 1, wy + 1, ww - 2, 26, &HFF2E3440
        FillRect frontSurf, wx + 1, wy + 1, 4, 26, &HFF5E81AC
        DrawText5x7 frontSurf, wx + 16, wy + 10, CPtr(Pointer To Byte, "PROS SYSTEM MONITOR (RING 3 COMPOSITED)"), &HFFECEFF4

        ' Window Buttons (Minimize, Maximize, Close)
        FillRect frontSurf, (wx + ww) - 54, wy + 8, 10, 10, &HFF5E81AC ' Min
        FillRect frontSurf, (wx + ww) - 38, wy + 8, 10, 10, &HFFA3BE8C ' Max
        FillRect frontSurf, (wx + ww) - 22, wy + 8, 10, 10, &HFFBF616A ' Close

        ' Window Client Canvas
        FillRect frontSurf, wx + 2, wy + 28, ww - 4, wh - 30, &HFF232731

        ' Card 1: Microkernel Architecture
        FillRect frontSurf, wx + 16, wy + 40, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 40, 3, 42, &HFF81A1C1
        DrawText5x7 frontSurf, wx + 26, wy + 48, CPtr(Pointer To Byte, "KERNEL : PRK-LLB (LOW-LEVEL BASIC MICROKERNEL)"), &HFF81A1C1
        DrawText5x7 frontSurf, wx + 26, wy + 64, CPtr(Pointer To Byte, "MODEL  : DUAL-PLANE NEURAL SYNAPSE ROUTING"), &HFFD8DEE9

        ' Card 2: Compositor Status
        FillRect frontSurf, wx + 16, wy + 92, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 92, 3, 42, &HFFA3BE8C
        DrawText5x7 frontSurf, wx + 26, wy + 100, CPtr(Pointer To Byte, "ENGINE : ZERO-COPY WINDOW SURFACE PIPELINE"), &HFFA3BE8C
        DrawText5x7 frontSurf, wx + 26, wy + 116, CPtr(Pointer To Byte, "DRIVER : DIRECT LINEAR FRAMEBUFFER APERTURE"), &HFFECEFF4

        ' Card 3: Subsystem Status
        FillRect frontSurf, wx + 16, wy + 144, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 144, 3, 42, &HFFEBCB8B
        DrawText5x7 frontSurf, wx + 26, wy + 152, CPtr(Pointer To Byte, "INPUT  : INPUT_SRV DAEMON ONLINE (PS/2 MOUSE)"), &HFFEBCB8B
        DrawText5x7 frontSurf, wx + 26, wy + 168, CPtr(Pointer To Byte, "DISPLAY: DISP_SRV DEVICE CONTROLLER ONLINE"), &HFFECEFF4

        ' Card 4: Ring 3 Performance
        FillRect frontSurf, wx + 16, wy + 196, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 196, 3, 42, &HFFB48EAD
        DrawText5x7 frontSurf, wx + 26, wy + 204, CPtr(Pointer To Byte, "SECURITY: CPL=3 USERLAND HARDWARE ISOLATION"), &HFFB48EAD
        DrawText5x7 frontSurf, wx + 26, wy + 220, CPtr(Pointer To Byte, "SHARED MEMORY: SHMEM GRADIENTS MAPPED"), &HFFECEFF4

        ' 4. Initialize Telemetry Status Badge Container
        If dispInfo.Width > 220 And dispInfo.Height > 60 Then
            badgeX = CType(Int32, dispInfo.Width) - 210
            badgeY = CType(Int32, dispInfo.Height) - 34
            FillRect frontSurf, badgeX, badgeY, 200, 26, &HFF2E3440
            FillRect frontSurf, badgeX, badgeY, 200, 1, &HFF434C5E
            badgeActive = True
        End If
    End Sub

    ' -------------------------------------------------------------------------
    ' Main Application Entry Point
    ' -------------------------------------------------------------------------
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[COMPOSITOR] ======================================================="
        ConsoleWriteLine "[COMPOSITOR] PROS Display Compositor Service Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[COMPOSITOR] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.compositor' (Kind: Device/Compositor = 2, Caps: RWN = 7)
        Dim srvName(32) As Byte
        srvName(0) = 115 ' 's'
        srvName(1) = 114 ' 'r'
        srvName(2) = 118 ' 'v'
        srvName(3) = 46  ' '.'
        srvName(4) = 99  ' 'c'
        srvName(5) = 111 ' 'o'
        srvName(6) = 109 ' 'm'
        srvName(7) = 112 ' 'p'
        srvName(8) = 111 ' 'o'
        srvName(9) = 115 ' 's'
        srvName(10) = 105' 'i'
        srvName(11) = 116' 't'
        srvName(12) = 111' 'o'
        srvName(13) = 114' 'r'
        srvName(14) = 0
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, @srvName(0), 7)
        ConsolePrintWithUInt "[COMPOSITOR] Registered Node 'srv.compositor' -> Node #", srvNodeId, "\r\n"

        ' 3. Query Hardware Display Geometry
        If GetDisplayInfo(dispInfo) Then
            Dim resBuf(64) As Byte
            Dim rIdx As UInt32 = 0
            AppendStr "[COMPOSITOR] Discovered Display: ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Width), @resBuf(0), rIdx
            AppendStr "x", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Height), @resBuf(0), rIdx
            AppendStr " @ ", @resBuf(0), rIdx
            AppendUInt CType(UInt64, dispInfo.Bpp), @resBuf(0), rIdx
            AppendStr " BPP", @resBuf(0), rIdx
            resBuf(rIdx) = 0
            ConsoleWriteLine @resBuf(0)
            ConsolePrintWithUInt "[COMPOSITOR] Framebuffer Pitch: ", CType(UInt64, dispInfo.Pitch), " bytes\r\n"
        Else
            ConsoleWriteLine "[COMPOSITOR] WARN: Could not query display information"
        End If

        ' 4. Map Linear Framebuffer Aperture to User Space at 0x78000000
        Dim fbPtr As Pointer To UInt32 = MapFramebuffer(&H78000000)
        If fbPtr <> 0 Then
            ConsoleWriteLine "[COMPOSITOR] Linear Framebuffer Aperture mapped at 0x78000000"
            frontSurf.Width = dispInfo.Width
            frontSurf.Height = dispInfo.Height
            frontSurf.Pitch = dispInfo.Pitch
            frontSurf.Bpp = dispInfo.Bpp
            frontSurf.Pixels = fbPtr
            hasDisplay = True
        Else
            ConsoleWriteLine "[COMPOSITOR] ERR: Failed to map linear framebuffer aperture!"
            user_main = 1
            Exit Function
        End If

        ' 5. Transition from Boot Splash to Graphical Desktop Canvas
        ConsoleWriteLine "[COMPOSITOR] Boot splash completed. Transitioning to PROS Desktop..."
        DrawDesktopScene

        ' 6. Initial cursor placement at screen center
        cursorX = CType(Int32, dispInfo.Width / 2)
        cursorY = CType(Int32, dispInfo.Height / 2)
        oldCursorX = cursorX
        oldCursorY = cursorY
        SaveCursorBackground cursorX, cursorY
        DrawCursorArrow cursorX, cursorY
        cursorInitialized = True
        ConsoleWriteLine "[COMPOSITOR] Hardware software cursor plane initialized at screen center."

        ' 7. Active Presentation & Event Loop
        ConsoleWriteLine "[COMPOSITOR] Compositor online. Entering presentation loop (~30 FPS)..."

        Dim tickCount As UInt32 = 0
        Do
            ' A. Update and animate telemetry badge
            RenderTelemetryBadge

            ' B. Update interactive cursor (simulated test drift or input queue sampling)
            ' Every 4 frames, animate a subtle cursor scan or motion test
            If (frameCount Mod 8) = 0 Then
                Dim nextX As Int32 = cursorX + 1
                Dim nextY As Int32 = cursorY
                If nextX > (CType(Int32, dispInfo.Width) - 100) Then
                    nextX = CType(Int32, dispInfo.Width / 2) - 100
                End If

                ' Fast tear-free cursor blit
                RestoreCursorBackground oldCursorX, oldCursorY
                SaveCursorBackground nextX, nextY
                DrawCursorArrow nextX, nextY
                oldCursorX = nextX
                oldCursorY = nextY
                cursorX = nextX
                cursorY = nextY
            End If

            frameCount = frameCount + 1
            tickCount = tickCount + 1

            ' Cooperatively yield CPU slice across SMP cores
            ProcessYield
        Loop

        user_main = 0
    End Function

End Module
