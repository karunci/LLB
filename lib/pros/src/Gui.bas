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
        Public Width     As Int32
        Public Height    As Int32
        Public Pitch     As UInt32
        Public Bpp       As UInt32
        Public Pixels    As Pointer To UInt32
    End Structure

    Public Module Graphics

        Public Declare Sub fast_fill32(ByVal dst As Pointer To UInt32, ByVal color As UInt32, ByVal count As UInt64)

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
            If x1 > surf.Width Then x1 = surf.Width
            If y1 > surf.Height Then y1 = surf.Height

            If x0 >= x1 Or y0 >= y1 Then Exit Sub

            Dim py As Int32
            Dim px As Int32

            If surf.Bpp = 24 Then
                Dim b0 As Byte = Byte(color And &HFF)
                Dim b1 As Byte = Byte((color RShift 8) And &HFF)
                Dim b2 As Byte = Byte((color RShift 16) And &HFF)
                py = y0
                While py < y1
                    Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, surf.Pixels) + (UInt32(py) * surf.Pitch)
                    px = x0
                    While px < x1
                        Dim byteOffset As UInt32 = UInt32(px) * 3
                        rawRow(byteOffset) = b0
                        rawRow(byteOffset + 1) = b1
                        rawRow(byteOffset + 2) = b2
                        px = px + 1
                    Wend
                    py = py + 1
                Wend
            Else
                Dim pitchPixels As UInt32 = surf.Pitch / 4
                Dim lineLen As UInt64 = UInt64(x1 - x0)
                py = y0
                While py < y1
                    Dim rowPtr As Pointer To UInt32 = surf.Pixels + (UInt32(py) * pitchPixels) + UInt32(x0)
                    fast_fill32 rowPtr, color, lineLen
                    py = py + 1
                Wend
            End If
        End Sub

        ''
        ' @brief Fast 24/32bpp block transfer (blit) from source surface to destination.
        ''
        Public Unsafe Sub Blit(ByRef dst As Surface, ByVal dx As Int32, ByVal dy As Int32, _
                               ByRef src As Surface, ByVal sx As Int32, ByVal sy As Int32, _
                               ByVal w As Int32, ByVal h As Int32)
            If w <= 0 Or h <= 0 Then Exit Sub
            If dst.Pixels = 0 Or src.Pixels = 0 Then Exit Sub

            Dim row As Int32 = 0
            Dim col As Int32 = 0
            Dim curDy As Int32 = 0
            Dim curSy As Int32 = 0
            Dim curDx As Int32 = 0
            Dim curSx As Int32 = 0

            If dst.Bpp = 24 And src.Bpp = 24 Then
                row = 0
                While row < h
                    curDy = dy + row
                    curSy = sy + row
                    If curDy >= 0 And curDy < dst.Height And curSy >= 0 And curSy < src.Height Then
                        Dim dstRaw As Pointer To Byte = CPtr(Pointer To Byte, dst.Pixels) + (UInt32(curDy) * dst.Pitch)
                        Dim srcRaw As Pointer To Byte = CPtr(Pointer To Byte, src.Pixels) + (UInt32(curSy) * src.Pitch)
                        col = 0
                        While col < w
                            curDx = dx + col
                            curSx = sx + col
                            If curDx >= 0 And curDx < dst.Width And curSx >= 0 And curSx < src.Width Then
                                Dim dOff As UInt32 = UInt32(curDx) * 3
                                Dim sOff As UInt32 = UInt32(curSx) * 3
                                dstRaw(dOff) = srcRaw(sOff)
                                dstRaw(dOff + 1) = srcRaw(sOff + 1)
                                dstRaw(dOff + 2) = srcRaw(sOff + 2)
                            End If
                            col = col + 1
                        Wend
                    End If
                    row = row + 1
                Wend
            Else
                Dim dstPitchPixels As UInt32 = dst.Pitch / 4
                Dim srcPitchPixels As UInt32 = src.Pitch / 4

                row = 0
                While row < h
                    curDy = dy + row
                    curSy = sy + row
                    If curDy >= 0 And curDy < dst.Height And curSy >= 0 And curSy < src.Height Then
                        Dim dstRow As Pointer To UInt32 = dst.Pixels + (UInt32(curDy) * dstPitchPixels)
                        Dim srcRow As Pointer To UInt32 = src.Pixels + (UInt32(curSy) * srcPitchPixels)
                        col = 0
                        While col < w
                            curDx = dx + col
                            curSx = sx + col
                            If curDx >= 0 And curDx < dst.Width And curSx >= 0 And curSx < src.Width Then
                                dstRow(curDx) = srcRow(curSx)
                            End If
                            col = col + 1
                        Wend
                    End If
                    row = row + 1
                Wend
            End If
        End Sub

    End Module

End Namespace
