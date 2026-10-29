' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/Font8x16.bas
' Summary: 8x16 bitmap font interface and US keyboard scancode maps.

Namespace Drivers

    Public Module Font8x16

        ' External reference to 2048-byte font bitmap table in Font8x16_data.S
        Extern font_8x16_data As Byte

        ''
        ' @brief Retrieve a specific row bitmask (8 bits wide) for an ASCII glyph.
        ' @param asciiCode ASCII character code (0 to 127).
        ' @param row       Row index within the glyph (0 to 15).
        ' @return Byte bitmask where set bits represent active foreground pixels.
        ''
        Public Unsafe Function GetGlyphByte(ByVal asciiCode As UInt32, ByVal row As UInt32) As Byte
            If asciiCode >= 128 Or row >= 16 Then
                GetGlyphByte = 0
                Exit Function
            End If

            Dim fontBase As Pointer To Byte = 0
            Asm "movabs $font_8x16_data, %0" : "=r"(fontBase) : : "memory"
            Dim offset As UInt64 = (CType(UInt64, asciiCode) * 16) + CType(UInt64, row)
            GetGlyphByte = fontBase(offset)
        End Function

    End Module

End Namespace
