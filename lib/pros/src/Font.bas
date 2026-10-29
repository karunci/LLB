' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: lib/pros/src/Font.bas
' Summary: Low-Level Basic font tables and universal text rendering engine (5x7 and 8x16).

Import Pros.Gui

Namespace Pros.Drawing

    Public Module FontRenderer

        ' =========================================================================
        ' 1. Standard 5x7 ASCII Bitmap Font Table (ASCII 32 ' ' to 126 '~')
        '    95 characters x 7 rows = 665 bytes total in .rodata.
        '    Active foreground pixels are set bits. Bit 4 (16) is column 0 (left),
        '    Bit 0 (1) is column 4 (right).
        ' =========================================================================
        Private Const FONT_5X7(665) As Byte = { _
            0, 0, 0, 0, 0, 0, 0, _                         ' 32 ' '
            4, 4, 4, 4, 4, 0, 4, _                         ' 33 '!'
            10, 10, 10, 0, 0, 0, 0, _                      ' 34 '"'
            10, 10, 31, 10, 31, 10, 10, _                  ' 35 '#'
            4, 15, 20, 14, 5, 30, 4, _                     ' 36 '$'
            25, 25, 2, 4, 8, 19, 19, _                     ' 37 '%'
            12, 18, 20, 8, 21, 18, 13, _                   ' 38 '&'
            12, 12, 8, 0, 0, 0, 0, _                       ' 39 '\''
            2, 4, 8, 8, 8, 4, 2, _                         ' 40 '('
            8, 4, 2, 2, 2, 4, 8, _                         ' 41 ')'
            0, 4, 21, 14, 21, 4, 0, _                      ' 42 '*'
            0, 4, 4, 31, 4, 4, 0, _                        ' 43 '+'
            0, 0, 0, 0, 12, 12, 8, _                       ' 44 ','
            0, 0, 0, 31, 0, 0, 0, _                        ' 45 '-'
            0, 0, 0, 0, 0, 12, 12, _                       ' 46 '.'
            1, 2, 4, 8, 16, 0, 0, _                        ' 47 '/'
            14, 17, 19, 21, 25, 17, 14, _                  ' 48 '0'
            4, 12, 4, 4, 4, 4, 14, _                       ' 49 '1'
            14, 17, 1, 6, 8, 16, 31, _                     ' 50 '2'
            30, 1, 1, 14, 1, 1, 30, _                      ' 51 '3'
            2, 6, 10, 18, 31, 2, 2, _                      ' 52 '4'
            31, 16, 30, 1, 1, 17, 14, _                    ' 53 '5'
            14, 16, 16, 30, 17, 17, 14, _                  ' 54 '6'
            31, 1, 2, 4, 8, 8, 8, _                        ' 55 '7'
            14, 17, 17, 14, 17, 17, 14, _                  ' 56 '8'
            14, 17, 17, 15, 1, 1, 14, _                    ' 57 '9'
            0, 12, 12, 0, 12, 12, 0, _                     ' 58 ':'
            0, 12, 12, 0, 12, 12, 8, _                     ' 59 ';'
            2, 4, 8, 16, 8, 4, 2, _                        ' 60 '<'
            0, 31, 0, 31, 0, 0, 0, _                       ' 61 '='
            16, 8, 4, 2, 4, 8, 16, _                       ' 62 '>'
            14, 17, 1, 2, 4, 0, 4, _                       ' 63 '?'
            14, 17, 1, 29, 21, 21, 14, _                   ' 64 '@'
            14, 17, 17, 31, 17, 17, 17, _                  ' 65 'A'
            30, 17, 17, 30, 17, 17, 30, _                  ' 66 'B'
            14, 17, 16, 16, 16, 17, 14, _                  ' 67 'C'
            28, 18, 17, 17, 17, 18, 28, _                  ' 68 'D'
            31, 16, 16, 30, 16, 16, 31, _                  ' 69 'E'
            31, 16, 16, 30, 16, 16, 16, _                  ' 70 'F'
            14, 17, 16, 23, 17, 17, 14, _                  ' 71 'G'
            17, 17, 17, 31, 17, 17, 17, _                  ' 72 'H'
            14, 4, 4, 4, 4, 4, 14, _                       ' 73 'I'
            7, 2, 2, 2, 2, 18, 12, _                       ' 74 'J'
            17, 18, 20, 24, 20, 18, 17, _                  ' 75 'K'
            16, 16, 16, 16, 16, 16, 31, _                  ' 76 'L'
            17, 27, 21, 21, 17, 17, 17, _                  ' 77 'M'
            17, 25, 21, 19, 17, 17, 17, _                  ' 78 'N'
            14, 17, 17, 17, 17, 17, 14, _                  ' 79 'O'
            30, 17, 17, 30, 16, 16, 16, _                  ' 80 'P'
            14, 17, 17, 17, 21, 18, 13, _                  ' 81 'Q'
            30, 17, 17, 30, 20, 18, 17, _                  ' 82 'R'
            15, 16, 16, 14, 1, 1, 30, _                    ' 83 'S'
            31, 4, 4, 4, 4, 4, 4, _                        ' 84 'T'
            17, 17, 17, 17, 17, 17, 14, _                  ' 85 'U'
            17, 17, 17, 17, 10, 10, 4, _                   ' 86 'V'
            17, 17, 21, 21, 21, 21, 10, _                  ' 87 'W'
            17, 10, 4, 4, 4, 10, 17, _                     ' 88 'X'
            17, 17, 17, 10, 4, 4, 4, _                     ' 89 'Y'
            31, 1, 2, 4, 8, 16, 31, _                      ' 90 'Z'
            14, 8, 8, 8, 8, 8, 14, _                       ' 91 '['
            16, 16, 8, 4, 2, 1, 1, _                       ' 92 '\'
            14, 2, 2, 2, 2, 2, 14, _                       ' 93 ']'
            4, 10, 17, 0, 0, 0, 0, _                       ' 94 '^'
            0, 0, 0, 0, 0, 0, 31, _                        ' 95 '_'
            8, 4, 0, 0, 0, 0, 0, _                         ' 96 '`'
            0, 0, 14, 1, 15, 17, 15, _                     ' 97 'a'
            16, 16, 22, 25, 17, 17, 30, _                  ' 98 'b'
            0, 0, 14, 17, 16, 17, 14, _                    ' 99 'c'
            1, 1, 13, 19, 17, 17, 15, _                    ' 100 'd'
            0, 0, 14, 17, 31, 16, 14, _                    ' 101 'e'
            6, 9, 8, 28, 8, 8, 8, _                        ' 102 'f'
            0, 15, 17, 17, 15, 1, 14, _                    ' 103 'g'
            16, 16, 22, 25, 17, 17, 17, _                  ' 104 'h'
            4, 0, 12, 4, 4, 4, 14, _                       ' 105 'i'
            2, 0, 6, 2, 2, 18, 12, _                       ' 106 'j'
            16, 16, 18, 20, 24, 20, 18, _                  ' 107 'k'
            12, 4, 4, 4, 4, 4, 14, _                       ' 108 'l'
            0, 0, 26, 21, 21, 17, 17, _                    ' 109 'm'
            0, 0, 22, 25, 17, 17, 17, _                    ' 110 'n'
            0, 0, 14, 17, 17, 17, 14, _                    ' 111 'o'
            0, 0, 30, 17, 30, 16, 16, _                    ' 112 'p'
            0, 0, 15, 17, 15, 1, 1, _                      ' 113 'q'
            0, 0, 22, 25, 16, 16, 16, _                    ' 114 'r'
            0, 0, 15, 16, 14, 1, 30, _                     ' 115 's'
            8, 8, 28, 8, 8, 9, 6, _                        ' 116 't'
            0, 0, 17, 17, 17, 19, 13, _                    ' 117 'u'
            0, 0, 17, 17, 17, 10, 4, _                     ' 118 'v'
            0, 0, 17, 17, 21, 21, 10, _                    ' 119 'w'
            0, 0, 17, 10, 4, 10, 17, _                     ' 120 'x'
            0, 0, 17, 17, 15, 1, 14, _                     ' 121 'y'
            0, 0, 31, 2, 4, 8, 31, _                       ' 122 'z'
            2, 4, 4, 8, 4, 4, 2, _                         ' 123 '{'
            4, 4, 4, 4, 4, 4, 4, _                         ' 124 '|'
            8, 4, 4, 2, 4, 4, 8, _                         ' 125 '}'
            0, 8, 21, 2, 0, 0, 0 _                         ' 126 '~'
        }

        ' =========================================================================
        ' 2. Font Reference Helpers
        ' =========================================================================
        ''
        ' @brief Retrieve the base pointer to the 5x7 font table in .rodata.
        ' @return Pointer to 5x7 font table.
        ''
        Private Unsafe Function GetFont5x7Base() As Pointer To Byte
            GetFont5x7Base = CPtr(Pointer To Byte, AddressOf FONT_5X7)
        End Function

        ''
        ' @brief Retrieve the base pointer to the 2048-byte 8x16 console font table in lib/runtime/font_8x16.S.
        ' @return Pointer to 8x16 bitmap font table in .rodata.
        ''
        Private Unsafe Function GetFont8x16Base() As Pointer To Byte
            Dim fontBase As Pointer To Byte = 0
            Asm "movabs $font_8x16_data, %0" : "=r"(fontBase) : : "memory"
            GetFont8x16Base = fontBase
        End Function

        ' =========================================================================
        ' 3. Font Rendering Procedures
        ' =========================================================================

        ''
        ' @brief Render a single 5x7 ASCII character glyph onto the target Surface with boundary clipping.
        ' @param surf Surface to render into.
        ' @param gx Top-left X coordinate on surface.
        ' @param gy Top-left Y coordinate on surface.
        ' @param ascii ASCII character byte (32..126).
        ' @param color 32-bit ARGB foreground color.
        ''
        Public Unsafe Sub DrawGlyph5x7(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
            If surf.Pixels = 0 Then Exit Sub
            If surf.Width = 0 Or surf.Height = 0 Then Exit Sub

            ' Complete off-screen clipping
            If gx + 5 <= 0 Or gx >= CType(Int32, surf.Width) Then Exit Sub
            If gy + 7 <= 0 Or gy >= CType(Int32, surf.Height) Then Exit Sub

            Dim uAscii As UInt32 = CType(UInt32, ascii)
            If uAscii < 32 Or uAscii > 126 Then Exit Sub

            Dim font5x7 As Pointer To Byte = GetFont5x7Base()
            If font5x7 = 0 Then Exit Sub

            Dim baseOffset As UInt32 = (uAscii - 32) * 7
            Dim is24bpp As Boolean = (surf.Bpp = 24)
            Dim pitchPix As UInt32 = surf.Pitch / 4

            Dim b0 As Byte = 0
            Dim b1 As Byte = 0
            Dim b2 As Byte = 0
            If is24bpp Then
                b0 = CType(Byte, color And &HFF)
                b1 = CType(Byte, (color RShift 8) And &HFF)
                b2 = CType(Byte, (color RShift 16) And &HFF)
            End If

            Dim r As Int32 = 0
            While r < 7
                Dim py As Int32 = gy + r
                If py >= 0 And py < CType(Int32, surf.Height) Then
                    Dim rowVal As Byte = font5x7(baseOffset + CType(UInt32, r))
                    If rowVal <> 0 Then
                        Dim c As Int32 = 0
                        While c < 5
                            Dim px As Int32 = gx + c
                            If px >= 0 And px < CType(Int32, surf.Width) Then
                                Dim bitMask As Byte = CType(Byte, 16 RShift c)
                                If (rowVal And bitMask) <> 0 Then
                                    If is24bpp Then
                                        Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, surf.Pixels) + (CType(UInt32, py) * surf.Pitch)
                                        Dim byteOffset As UInt32 = CType(UInt32, px) * 3
                                        rawRow(byteOffset) = b0
                                        rawRow(byteOffset + 1) = b1
                                        rawRow(byteOffset + 2) = b2
                                    Else
                                        Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, py) * pitchPix)
                                        rowPtr(px) = color
                                    End If
                                End If
                            End If
                            c = c + 1
                        Wend
                    End If
                End If
                r = r + 1
            Wend
        End Sub

        ''
        ' @brief Render null-terminated ASCII text string in 5x7 font onto target Surface.
        ' @param surf Target Surface.
        ' @param x Starting X coordinate.
        ' @param y Starting Y coordinate.
        ' @param textPtr Pointer to null-terminated ASCII string.
        ' @param color 32-bit ARGB foreground color.
        ''
        Public Unsafe Sub DrawText5x7(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)
            If surf.Pixels = 0 Or textPtr = 0 Then Exit Sub
            Dim cx As Int32 = x
            Dim i As UInt32 = 0
            While textPtr(i) <> 0
                DrawGlyph5x7 surf, cx, y, textPtr(i), color
                cx = cx + 6
                i = i + 1
            Wend
        End Sub

        ''
        ' @brief Render a single 8x16 ASCII character glyph onto target Surface referencing lib/runtime/font_8x16.S.
        ' @param surf Surface to render into.
        ' @param gx Top-left X coordinate on surface.
        ' @param gy Top-left Y coordinate on surface.
        ' @param ascii ASCII character byte (0..127).
        ' @param color 32-bit ARGB foreground color.
        ''
        Public Unsafe Sub DrawGlyph8x16(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32)
            If surf.Pixels = 0 Then Exit Sub
            If surf.Width = 0 Or surf.Height = 0 Then Exit Sub
            If gx + 8 <= 0 Or gx >= CType(Int32, surf.Width) Then Exit Sub
            If gy + 16 <= 0 Or gy >= CType(Int32, surf.Height) Then Exit Sub
            If ascii > 127 Then Exit Sub

            Dim fontBase As Pointer To Byte = GetFont8x16Base()
            If fontBase = 0 Then Exit Sub

            Dim baseOffset As UInt64 = CType(UInt64, ascii) * 16
            Dim is24bpp As Boolean = (surf.Bpp = 24)
            Dim pitchPix As UInt32 = surf.Pitch / 4

            Dim b0 As Byte = 0
            Dim b1 As Byte = 0
            Dim b2 As Byte = 0
            If is24bpp Then
                b0 = CType(Byte, color And &HFF)
                b1 = CType(Byte, (color RShift 8) And &HFF)
                b2 = CType(Byte, (color RShift 16) And &HFF)
            End If

            Dim r As Int32 = 0
            While r < 16
                Dim py As Int32 = gy + r
                If py >= 0 And py < CType(Int32, surf.Height) Then
                    Dim rowVal As Byte = fontBase(baseOffset + CType(UInt64, r))
                    If rowVal <> 0 Then
                        Dim c As Int32 = 0
                        While c < 8
                            Dim px As Int32 = gx + c
                            If px >= 0 And px < CType(Int32, surf.Width) Then
                                Dim bitMask As Byte = CType(Byte, &H80 RShift c)
                                If (rowVal And bitMask) <> 0 Then
                                    If is24bpp Then
                                        Dim rawRow As Pointer To Byte = CPtr(Pointer To Byte, surf.Pixels) + (CType(UInt32, py) * surf.Pitch)
                                        Dim byteOffset As UInt32 = CType(UInt32, px) * 3
                                        rawRow(byteOffset) = b0
                                        rawRow(byteOffset + 1) = b1
                                        rawRow(byteOffset + 2) = b2
                                    Else
                                        Dim rowPtr As Pointer To UInt32 = surf.Pixels + (CType(UInt32, py) * pitchPix)
                                        rowPtr(px) = color
                                    End If
                                End If
                            End If
                            c = c + 1
                        Wend
                    End If
                End If
                r = r + 1
            Wend
        End Sub

        ''
        ' @brief Render null-terminated ASCII text string in 8x16 font onto target Surface.
        ' @param surf Target Surface.
        ' @param x Starting X coordinate.
        ' @param y Starting Y coordinate.
        ' @param textPtr Pointer to null-terminated ASCII string.
        ' @param color 32-bit ARGB foreground color.
        ''
        Public Unsafe Sub DrawText8x16(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32)
            If surf.Pixels = 0 Or textPtr = 0 Then Exit Sub
            Dim cx As Int32 = x
            Dim i As UInt32 = 0
            While textPtr(i) <> 0
                DrawGlyph8x16 surf, cx, y, textPtr(i), color
                cx = cx + 8
                i = i + 1
            Wend
        End Sub

        ''
        ' @brief Generic character glyph rendering routine selecting between 5x7 and 8x16 font.
        ' @param surf Target Surface.
        ' @param gx Top-left X coordinate.
        ' @param gy Top-left Y coordinate.
        ' @param ascii Character byte.
        ' @param color 32-bit ARGB foreground color.
        ' @param useLargeFont True for 8x16 console font, False for 5x7 compact font.
        ''
        Public Unsafe Sub DrawGlyph(ByRef surf As Surface, ByVal gx As Int32, ByVal gy As Int32, ByVal ascii As Byte, ByVal color As UInt32, ByVal useLargeFont As Boolean = False)
            If useLargeFont Then
                DrawGlyph8x16 surf, gx, gy, ascii, color
            Else
                DrawGlyph5x7 surf, gx, gy, ascii, color
            End If
        End Sub

        ''
        ' @brief Generic string rendering routine selecting between 5x7 and 8x16 font.
        ' @param surf Target Surface.
        ' @param x Starting X coordinate.
        ' @param y Starting Y coordinate.
        ' @param textPtr Pointer to null-terminated ASCII string.
        ' @param color 32-bit ARGB foreground color.
        ' @param useLargeFont True for 8x16 console font, False for 5x7 compact font.
        ''
        Public Unsafe Sub DrawText(ByRef surf As Surface, ByVal x As Int32, ByVal y As Int32, ByVal textPtr As Pointer To Byte, ByVal color As UInt32, ByVal useLargeFont As Boolean = False)
            If useLargeFont Then
                DrawText8x16 surf, x, y, textPtr, color
            Else
                DrawText5x7 surf, x, y, textPtr, color
            End If
        End Sub

    End Module

End Namespace
