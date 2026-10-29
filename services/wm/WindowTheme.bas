' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/wm/WindowTheme.bas
' Summary: Window Theme Engine and Decorator for PROS Window Manager and Compositor.
'          Provides decoupled Nord palette, button metrics, hit-test geometry,
'          and 10x10 glyph bitmask tables using aggregate initializers.

Import "../../include/pros.bas"

Module WindowTheme

    ' =========================================================================
    ' 1. Window Metrics & Dimensions
    ' =========================================================================
    Public Const TITLEBAR_HEIGHT    As Int32 = 26
    Public Const BORDER_WIDTH        As Int32 = 1
    Public Const SHADOW_OFFSET       As Int32 = 4
    Public Const BUTTON_W            As Int32 = 10
    Public Const BUTTON_H            As Int32 = 10
    Public Const BUTTON_Y_OFFSET     As Int32 = 8
    Public Const BUTTON_SPACING      As Int32 = 6
    Public Const RESIZE_HANDLE_SIZE  As Int32 = 16

    ' =========================================================================
    ' 2. Window Hit-Testing Codes
    ' =========================================================================
    Public Const HIT_NONE            As UInt32 = 0
    Public Const HIT_CLIENT          As UInt32 = 1
    Public Const HIT_TITLEBAR        As UInt32 = 2
    Public Const HIT_BTN_CLOSE       As UInt32 = 3
    Public Const HIT_BTN_MAX         As UInt32 = 4
    Public Const HIT_BTN_MIN         As UInt32 = 5
    Public Const HIT_RESIZE_BR       As UInt32 = 6
    Public Const HIT_BORDER_EW       As UInt32 = 7
    Public Const HIT_BORDER_NS       As UInt32 = 8

    ' =========================================================================
    ' 3. Window State Identifiers
    ' =========================================================================
    Public Const WIN_STATE_NORMAL    As Int32 = 0
    Public Const WIN_STATE_MINIMIZED As Int32 = 1
    Public Const WIN_STATE_MAXIMIZED As Int32 = 2

    ' =========================================================================
    ' 4. Window Manager Action IPC Codes (PRK & PROS ABI)
    ' =========================================================================
    Public Const WM_ACTION_FOCUS_GAINED As UInt32 = 1
    Public Const WM_ACTION_FOCUS_LOST   As UInt32 = 2
    Public Const WM_ACTION_MOVE         As UInt32 = 3
    Public Const WM_ACTION_RESIZE       As UInt32 = 4
    Public Const WM_ACTION_MINIMIZE     As UInt32 = 5
    Public Const WM_ACTION_MAXIMIZE     As UInt32 = 6
    Public Const WM_ACTION_RESTORE      As UInt32 = 7
    Public Const WM_ACTION_CLOSE        As UInt32 = 8

    ' =========================================================================
    ' 5. Nord System Palette Colors (32-bit ARGB)
    ' =========================================================================
    Public Const COLOR_WIN_SHADOW            As UInt32 = &HFF121419
    Public Const COLOR_WIN_ACTIVE_BORDER     As UInt32 = &HFF434C5E
    Public Const COLOR_WIN_INACTIVE_BORDER   As UInt32 = &HFF3B4252
    Public Const COLOR_WIN_ACTIVE_TITLEBAR   As UInt32 = &HFF2E3440
    Public Const COLOR_WIN_INACTIVE_TITLEBAR As UInt32 = &HFF242933
    Public Const COLOR_WIN_ACTIVE_ACCENT     As UInt32 = &HFF5E81AC
    Public Const COLOR_WIN_INACTIVE_ACCENT   As UInt32 = &HFF4C566A
    Public Const COLOR_WIN_ACTIVE_TEXT       As UInt32 = &HFFECEFF4
    Public Const COLOR_WIN_INACTIVE_TEXT     As UInt32 = &HFF9AA5B8
    Public Const COLOR_WIN_CLIENT_BG         As UInt32 = &HFF232731

    ' Button State Colors
    Public Const COLOR_BTN_CLOSE_NORMAL      As UInt32 = &HFFBF616A
    Public Const COLOR_BTN_CLOSE_HOVER       As UInt32 = &HFFD08770
    Public Const COLOR_BTN_CLOSE_PRESSED     As UInt32 = &HFF8F3D45

    Public Const COLOR_BTN_MAX_NORMAL        As UInt32 = &HFFA3BE8C
    Public Const COLOR_BTN_MAX_HOVER         As UInt32 = &HFFB8D3A0
    Public Const COLOR_BTN_MAX_PRESSED       As UInt32 = &HFF7A9966

    Public Const COLOR_BTN_MIN_NORMAL        As UInt32 = &HFF5E81AC
    Public Const COLOR_BTN_MIN_HOVER         As UInt32 = &HFF81A1C1
    Public Const COLOR_BTN_MIN_PRESSED       As UInt32 = &HFF435F82

    Public Const COLOR_RESIZE_GRIPPER        As UInt32 = &HFF4C566A
    Public Const COLOR_GLYPH_ICON            As UInt32 = &HFFECEFF4

    ' =========================================================================
    ' 6. 10x10 Window Button Glyphs (Aggregate Initializers)
    ' =========================================================================
    ' Close Glyph ('X')
    Private Const GLYPH_CLOSE(10) As UInt16 = { &H0000, &H0102, &H0084, &H0048, &H0030, &H0030, &H0048, &H0084, &H0102, &H0000 }

    ' Maximize Glyph (Square outline)
    Private Const GLYPH_MAX(10) As UInt16 = { &H0000, &H01FE, &H0102, &H0102, &H0102, &H0102, &H0102, &H0102, &H01FE, &H0000 }

    ' Minimize Glyph (Horizontal bar)
    Private Const GLYPH_MIN(10) As UInt16 = { &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H0000, &H01FE, &H01FE, &H0000 }

    ' Restore Glyph (Overlapping boxes)
    Private Const GLYPH_RESTORE(10) As UInt16 = { &H0000, &H01F8, &H0108, &H0108, &H017E, &H0042, &H0042, &H0042, &H007E, &H0000 }

    ''
    ' @brief Get pointer to static 10x10 button glyph bitmask.
    ' @param glyphType Button type: HIT_BTN_CLOSE, HIT_BTN_MAX, HIT_BTN_MIN, or WIN_STATE_MAXIMIZED for restore.
    ' @return Pointer to 10 UInt16 row bitmasks in .rodata.
    ''
    Public Unsafe Function GetGlyphMasks(ByVal glyphType As UInt32) As Pointer To UInt16
        If glyphType = HIT_BTN_CLOSE Then
            GetGlyphMasks = *UInt16(AddressOf GLYPH_CLOSE)
        ElseIf glyphType = HIT_BTN_MAX Then
            GetGlyphMasks = *UInt16(AddressOf GLYPH_MAX)
        ElseIf glyphType = HIT_BTN_MIN Then
            GetGlyphMasks = *UInt16(AddressOf GLYPH_MIN)
        ElseIf glyphType = 7 Then ' Restore
            GetGlyphMasks = *UInt16(AddressOf GLYPH_RESTORE)
        Else
            GetGlyphMasks = Nothing
        End If
    End Function

    ''
    ' @brief Perform hit testing on window geometry.
    ' @param mouseX Cursor X screen coordinate.
    ' @param mouseY Cursor Y screen coordinate.
    ' @param winX Window left coordinate.
    ' @param winY Window top coordinate.
    ' @param winW Window width.
    ' @param winH Window height.
    ' @return Hit test code (HIT_NONE, HIT_TITLEBAR, HIT_BTN_*, HIT_RESIZE_BR, HIT_CLIENT).
    ''
    Public Unsafe Function HitTestWindow(ByVal mouseX As Int32, ByVal mouseY As Int32, _
                                         ByVal winX As Int32, ByVal winY As Int32, _
                                         ByVal winW As Int32, ByVal winH As Int32) As UInt32
        ' Check outer bounds
        If mouseX < winX Or mouseX >= (winX + winW) Or mouseY < winY Or mouseY >= (winY + winH) Then
            HitTestWindow = HIT_NONE
            Exit Function
        End If

        ' Titlebar area hit testing
        If mouseY < (winY + TITLEBAR_HEIGHT) Then
            ' Close button: (winX + winW) - 22 .. (winX + winW) - 12, winY + 8 .. winY + 18
            Dim closeX As Int32 = (winX + winW) - 22
            If mouseX >= closeX And mouseX < (closeX + BUTTON_W) And _
               mouseY >= (winY + BUTTON_Y_OFFSET) And mouseY < (winY + BUTTON_Y_OFFSET + BUTTON_H) Then
                HitTestWindow = HIT_BTN_CLOSE
                Exit Function
            End If

            ' Maximize button: (winX + winW) - 38 .. (winX + winW) - 28
            Dim maxX As Int32 = (winX + winW) - 38
            If mouseX >= maxX And mouseX < (maxX + BUTTON_W) And _
               mouseY >= (winY + BUTTON_Y_OFFSET) And mouseY < (winY + BUTTON_Y_OFFSET + BUTTON_H) Then
                HitTestWindow = HIT_BTN_MAX
                Exit Function
            End If

            ' Minimize button: (winX + winW) - 54 .. (winX + winW) - 44
            Dim minX As Int32 = (winX + winW) - 54
            If mouseX >= minX And mouseX < (minX + BUTTON_W) And _
               mouseY >= (winY + BUTTON_Y_OFFSET) And mouseY < (winY + BUTTON_Y_OFFSET + BUTTON_H) Then
                HitTestWindow = HIT_BTN_MIN
                Exit Function
            End If

            HitTestWindow = HIT_TITLEBAR
            Exit Function
        End If

        ' Bottom-Right resize handle
        If mouseX >= ((winX + winW) - RESIZE_HANDLE_SIZE) And mouseY >= ((winY + winH) - RESIZE_HANDLE_SIZE) Then
            HitTestWindow = HIT_RESIZE_BR
            Exit Function
        End If

        ' Window border edges (East-West and North-South resize triggers)
        If mouseX < (winX + 4) Or mouseX >= ((winX + winW) - 4) Then
            HitTestWindow = HIT_BORDER_EW
            Exit Function
        End If
        If mouseY >= ((winY + winH) - 4) Then
            HitTestWindow = HIT_BORDER_NS
            Exit Function
        End If

        ' Otherwise within window client area
        HitTestWindow = HIT_CLIENT
    End Function

    ''
    ' @brief Draw a 10x10 monochrome bitmask glyph onto target surface.
    ''
    Public Unsafe Sub DrawGlyph10x10(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal pMask As Pointer To UInt16, ByVal color As UInt32)
        If surf.Pixels = 0 Or pMask = 0 Then Exit Sub
        Dim row As Int32 = 0
        While row < 10
            Dim py As Int32 = y + row
            If py >= 0 And py < surf.Height Then
                Dim mask As UInt16 = pMask(row)
                Dim col As Int32 = 0
                While col < 10
                    Dim px As Int32 = x + col
                    If px >= 0 And px < surf.Width Then
                        If (mask And (UInt16(1) LShift col)) <> 0 Then
                            Dim pitchPix As UInt32 = surf.Pitch / 4
                            Dim rowPtr As Pointer To UInt32 = surf.Pixels + (UInt32(py) * pitchPix)
                            rowPtr(px) = color
                        End If
                    End If
                    col = col + 1
                Wend
            End If
            row = row + 1
        Wend
    End Sub

    ''
    ' @brief Draw bottom-right resize gripper corner.
    ''
    Public Unsafe Sub DrawResizeGripper(ByRef surf As Surface, ByVal winX As Int32, ByVal winY As Int32, ByVal winW As Int32, ByVal winH As Int32, ByVal color As UInt32)
        If surf.Pixels = 0 Then Exit Sub
        Dim pitchPix As UInt32 = surf.Pitch / 4
        Dim right As Int32 = winX + winW
        Dim bottom As Int32 = winY + winH

        ' 3 diagonal ticks
        Dim d As Int32 = 3
        While d <= 9
            Dim i As Int32 = 0
            While i <= d
                Dim px As Int32 = (right - 2) - (d - i)
                Dim py As Int32 = (bottom - 2) - i
                If px >= 0 And px < surf.Width And py >= 0 And py < surf.Height Then
                    Dim rowPtr As Pointer To UInt32 = surf.Pixels + (UInt32(py) * pitchPix)
                    rowPtr(px) = color
                End If
                i = i + 1
            Wend
            d = d + 3
        Wend
    End Sub

    ''
    ' @brief Render complete window frame decorations (shadow, frame, titlebar, accent, buttons, gripper).
    ' @param surf Target rendering surface (RAM backbuffer).
    ' @param x Window X position.
    ' @param y Window Y position.
    ' @param w Window width.
    ' @param h Window height.
    ' @param focused True if window holds active input focus.
    ' @param state Normal (0), Minimized (1), Maximized (2).
    ' @param hoverHit Active hovered button (HIT_BTN_CLOSE, HIT_BTN_MAX, HIT_BTN_MIN, or 0).
    ''
    Public Unsafe Sub DrawWindowFrame(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, _
                                      ByVal w As Int32, ByVal h As Int32, _
                                      ByVal focused As Boolean, ByVal state As Int32, _
                                      ByVal hoverHit As UInt32)
        If surf.Pixels = 0 Then Exit Sub
        If state = WIN_STATE_MINIMIZED Then Exit Sub

        ' 1. Outer drop-shadow (only for non-maximized floating windows)
        If state = WIN_STATE_NORMAL Then
            FillRect surf, x + SHADOW_OFFSET, y + SHADOW_OFFSET, w, h, COLOR_WIN_SHADOW
        End If

        ' 2. Window Frame Border
        Dim borderColor As UInt32
        Dim titleBgColor As UInt32
        Dim accentColor As UInt32

        If focused Then
            borderColor = COLOR_WIN_ACTIVE_BORDER
            titleBgColor = COLOR_WIN_ACTIVE_TITLEBAR
            accentColor = COLOR_WIN_ACTIVE_ACCENT
        Else
            borderColor = COLOR_WIN_INACTIVE_BORDER
            titleBgColor = COLOR_WIN_INACTIVE_TITLEBAR
            accentColor = COLOR_WIN_INACTIVE_ACCENT
        End If

        FillRect surf, x, y, w, h, borderColor
        FillRect surf, x + 1, y + 1, w - 2, h - 2, titleBgColor

        ' 3. Titlebar (height: TITLEBAR_HEIGHT)
        FillRect surf, x + 1, y + 1, w - 2, TITLEBAR_HEIGHT, titleBgColor

        ' 4. Titlebar Accent Indicator (left edge)
        FillRect surf, x + 1, y + 1, 4, TITLEBAR_HEIGHT, accentColor

        ' 5. Window Buttons (Minimize, Maximize/Restore, Close)
        Dim minBtnX As Int32 = (x + w) - 54
        Dim maxBtnX As Int32 = (x + w) - 38
        Dim closeBtnX As Int32 = (x + w) - 22
        Dim btnY As Int32 = y + BUTTON_Y_OFFSET

        ' Minimize Button
        Dim minColor As UInt32 = COLOR_BTN_MIN_NORMAL
        If hoverHit = HIT_BTN_MIN Then minColor = COLOR_BTN_MIN_HOVER
        FillRect surf, minBtnX, btnY, BUTTON_W, BUTTON_H, minColor

        ' Maximize / Restore Button
        Dim maxColor As UInt32 = COLOR_BTN_MAX_NORMAL
        If hoverHit = HIT_BTN_MAX Then maxColor = COLOR_BTN_MAX_HOVER
        FillRect surf, maxBtnX, btnY, BUTTON_W, BUTTON_H, maxColor

        ' Close Button
        Dim closeColor As UInt32 = COLOR_BTN_CLOSE_NORMAL
        If hoverHit = HIT_BTN_CLOSE Then closeColor = COLOR_BTN_CLOSE_HOVER
        FillRect surf, closeBtnX, btnY, BUTTON_W, BUTTON_H, closeColor

        ' 6. Window Client Canvas Area
        FillRect surf, x + 2, y + TITLEBAR_HEIGHT + 2, w - 4, (h - TITLEBAR_HEIGHT) - 4, COLOR_WIN_CLIENT_BG

        ' 7. Bottom-Right Resize Gripper (only in normal state)
        If state = WIN_STATE_NORMAL Then
            DrawResizeGripper surf, x, y, w, h, COLOR_RESIZE_GRIPPER
        End If
    End Sub

End Module
