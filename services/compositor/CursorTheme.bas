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
    Private Const ArrowActive(18) As UInt16 = { _
        &H8000, &HC000, &HE000, &HF000, &HF800, &HFC00, &HFE00, &HFF00, _
        &HFF80, &HFFC0, &HFFC0, &HFE00, &HEF00, &HCF00, &H8780, &H0780, _
        &H0300, &H0000 _
    }
    Private Const ArrowColor(18) As UInt16 = { _
        &H0000, &H0000, &H4000, &H6000, &H7000, &H7800, &H7C00, &H7E00, _
        &H7F00, &H7F80, &H7C00, &H6C00, &H4600, &H0600, &H0300, &H0300, _
        &H0000, &H0000 _
    }

    Private Const IBeamActive(18) As UInt16 = { _
        &H3F00, &H0C00, &H0C00, &H0C00, &H0C00, &H0C00, &H0C00, &H0C00, _
        &H0C00, &H0C00, &H0C00, &H0C00, &H0C00, &H3F00, &H0000, &H0000, _
        &H0000, &H0000 _
    }
    Private Const IBeamColor(18) As UInt16 = { _
        &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, _
        &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }

    Private Const ResizeEWActive(18) As UInt16 = { _
        &H0000, &H0000, &H0000, &H0810, &H1818, &H3FFC, &H7FFE, &H3FFC, _
        &H1818, &H0810, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }
    Private Const ResizeEWColor(18) As UInt16 = { _
        &H0000, &H0000, &H0000, &H0000, &H0000, &H1008, &H3FFC, &H1008, _
        &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }

    Private Const ResizeNSActive(18) As UInt16 = { _
        &H0100, &H0380, &H07C0, &H0FC0, &H0100, &H0100, &H0100, &H0100, _
        &H0100, &H0100, &H0FC0, &H07C0, &H0380, &H0100, &H0000, &H0000, _
        &H0000, &H0000 _
    }
    Private Const ResizeNSColor(18) As UInt16 = { _
        &H0000, &H0100, &H0380, &H0000, &H0000, &H0000, &H0000, &H0000, _
        &H0000, &H0000, &H0000, &H0380, &H0100, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }

    Private Const ResizeNWSEActive(18) As UInt16 = { _
        &HF000, &HF000, &HF800, &H9C00, &H0E00, &H0700, &H0380, &H01C0, _
        &H00E0, &H0070, &H0039, &H001F, &H000F, &H000F, &H0000, &H0000, _
        &H0000, &H0000 _
    }
    Private Const ResizeNWSEColor(18) As UInt16 = { _
        &H0000, &H6000, &H5000, &H0800, &H0400, &H0200, &H0100, &H0080, _
        &H0040, &H0020, &H0010, &H000A, &H0006, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }

    Private Const ResizeNESWActive(18) As UInt16 = { _
        &H000F, &H000F, &H001F, &H0039, &H0070, &H00E0, &H01C0, &H0380, _
        &H0700, &H0E00, &H9C00, &HF800, &HF000, &HF000, &H0000, &H0000, _
        &H0000, &H0000 _
    }
    Private Const ResizeNESWColor(18) As UInt16 = { _
        &H0000, &H0006, &H000A, &H0010, &H0020, &H0040, &H0080, &H0100, _
        &H0200, &H0400, &H0800, &H5000, &H6000, &H0000, &H0000, &H0000, _
        &H0000, &H0000 _
    }

    ''
    ' @brief Retrieve pointer to static active bitmask table for cursor sprite.
    ''
    Public Unsafe Function GetCursorActiveMask(ByVal cursorType As UInt32) As Pointer To UInt16
        Select Case cursorType
            Case CURSOR_ARROW
                GetCursorActiveMask = *UInt16(AddressOf ArrowActive)
            Case CURSOR_IBEAM
                GetCursorActiveMask = *UInt16(AddressOf IBeamActive)
            Case CURSOR_RESIZE_EW
                GetCursorActiveMask = *UInt16(AddressOf ResizeEWActive)
            Case CURSOR_RESIZE_NS
                GetCursorActiveMask = *UInt16(AddressOf ResizeNSActive)
            Case CURSOR_RESIZE_NWSE
                GetCursorActiveMask = *UInt16(AddressOf ResizeNWSEActive)
            Case CURSOR_RESIZE_NESW
                GetCursorActiveMask = *UInt16(AddressOf ResizeNESWActive)
            Case Else
                GetCursorActiveMask = *UInt16(AddressOf ArrowActive)
        End Select
    End Function

    ''
    ' @brief Retrieve pointer to static color bitmask table for cursor sprite.
    ''
    Public Unsafe Function GetCursorColorMask(ByVal cursorType As UInt32) As Pointer To UInt16
        Select Case cursorType
            Case CURSOR_ARROW
                GetCursorColorMask = *UInt16(AddressOf ArrowColor)
            Case CURSOR_IBEAM
                GetCursorColorMask = *UInt16(AddressOf IBeamColor)
            Case CURSOR_RESIZE_EW
                GetCursorColorMask = *UInt16(AddressOf ResizeEWColor)
            Case CURSOR_RESIZE_NS
                GetCursorColorMask = *UInt16(AddressOf ResizeNSColor)
            Case CURSOR_RESIZE_NWSE
                GetCursorColorMask = *UInt16(AddressOf ResizeNWSEColor)
            Case CURSOR_RESIZE_NESW
                GetCursorColorMask = *UInt16(AddressOf ResizeNESWColor)
            Case Else
                GetCursorColorMask = *UInt16(AddressOf ArrowColor)
        End Select
    End Function

    ''
    ' @brief Retrieve pointers to the constant row bitmasks for the specified cursor sprite.
    ' @param cursorType Target cursor index.
    ' @param pAct Output pointer to 18-element active mask table.
    ' @param pCol Output pointer to 18-element color mask table.
    ''
    Public Unsafe Sub GetCursorMasks(ByVal cursorType As UInt32, ByRef pAct As Pointer To UInt16, ByRef pCol As Pointer To UInt16)
        pAct = GetCursorActiveMask(cursorType)
        pCol = GetCursorColorMask(cursorType)
    End Sub

    ''
    ' @brief Load row bitmasks for the specified cursor sprite into destination buffers.
    ' @param cursorType Target cursor index.
    ' @param pAct Pointer to 18-element UInt16 active mask buffer.
    ' @param pCol Pointer to 18-element UInt16 color mask buffer.
    ''
    Public Unsafe Sub LoadCursorMasks(ByVal cursorType As UInt32, ByVal pAct As Pointer To UInt16, ByVal pCol As Pointer To UInt16)
        Dim pSrcAct As Pointer To UInt16 = GetCursorActiveMask(cursorType)
        Dim pSrcCol As Pointer To UInt16 = GetCursorColorMask(cursorType)
        If pSrcAct = 0 Or pSrcCol = 0 Or pAct = 0 Or pCol = 0 Then Exit Sub
        Dim r As Int32
        For r = 0 To CURSOR_H - 1
            pAct(r) = pSrcAct(r)
            pCol(r) = pSrcCol(r)
        Next r
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

        Dim pAct As Pointer To UInt16 = GetCursorActiveMask(cursorType)
        Dim pCol As Pointer To UInt16 = GetCursorColorMask(cursorType)
        If pAct = 0 Or pCol = 0 Then Exit Sub

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
                If curY >= 0 And curY < surf.Height Then
                    Dim rawRow As Pointer To Byte = *Byte(surf.Pixels) + (UInt32(curY) * surf.Pitch)
                    actRow = pAct(cy)
                    colRow = pCol(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < surf.Width Then
                            shiftVal = 15 - cx
                            isDrawn = ((actRow RShift shiftVal) And 1) <> 0
                            If isDrawn Then
                                isWhite = ((colRow RShift shiftVal) And 1) <> 0
                                Dim bOff As UInt32 = UInt32(curX) * 3
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
                If curY >= 0 And curY < surf.Height Then
                    Dim rowPtr As Pointer To UInt32 = surf.Pixels + (UInt32(curY) * pitchPix)
                    actRow = pAct(cy)
                    colRow = pCol(cy)
                    cx = 0
                    While cx < CURSOR_W
                        curX = x + cx
                        If curX >= 0 And curX < surf.Width Then
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
