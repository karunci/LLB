' Project Name: PROS (Personal Research Operating System)
' Filename: services/compositor/CompositorMain.bas
' Summary: Standalone Ring 3 Display Compositor and Window Engine daemon.
'          Features pixel-perfect PRK cursor sprite (16x18), responsive zero-lag
'          mouse hardware tracking, real-time dynamic FPS measurement,
'          smooth half-speed telemetry pulse, and restored minimalist Nord window.

Import "../../include/pros.bas"

Module CompositorMain

    ' -------------------------------------------------------------------------
    ' Internal Data & State
    ' -------------------------------------------------------------------------
    Private dispInfo As DisplayInfo
    Private frontSurf As Surface
    Private hasDisplay As Boolean = False

    ' PRK 16x18 Arrow Cursor State
    Private Const CURSOR_W As Int32 = 16
    Private Const CURSOR_H As Int32 = 18

    Private cursorX As Int32 = 512
    Private cursorY As Int32 = 384
    Private oldCursorX As Int32 = 512
    Private oldCursorY As Int32 = 384
    Private cursorSavedBg(320) As UInt32 ' 16 x 18 = 288 pixels background backup
    Private cursorInitialized As Boolean = False

    ' Telemetry Badge State
    Private badgeX As Int32 = 0
    Private badgeY As Int32 = 0
    Private badgeActive As Boolean = False
    Private animPos As Int32 = 0
    Private animDir As Int32 = 2

    ' Real Dynamic FPS Measurement State
    Private frameCount As UInt32 = 0
    Private lastFpsFrame As UInt32 = 0
    Private lastFpsTime As UInt64 = 0
    Private currentFps As UInt32 = 60
    Private nextAnimTime As UInt64 = 0

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

    ' -------------------------------------------------------------------------
    ' 5x7 ASCII Bitmap Font Engine (with full Alphabet including Y and Z)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
        Dim rows(7) As Byte

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
        ' Uppercase Alphabet
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
        ElseIf ascii = 74 Then  ' 'J'
            rows(0) = 7:  rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 18: rows(6) = 12
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
        ElseIf ascii = 81 Then  ' 'Q'
            rows(0) = 14: rows(1) = 17: rows(2) = 17: rows(3) = 17: rows(4) = 21: rows(5) = 18: rows(6) = 13
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
        ElseIf ascii = 88 Then  ' 'X'
            rows(0) = 17: rows(1) = 10: rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 10: rows(6) = 17
        ElseIf ascii = 89 Then  ' 'Y'
            rows(0) = 17: rows(1) = 17: rows(2) = 17: rows(3) = 10: rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 90 Then  ' 'Z'
            rows(0) = 31: rows(1) = 1:  rows(2) = 2:  rows(3) = 4:  rows(4) = 8:  rows(5) = 16: rows(6) = 31
        ' Punctuation & Symbols
        ElseIf ascii = 32 Then  ' ' ' (Space)
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 58 Then  ' ':'
            rows(0) = 0:  rows(1) = 12: rows(2) = 12: rows(3) = 0:  rows(4) = 12: rows(5) = 12: rows(6) = 0
        ElseIf ascii = 45 Then  ' '-'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 31: rows(4) = 0:  rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 46 Then  ' '.'
            rows(0) = 0:  rows(1) = 0:  rows(2) = 0:  rows(3) = 0:  rows(4) = 0:  rows(5) = 12: rows(6) = 12
        ElseIf ascii = 47 Then  ' '/'
            rows(0) = 1:  rows(1) = 2:  rows(2) = 4:  rows(3) = 8:  rows(4) = 16: rows(5) = 0:  rows(6) = 0
        ElseIf ascii = 124 Then ' '|'
            rows(0) = 4:  rows(1) = 4:  rows(2) = 4:  rows(3) = 4:  rows(4) = 4:  rows(5) = 4:  rows(6) = 4
        ElseIf ascii = 40 Then  ' '('
            rows(0) = 2:  rows(1) = 4:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 4:  rows(6) = 2
        ElseIf ascii = 41 Then  ' ')'
            rows(0) = 8:  rows(1) = 4:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 4:  rows(6) = 8
        ElseIf ascii = 91 Then  ' '['
            rows(0) = 14: rows(1) = 8:  rows(2) = 8:  rows(3) = 8:  rows(4) = 8:  rows(5) = 8:  rows(6) = 14
        ElseIf ascii = 93 Then  ' ']'
            rows(0) = 14: rows(1) = 2:  rows(2) = 2:  rows(3) = 2:  rows(4) = 2:  rows(5) = 2:  rows(6) = 14
        Else
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

    Private Unsafe Sub DrawText5x7(ByRef surf As Surface, ByVal startX As Int32, ByVal startY As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)
        If textPtr = 0 Then Exit Sub
        Dim i As UInt32 = 0
        Dim curX As Int32 = startX
        While textPtr(i) <> 0
            Dim ch As Byte = textPtr(i)
            If ch >= 97 And ch <= 122 Then
                ch = ch - 32
            End If
            DrawGlyph surf, curX, startY, ch, color
            curX = curX + 6
            i = i + 1
        Wend
    End Sub

    ' -------------------------------------------------------------------------
    ' PRK Standard Arrow Cursor Engine (16x18 Sprite matching gui/main.c)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub SaveCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0

        If frontSurf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, frontSurf.Pixels) + (CType(UInt32, curY) * frontSurf.Pitch)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            Dim bOff As UInt32 = CType(UInt32, curX) * 3
                            Dim b As UInt32 = CType(UInt32, rawRow(bOff))
                            Dim g As UInt32 = CType(UInt32, rawRow(bOff + 1))
                            Dim r As UInt32 = CType(UInt32, rawRow(bOff + 2))
                            cursorSavedBg((cy * CURSOR_W) + cx) = &HFF000000 Or (r LShift 16) Or (g LShift 8) Or b
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        Else
            Dim pitchPix As UInt32 = frontSurf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            cursorSavedBg((cy * CURSOR_W) + cx) = rowPtr(curX)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        End If
    End Sub

    Private Unsafe Sub RestoreCursorBackground(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub
        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0

        If frontSurf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, frontSurf.Pixels) + (CType(UInt32, curY) * frontSurf.Pitch)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            Dim col As UInt32 = cursorSavedBg((cy * CURSOR_W) + cx)
                            Dim bOff As UInt32 = CType(UInt32, curX) * 3
                            rawRow(bOff) = CType(Byte, col And &HFF)
                            rawRow(bOff + 1) = CType(Byte, (col RShift 8) And &HFF)
                            rawRow(bOff + 2) = CType(Byte, (col RShift 16) And &HFF)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        Else
            Dim pitchPix As UInt32 = frontSurf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            rowPtr(curX) = cursorSavedBg((cy * CURSOR_W) + cx)
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        End If
    End Sub

    Private Unsafe Sub DrawCursorArrow(ByVal x As Int32, ByVal y As Int32)
        If frontSurf.Pixels = 0 Then Exit Sub

        ' PRK cursor_arrow bitmap:
        ' activeMask: 1 = pixel present, 0 = transparent
        ' colorMask:  1 = White (0xFFFFFFFF), 0 = Black border (0xFF000000)
        Dim activeMask(18) As UInt16
        Dim colorMask(18)  As UInt16

        activeMask(0)  = &H8000: colorMask(0)  = &H0000 ' "X               "
        activeMask(1)  = &HC000: colorMask(1)  = &H0000 ' "XX              "
        activeMask(2)  = &HE000: colorMask(2)  = &H4000 ' "X.X             "
        activeMask(3)  = &HF000: colorMask(3)  = &H6000 ' "X..X            "
        activeMask(4)  = &HF800: colorMask(4)  = &H7000 ' "X...X           "
        activeMask(5)  = &HFC00: colorMask(5)  = &H7800 ' "X....X          "
        activeMask(6)  = &HFE00: colorMask(6)  = &H7C00 ' "X.....X         "
        activeMask(7)  = &HFF00: colorMask(7)  = &H7E00 ' "X......X        "
        activeMask(8)  = &HFF80: colorMask(8)  = &H7F00 ' "X.......X       "
        activeMask(9)  = &HFFC0: colorMask(9)  = &H7F80 ' "X........X      "
        activeMask(10) = &HFFC0: colorMask(10) = &H7C00 ' "X.....XXXX      "
        activeMask(11) = &HFE00: colorMask(11) = &H6C00 ' "X..X..X         "
        activeMask(12) = &HEF00: colorMask(12) = &H4600 ' "X.X X..X        "
        activeMask(13) = &HCF00: colorMask(13) = &H0600 ' "XX  X..X        "
        activeMask(14) = &H8780: colorMask(14) = &H0300 ' "X    X..X       "
        activeMask(15) = &H0780: colorMask(15) = &H0300 ' "     X..X       "
        activeMask(16) = &H0300: colorMask(16) = &H0000 ' "      XX        "
        activeMask(17) = &H0000: colorMask(17) = &H0000 ' "                "

        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0
        Dim actRow As UInt16 = 0
        Dim colRow As UInt16 = 0
        Dim shiftVal As Int32 = 0
        Dim isDrawn As Boolean = False
        Dim isWhite As Boolean = False

        If frontSurf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, frontSurf.Pixels) + (CType(UInt32, curY) * frontSurf.Pitch)
                    actRow = activeMask(cy)
                    colRow = colorMask(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            shiftVal = 15 - cx
                            isDrawn = ((actRow RShift shiftVal) And 1) <> 0
                            If isDrawn Then
                                isWhite = ((colRow RShift shiftVal) And 1) <> 0
                                Dim bOff As UInt32 = CType(UInt32, curX) * 3
                                If isWhite Then
                                    rawRow(bOff) = &HFF
                                    rawRow(bOff + 1) = &HFF
                                    rawRow(bOff + 2) = &HFF
                                Else
                                    rawRow(bOff) = 0
                                    rawRow(bOff + 1) = 0
                                    rawRow(bOff + 2) = 0
                                End If
                            End If
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        Else
            Dim pitchPix As UInt32 = frontSurf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, frontSurf.Height) Then
                    Dim rowPtr As Pointer To UInt32 = frontSurf.Pixels + (CType(UInt32, curY) * pitchPix)
                    actRow = activeMask(cy)
                    colRow = colorMask(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, frontSurf.Width) Then
                            shiftVal = 15 - cx
                            isDrawn = ((actRow RShift shiftVal) And 1) <> 0
                            If isDrawn Then
                                isWhite = ((colRow RShift shiftVal) And 1) <> 0
                                If isWhite Then
                                    rowPtr(curX) = &HFFFFFFFF ' Crisp White Fill
                                Else
                                    rowPtr(curX) = &HFF000000 ' Sharp Black Border
                                End If
                            End If
                        End If
                        cx = cx + 1
                    Wend
                End If
                cy = cy + 1
            Wend
        End If
    End Sub

    ''
    ' @brief Check if a candidate bounding box intersects the current cursor rectangle.
    ''
    Private Function CursorIntersects(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32) As Boolean
        If (cursorX + CURSOR_W) <= rx Or cursorX >= (rx + rw) Then
            CursorIntersects = False
            Exit Function
        End If
        If (cursorY + CURSOR_H) <= ry Or cursorY >= (ry + rh) Then
            CursorIntersects = False
            Exit Function
        End If
        CursorIntersects = True
    End Function

    ' -------------------------------------------------------------------------
    ' Telemetry Status Badge Renderer (Paced at half-speed with Dynamic FPS)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub RenderTelemetryBadge()
        If Not badgeActive Then Exit Sub

        Dim restoreCursor As Boolean = (cursorInitialized And CursorIntersects(badgeX, badgeY, 200, 26))
        If restoreCursor Then
            RestoreCursorBackground cursorX, cursorY
        End If

        ' 1. Cycle status LED color (breathing green -> cyan -> mint -> emerald)
        Dim ledColor As UInt32 = &HFF00C853
        Dim colorPhase As UInt32 = (frameCount / 12) Mod 4
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

        ' 3. Ping-pong animated scanner pulse with multi-layer glow
        Dim pulseX As Int32 = trackX + animPos
        If pulseX < trackX Then pulseX = trackX
        If (pulseX + pulseW) > (trackX + trackW) Then
            pulseX = (trackX + trackW) - pulseW
        End If

        FillRect frontSurf, pulseX, trackY + 1, pulseW, trackH - 2, &HFF00897B
        FillRect frontSurf, pulseX + 4, trackY + 3, pulseW - 8, trackH - 6, &HFF00E5FF
        FillRect frontSurf, pulseX + 9, trackY + 5, pulseW - 18, trackH - 10, &HFFFFFFFF

        ' Advance animation at half-speed (2 pixels per frame)
        animPos = animPos + animDir
        If animPos >= (trackW - pulseW) Then
            animPos = trackW - pulseW
            animDir = -2
        ElseIf animPos <= 0 Then
            animPos = 0
            animDir = 2
        End If

        ' 4. Real-time dynamic FPS counter text measured from system timer
        Dim fpsBuf(16) As Byte
        Dim fIdx As UInt32 = 0
        AppendUInt CType(UInt64, currentFps), @fpsBuf(0), fIdx
        AppendStr " FPS", @fpsBuf(0), fIdx
        fpsBuf(fIdx) = 0

        ' Clear FPS text region and redraw dynamic counter
        FillRect frontSurf, badgeX + 138, badgeY + 6, 60, 16, &HFF2E3440
        DrawText5x7 frontSurf, badgeX + 140, badgeY + 10, @fpsBuf(0), &HFF88C0D0

        If restoreCursor Then
            SaveCursorBackground cursorX, cursorY
            DrawCursorArrow cursorX, cursorY
        End If
    End Sub

    ''
    ' @brief Render live mouse coordinates text on top system menu bar.
    ''
    Private Unsafe Sub RenderMouseCoordinates()
        If frontSurf.Pixels = 0 Then Exit Sub

        Dim restoreCursor As Boolean = (cursorInitialized And CursorIntersects(430, 6, 180, 14))
        If restoreCursor Then
            RestoreCursorBackground cursorX, cursorY
        End If

        Dim coordBuf(32) As Byte
        Dim cIdx As UInt32 = 0
        AppendStr "MOUSE: X=", @coordBuf(0), cIdx
        AppendUInt CType(UInt64, cursorX), @coordBuf(0), cIdx
        AppendStr " Y=", @coordBuf(0), cIdx
        AppendUInt CType(UInt64, cursorY), @coordBuf(0), cIdx
        coordBuf(cIdx) = 0

        FillRect frontSurf, 430, 6, 180, 14, &HFF232731
        DrawText5x7 frontSurf, 434, 10, @coordBuf(0), &HFFEBCB8B

        If restoreCursor Then
            SaveCursorBackground cursorX, cursorY
            DrawCursorArrow cursorX, cursorY
        End If
    End Sub

    ' -------------------------------------------------------------------------
    ' Desktop Background & Initial Window Canvas Pre-Renderer
    ' (Restored to exact previous theme and dimensions)
    ' -------------------------------------------------------------------------
    Private Unsafe Sub DrawDesktopScene()
        If frontSurf.Pixels = 0 Then Exit Sub

        ' 1. Clear boot splash to Nord Dark Background (#191D24)
        FillRect frontSurf, 0, 0, dispInfo.Width, dispInfo.Height, &HFF191D24

        ' 2. Top System Menu Bar (y: 0..26)
        FillRect frontSurf, 0, 0, dispInfo.Width, 26, &HFF232731
        FillRect frontSurf, 0, 25, dispInfo.Width, 1, &HFF4C566A
        FillRect frontSurf, 0, 0, 4, 25, &HFF88C0D0

        DrawText5x7 frontSurf, 16, 10, CPtr(Pointer To Byte, "PROS WORKSTATION  |  APPLICATIONS  NODES  SERVICES"), &HFFECEFF4
        RenderMouseCoordinates
        DrawText5x7 frontSurf, CType(Int32, dispInfo.Width) - 340, 10, CPtr(Pointer To Byte, "REV: 2026.10.26-r26"), &HFF88C0D0
        DrawText5x7 frontSurf, CType(Int32, dispInfo.Width) - 170, 10, CPtr(Pointer To Byte, "SMP 4 CORES  ONLINE"), &HFFA3BE8C

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

        ' Window Buttons (Minimize, Maximize, Close - minimalist squares)
        FillRect frontSurf, (wx + ww) - 54, wy + 8, 10, 10, &HFF5E81AC ' Min
        FillRect frontSurf, (wx + ww) - 38, wy + 8, 10, 10, &HFFA3BE8C ' Max
        FillRect frontSurf, (wx + ww) - 22, wy + 8, 10, 10, &HFFBF616A ' Close

        ' Window Client Canvas
        FillRect frontSurf, wx + 2, wy + 28, ww - 4, wh - 30, &HFF232731

        ' Card 1: Microkernel Architecture
        FillRect frontSurf, wx + 16, wy + 40, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 40, 3, 42, &HFF81A1C1
        DrawText5x7 frontSurf, wx + 26, wy + 48, CPtr(Pointer To Byte, "KERNEL : PRK-LLB MICROKERNEL [REV: 2026.10.26-r26]"), &HFF81A1C1
        DrawText5x7 frontSurf, wx + 26, wy + 64, CPtr(Pointer To Byte, "MODEL  : DUAL-PLANE NEURAL SYNAPSE ROUTING"), &HFFD8DEE9

        ' Card 2: Compositor Status
        FillRect frontSurf, wx + 16, wy + 92, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 92, 3, 42, &HFFA3BE8C
        DrawText5x7 frontSurf, wx + 26, wy + 100, CPtr(Pointer To Byte, "ENGINE : ZERO-COPY WINDOW SURFACE PIPELINE"), &HFFA3BE8C
        DrawText5x7 frontSurf, wx + 26, wy + 116, CPtr(Pointer To Byte, "DRIVER : DIRECT LINEAR FRAMEBUFFER APERTURE"), &HFFECEFF4

        ' Card 3: Display & Subsystem Status
        FillRect frontSurf, wx + 16, wy + 144, ww - 32, 42, &HFF1E222A
        FillRect frontSurf, wx + 16, wy + 144, 3, 42, &HFFEBCB8B
        DrawText5x7 frontSurf, wx + 26, wy + 152, CPtr(Pointer To Byte, "INPUT  : INPUT_SRV DAEMON ONLINE (PS/2 MOUSE)"), &HFFEBCB8B

        Dim dBuf(64) As Byte
        Dim dIdx As UInt32 = 0
        AppendStr "SCREEN : ", @dBuf(0), dIdx
        AppendUInt CType(UInt64, dispInfo.Width), @dBuf(0), dIdx
        AppendStr "x", @dBuf(0), dIdx
        AppendUInt CType(UInt64, dispInfo.Height), @dBuf(0), dIdx
        AppendStr " @ ", @dBuf(0), dIdx
        AppendUInt CType(UInt64, dispInfo.Bpp), @dBuf(0), dIdx
        AppendStr " BPP (PITCH: ", @dBuf(0), dIdx
        AppendUInt CType(UInt64, dispInfo.Pitch), @dBuf(0), dIdx
        AppendStr ")", @dBuf(0), dIdx
        dBuf(dIdx) = 0
        DrawText5x7 frontSurf, wx + 26, wy + 168, @dBuf(0), &HFFECEFF4

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
        RenderMouseCoordinates
        ConsoleWriteLine "[COMPOSITOR] Hardware software cursor plane initialized at screen center."

        ' 7. Active Presentation & Event Loop
        ConsoleWriteLine "[COMPOSITOR] Compositor online. Entering presentation loop..."

        Dim mState As MouseState
        lastFpsTime = GetUptime()
        nextAnimTime = lastFpsTime
        Dim activeUntil As UInt64 = 0

        Do
            Dim mouseMoved As Boolean = False
            Dim nowTime As UInt64 = GetUptime()

            ' A. Read live hardware PS/2 mouse state and update cursor position with zero lag
            If GetMouseState(mState) Then
                Dim newMx As Int32 = mState.X
                Dim newMy As Int32 = mState.Y

                ' Allow natural desktop overflow: cursor hotspot tip (0,0) reaches every boundary pixel
                If newMx < 0 Then newMx = 0
                If newMx >= CType(Int32, dispInfo.Width) Then newMx = CType(Int32, dispInfo.Width) - 1
                If newMy < 0 Then newMy = 0
                If newMy >= CType(Int32, dispInfo.Height) Then newMy = CType(Int32, dispInfo.Height) - 1

                If newMx <> cursorX Or newMy <> cursorY Then
                    RestoreCursorBackground cursorX, cursorY
                    cursorX = newMx
                    cursorY = newMy
                    SaveCursorBackground cursorX, cursorY
                    DrawCursorArrow cursorX, cursorY
                    mouseMoved = True
                    activeUntil = nowTime + 200
                End If
            End If

            ' B. Update telemetry animation and dynamic FPS counter on timer ticks (~60 FPS pace)
            If nowTime >= nextAnimTime Then
                RenderTelemetryBadge
                RenderMouseCoordinates
                If (nowTime - nextAnimTime) > 32 Then
                    nextAnimTime = nowTime + 16
                Else
                    nextAnimTime = nextAnimTime + 16
                End If
                frameCount = frameCount + 1
            End If

            ' C. Dynamic FPS calculation every 1000 ms
            If nowTime >= (lastFpsTime + 1000) Then
                Dim elapsedSec As UInt64 = nowTime - lastFpsTime
                If elapsedSec > 0 Then
                    currentFps = CType(UInt32, ((CType(UInt64, frameCount - lastFpsFrame) * 1000) / elapsedSec))
                End If
                lastFpsFrame = frameCount
                lastFpsTime = nowTime
            End If

            ' Adaptive Pacing Strategy (Proven r18 Configuration):
            ' When mouse is actively moving: immediate ProcessYield for zero-latency smooth 60 FPS tracking.
            ' When idle and waiting for next animation frame: brief ProcessSleep 1 allows CPU core to halt (sti; hlt).
            If mouseMoved Then
                ProcessYield
            Else
                Dim waitRemaining As UInt64 = 0
                If nextAnimTime > nowTime Then
                    waitRemaining = nextAnimTime - nowTime
                End If

                If waitRemaining >= 15 Then
                    ProcessSleep 1
                Else
                    ProcessYield
                End If
            End If
        Loop

        user_main = 0
    End Function

End Module
