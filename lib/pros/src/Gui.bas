' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Gui.bas
' Summary: Low-Level Basic GUI, Surface, and Theme primitives.

Namespace Pros.Gui

    ' Nord / Dark System Theme Palette
    Public Const COLOR_BG            As UInt32 = &HFF191D24
    Public Const COLOR_SURFACE       As UInt32 = &HFF232731
    Public Const COLOR_TITLEBAR      As UInt32 = &HFF2E3440
    Public Const COLOR_ACCENT        As UInt32 = &HFF56B6C2
    Public Const COLOR_BORDER_TOP    As UInt32 = &HFF4C566A
    Public Const COLOR_BORDER_BOTTOM As UInt32 = &HFF1B2028
    Public Const COLOR_TEXT          As UInt32 = &HFFD8DEE9
    Public Const COLOR_BTN_CLOSE     As UInt32 = &HFFBF616A
    Public Const COLOR_BTN_MAX       As UInt32 = &HFF00C853
    Public Const COLOR_BTN_MIN       As UInt32 = &HFF5E81AC

    <Packed>
    Public Structure Surface
        Public Width     As UInt32
        Public Height    As UInt32
        Public Pitch     As UInt32
        Public Bpp       As UInt32
        Public Pixels    As Pointer To UInt32
    End Structure

    Public Module Graphics

        ''
        ' @brief Fill a rectangular region with solid ARGB color.
        ''
        Public Unsafe Sub FillRect(ByRef surf As Surface, ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32, ByVal color As UInt32)
            If rw <= 0 Or rh <= 0 Then Exit Sub
            If surf.Pixels = 0 Then Exit Sub

            Dim x0 As Int32 = rx
            Dim y0 As Int32 = ry
            Dim x1 As Int32 = rx + rw
            Dim y1 As Int32 = ry + rh

            If x0 < 0 Then x0 = 0
            If y0 < 0 Then y0 = 0
            If x1 > CType(Int32, surf.Width) Then x1 = CType(Int32, surf.Width)
            If y1 > CType(Int32, surf.Height) Then y1 = CType(Int32, surf.Height)

            If x0 >= x1 Or y0 >= y1 Then Exit Sub

            Dim pitchPixels As UInt32 = surf.Pitch / 4
            Dim py As Int32 = y0
            While py < y1
                Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, py) * pitchPixels)
                Dim px As Int32 = x0
                While px < x1
                    rowPtr(px) = color
                    px = px + 1
                Wend
                py = py + 1
            Wend
        End Sub

        ''
        ' @brief Fast 32bpp block transfer (blit) from source surface to destination.
        ''
        Public Unsafe Sub Blit(ByRef dst As Surface, ByVal dx As Int32, ByVal dy As Int32, _
                               ByRef src As Surface, ByVal sx As Int32, ByVal sy As Int32, _
                               ByVal w As Int32, ByVal h As Int32)
            If w <= 0 Or h <= 0 Then Exit Sub
            If dst.Pixels = 0 Or src.Pixels = 0 Then Exit Sub

            Dim dstPitchPixels As UInt32 = dst.Pitch / 4
            Dim srcPitchPixels As UInt32 = src.Pitch / 4

            Dim row As Int32 = 0
            While row < h
                Dim curDy As Int32 = dy + row
                Dim curSy As Int32 = sy + row
                If curDy >= 0 And curDy < CType(Int32, dst.Height) And curSy >= 0 And curSy < CType(Int32, src.Height) Then
                    Dim dstRow As Pointer To UInt32 = dst.Pixels + (CType(UInt32, curDy) * dstPitchPixels)
                    Dim srcRow As Pointer To UInt32 = src.Pixels + (CType(UInt32, curSy) * srcPitchPixels)

                    Dim col As Int32 = 0
                    While col < w
                        Dim curDx As Int32 = dx + col
                        Dim curSx As Int32 = sx + col
                        If curDx >= 0 And curDx < CType(Int32, dst.Width) And curSx >= 0 And curSx < CType(Int32, src.Width) Then
                            dstRow(curDx) = srcRow(curSx)
                        End If
                        col = col + 1
                    Wend
                End If
                row = row + 1
            Wend
        End Sub

    End Module

End Namespace
