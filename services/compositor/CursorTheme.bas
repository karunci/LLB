' Project Name: PROS / Low-Level Basic
' Filename: services/compositor/CursorTheme.bas
' Summary: Decoupled cursor theme manager, PRK 16x18 sprite masks, and software cursor rasterizer.

Import "../../include/pros.bas"

Module CursorTheme

    ' =========================================================================
    ' 1. Cursor Type Enumeration & Dimensions
    ' =========================================================================
    Public Const CURSOR_ARROW       As UInt32 = 0
    Public Const CURSOR_IBEAM       As UInt32 = 1
    Public Const CURSOR_RESIZE_EW   As UInt32 = 2
    Public Const CURSOR_RESIZE_NS   As UInt32 = 3
    Public Const CURSOR_RESIZE_NWSE As UInt32 = 4
    Public Const CURSOR_RESIZE_NESW As UInt32 = 5
    Public Const CURSOR_COUNT       As UInt32 = 6

    Public Const CURSOR_W As Int32 = 16
    Public Const CURSOR_H As Int32 = 18

    ' =========================================================================
    ' 2. Hotspot Coordinates Retrieval
    ' =========================================================================
    ''
    ' @brief Retrieve the pixel hotspot offset for a given cursor sprite.
    ' @param cursorType Cursor identifier (0..5).
    ' @param hx Output parameter for horizontal hotspot offset.
    ' @param hy Output parameter for vertical hotspot offset.
    ''
    Public Sub GetHotspot(ByVal cursorType As UInt32, ByRef hx As Int32, ByRef hy As Int32)
        Select Case cursorType
            Case CURSOR_ARROW
                hx = 0: hy = 0
            Case CURSOR_IBEAM
                hx = 5: hy = 6
            Case CURSOR_RESIZE_EW
                hx = 8: hy = 6
            Case CURSOR_RESIZE_NS
                hx = 7: hy = 6
            Case CURSOR_RESIZE_NWSE
                hx = 6: hy = 6
            Case CURSOR_RESIZE_NESW
                hx = 6: hy = 6
            Case Else
                hx = 0: hy = 0
        End Select
    End Sub

    ' =========================================================================
    ' 3. Sprite Mask Tables (16-bit Bitmasks from PRK Reference)
    '    activeMask: 1 = pixel present, 0 = transparent
    '    colorMask:  1 = crisp white interior (&HFFFFFFFF), 0 = black border (&HFF000000)
    ' =========================================================================
    ''
    ' @brief Load row bitmasks for the specified cursor sprite.
    ' @param cursorType Target cursor index.
    ' @param pAct Pointer to 18-element UInt16 active mask buffer.
    ' @param pCol Pointer to 18-element UInt16 color mask buffer.
    ''
    Public Unsafe Sub LoadCursorMasks(ByVal cursorType As UInt32, ByVal pAct As Pointer To UInt16, ByVal pCol As Pointer To UInt16)
        Select Case cursorType
            Case CURSOR_ARROW
                pAct(0)  = &H8000: pCol(0)  = &H0000 ' "X               "
                pAct(1)  = &HC000: pCol(1)  = &H0000 ' "XX              "
                pAct(2)  = &HE000: pCol(2)  = &H4000 ' "X.X             "
                pAct(3)  = &HF000: pCol(3)  = &H6000 ' "X..X            "
                pAct(4)  = &HF800: pCol(4)  = &H7000 ' "X...X           "
                pAct(5)  = &HFC00: pCol(5)  = &H7800 ' "X....X          "
                pAct(6)  = &HFE00: pCol(6)  = &H7C00 ' "X.....X         "
                pAct(7)  = &HFF00: pCol(7)  = &H7E00 ' "X......X        "
                pAct(8)  = &HFF80: pCol(8)  = &H7F00 ' "X.......X       "
                pAct(9)  = &HFFC0: pCol(9)  = &H7F80 ' "X........X      "
                pAct(10) = &HFFC0: pCol(10) = &H7C00 ' "X.....XXXX      "
                pAct(11) = &HFE00: pCol(11) = &H6C00 ' "X..X..X         "
                pAct(12) = &HEF00: pCol(12) = &H4600 ' "X.X X..X        "
                pAct(13) = &HCF00: pCol(13) = &H0600 ' "XX  X..X        "
                pAct(14) = &H8780: pCol(14) = &H0300 ' "X    X..X       "
                pAct(15) = &H0780: pCol(15) = &H0300 ' "     X..X       "
                pAct(16) = &H0300: pCol(16) = &H0000 ' "      XX        "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case CURSOR_IBEAM
                pAct(0)  = &H3F00: pCol(0)  = &H0000 ' "  XXXXXX        "
                pAct(1)  = &H0C00: pCol(1)  = &H0000 ' "    XX          "
                pAct(2)  = &H0C00: pCol(2)  = &H0000 ' "    XX          "
                pAct(3)  = &H0C00: pCol(3)  = &H0000 ' "    XX          "
                pAct(4)  = &H0C00: pCol(4)  = &H0000 ' "    XX          "
                pAct(5)  = &H0C00: pCol(5)  = &H0000 ' "    XX          "
                pAct(6)  = &H0C00: pCol(6)  = &H0000 ' "    XX          "
                pAct(7)  = &H0C00: pCol(7)  = &H0000 ' "    XX          "
                pAct(8)  = &H0C00: pCol(8)  = &H0000 ' "    XX          "
                pAct(9)  = &H0C00: pCol(9)  = &H0000 ' "    XX          "
                pAct(10) = &H0C00: pCol(10) = &H0000 ' "    XX          "
                pAct(11) = &H0C00: pCol(11) = &H0000 ' "    XX          "
                pAct(12) = &H0C00: pCol(12) = &H0000 ' "    XX          "
                pAct(13) = &H3F00: pCol(13) = &H0000 ' "  XXXXXX        "
                pAct(14) = &H0000: pCol(14) = &H0000 ' "                "
                pAct(15) = &H0000: pCol(15) = &H0000 ' "                "
                pAct(16) = &H0000: pCol(16) = &H0000 ' "                "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case CURSOR_RESIZE_EW
                pAct(0)  = &H0000: pCol(0)  = &H0000 ' "                "
                pAct(1)  = &H0000: pCol(1)  = &H0000 ' "                "
                pAct(2)  = &H0000: pCol(2)  = &H0000 ' "                "
                pAct(3)  = &H0810: pCol(3)  = &H0000 ' "    X      X    "
                pAct(4)  = &H1818: pCol(4)  = &H0000 ' "   XX      XX   "
                pAct(5)  = &H3FFC: pCol(5)  = &H1008 ' "  X.XXXXXXXX.X  "
                pAct(6)  = &H7FFE: pCol(6)  = &H3FFC ' " X............X "
                pAct(7)  = &H3FFC: pCol(7)  = &H1008 ' "  X.XXXXXXXX.X  "
                pAct(8)  = &H1818: pCol(8)  = &H0000 ' "   XX      XX   "
                pAct(9)  = &H0810: pCol(9)  = &H0000 ' "    X      X    "
                pAct(10) = &H0000: pCol(10) = &H0000 ' "                "
                pAct(11) = &H0000: pCol(11) = &H0000 ' "                "
                pAct(12) = &H0000: pCol(12) = &H0000 ' "                "
                pAct(13) = &H0000: pCol(13) = &H0000 ' "                "
                pAct(14) = &H0000: pCol(14) = &H0000 ' "                "
                pAct(15) = &H0000: pCol(15) = &H0000 ' "                "
                pAct(16) = &H0000: pCol(16) = &H0000 ' "                "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case CURSOR_RESIZE_NS
                pAct(0)  = &H0100: pCol(0)  = &H0000 ' "       X        "
                pAct(1)  = &H0380: pCol(1)  = &H0100 ' "      X.X       "
                pAct(2)  = &H07C0: pCol(2)  = &H0380 ' "     X...X      "
                pAct(3)  = &H0FC0: pCol(3)  = &H0000 ' "    XXXXXX      "
                pAct(4)  = &H0100: pCol(4)  = &H0000 ' "       X        "
                pAct(5)  = &H0100: pCol(5)  = &H0000 ' "       X        "
                pAct(6)  = &H0100: pCol(6)  = &H0000 ' "       X        "
                pAct(7)  = &H0100: pCol(7)  = &H0000 ' "       X        "
                pAct(8)  = &H0100: pCol(8)  = &H0000 ' "       X        "
                pAct(9)  = &H0100: pCol(9)  = &H0000 ' "       X        "
                pAct(10) = &H0FC0: pCol(10) = &H0000 ' "    XXXXXX      "
                pAct(11) = &H07C0: pCol(11) = &H0380 ' "     X...X      "
                pAct(12) = &H0380: pCol(12) = &H0100 ' "      X.X       "
                pAct(13) = &H0100: pCol(13) = &H0000 ' "       X        "
                pAct(14) = &H0000: pCol(14) = &H0000 ' "                "
                pAct(15) = &H0000: pCol(15) = &H0000 ' "                "
                pAct(16) = &H0000: pCol(16) = &H0000 ' "                "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case CURSOR_RESIZE_NWSE
                pAct(0)  = &HF000: pCol(0)  = &H0000 ' "XXXX            "
                pAct(1)  = &HF000: pCol(1)  = &H6000 ' "X..X            "
                pAct(2)  = &HF800: pCol(2)  = &H5000 ' "X.X.X           "
                pAct(3)  = &H9C00: pCol(3)  = &H0800 ' "X  X.X          "
                pAct(4)  = &H0E00: pCol(4)  = &H0400 ' "    X.X         "
                pAct(5)  = &H0700: pCol(5)  = &H0200 ' "     X.X        "
                pAct(6)  = &H0380: pCol(6)  = &H0100 ' "      X.X       "
                pAct(7)  = &H01C0: pCol(7)  = &H0080 ' "       X.X      "
                pAct(8)  = &H00E0: pCol(8)  = &H0040 ' "        X.X     "
                pAct(9)  = &H0070: pCol(9)  = &H0020 ' "         X.X    "
                pAct(10) = &H0039: pCol(10) = &H0010 ' "          X.X  X"
                pAct(11) = &H001F: pCol(11) = &H000A ' "           X.X.X"
                pAct(12) = &H000F: pCol(12) = &H0006 ' "            X..X"
                pAct(13) = &H000F: pCol(13) = &H0000 ' "            XXXX"
                pAct(14) = &H0000: pCol(14) = &H0000 ' "                "
                pAct(15) = &H0000: pCol(15) = &H0000 ' "                "
                pAct(16) = &H0000: pCol(16) = &H0000 ' "                "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case CURSOR_RESIZE_NESW
                pAct(0)  = &H000F: pCol(0)  = &H0000 ' "            XXXX"
                pAct(1)  = &H000F: pCol(1)  = &H0006 ' "            X..X"
                pAct(2)  = &H001F: pCol(2)  = &H000A ' "           X.X.X"
                pAct(3)  = &H0039: pCol(3)  = &H0010 ' "          X.X  X"
                pAct(4)  = &H0070: pCol(4)  = &H0020 ' "         X.X    "
                pAct(5)  = &H00E0: pCol(5)  = &H0040 ' "        X.X     "
                pAct(6)  = &H01C0: pCol(6)  = &H0080 ' "       X.X      "
                pAct(7)  = &H0380: pCol(7)  = &H0100 ' "      X.X       "
                pAct(8)  = &H0700: pCol(8)  = &H0200 ' "     X.X        "
                pAct(9)  = &H0E00: pCol(9)  = &H0400 ' "    X.X         "
                pAct(10) = &H9C00: pCol(10) = &H0800 ' "X  X.X          "
                pAct(11) = &HF800: pCol(11) = &H5000 ' "X.X.X           "
                pAct(12) = &HF000: pCol(12) = &H6000 ' "X..X            "
                pAct(13) = &HF000: pCol(13) = &H0000 ' "XXXX            "
                pAct(14) = &H0000: pCol(14) = &H0000 ' "                "
                pAct(15) = &H0000: pCol(15) = &H0000 ' "                "
                pAct(16) = &H0000: pCol(16) = &H0000 ' "                "
                pAct(17) = &H0000: pCol(17) = &H0000 ' "                "

            Case Else
                LoadCursorMasks CURSOR_ARROW, pAct, pCol
        End Select
    End Sub

    ' =========================================================================
    ' 4. Cursor Surface Rasterizer (24-bit / 32-bit Framebuffers)
    ' =========================================================================
    ''
    ' @brief Rasterize a cursor sprite onto the specified surface with clipping.
    ' @param surf Target destination surface (e.g. compositor backSurf).
    ' @param x Screen X coordinate for top-left cursor bounding box.
    ' @param y Screen Y coordinate for top-left cursor bounding box.
    ' @param cursorType Cursor identifier (0..5).
    ''
    Public Unsafe Sub DrawCursor(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal cursorType As UInt32)
        If surf.Pixels = 0 Then Exit Sub

        Dim activeMask(18) As UInt16
        Dim colorMask(18)  As UInt16
        LoadCursorMasks cursorType, @activeMask(0), @colorMask(0)

        Dim cy As Int32 = 0
        Dim curY As Int32 = 0
        Dim cx As Int32 = 0
        Dim curX As Int32 = 0
        Dim actRow As UInt16 = 0
        Dim colRow As UInt16 = 0
        Dim shiftVal As Int32 = 0
        Dim isDrawn As Boolean = False
        Dim isWhite As Boolean = False

        If surf.Bpp = 24 Then
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, surf.Height) Then
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, surf.Pixels) + (CType(UInt32, curY) * surf.Pitch)
                    actRow = activeMask(cy)
                    colRow = colorMask(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, surf.Width) Then
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
            Dim pitchPix As UInt32 = surf.Pitch / 4
            cy = 0
            While cy < CURSOR_H
                curY = y + cy
                If curY >= 0 And curY < CType(Int32, surf.Height) Then
                    Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, curY) * pitchPix)
                    actRow = activeMask(cy)
                    colRow = colorMask(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < CType(Int32, surf.Width) Then
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

End Module
