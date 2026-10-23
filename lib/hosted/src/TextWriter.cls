' Project Name: LibLLB / Low-Level Basic
' Filename: lib/hosted/src/TextWriter.cls
' Summary: Stream text writer wrapping any ICharSink implementation in hosted runtime.

Import Format

<Instancing(MultiUse)>
Public Class TextWriter

    Private m_sink As Pointer To ICharSink

    ''
    ' @brief Attaches the writer to an ICharSink stream destination.
    ' @param sink Pointer to ICharSink implementation.
    ''
    Public Unsafe Sub Attach(ByVal sink As Pointer To ICharSink)
        m_sink = sink
    End Sub

    ''
    ' @brief Writes a single character to the attached sink.
    ' @param c Character byte.
    ''
    Public Unsafe Sub WriteChar(ByVal c As Byte)
        If m_sink <> 0 Then
            m_sink.WriteChar c
        End If
    End Sub

    ''
    ' @brief Writes a null-terminated string to the attached sink.
    ' @param str Pointer to null-terminated string.
    ''
    Public Unsafe Sub Write(ByVal str As Pointer To Byte)
        If m_sink <> 0 Then
            m_sink.WriteString str
        End If
    End Sub

    ''
    ' @brief Writes a null-terminated string followed by a newline (0x0A) character.
    ' @param str Pointer to null-terminated string.
    ''
    Public Unsafe Sub WriteLine(ByVal str As Pointer To Byte)
        Write str
        WriteChar 10
    End Sub

    ''
    ' @brief Writes an unsigned 64-bit integer as a base-10 decimal string.
    ' @param value Unsigned 64-bit integer.
    ''
    Public Unsafe Sub WriteUInt(ByVal value As UInt64)
        Dim buf(24) As Byte
        Format.ToUInt value, CPtr(Pointer To Byte, buf)
        Write CPtr(Pointer To Byte, buf)
    End Sub

    ''
    ' @brief Writes a signed 64-bit integer as a base-10 decimal string.
    ' @param value Signed 64-bit integer.
    ''
    Public Unsafe Sub WriteInt(ByVal value As Int64)
        Dim buf(24) As Byte
        Format.ToInt value, CPtr(Pointer To Byte, buf)
        Write CPtr(Pointer To Byte, buf)
    End Sub

    ''
    ' @brief Writes an unsigned 64-bit integer in hexadecimal format.
    ' @param value Unsigned 64-bit integer.
    ' @param prefix True to prepend "0x".
    ''
    Public Unsafe Sub WriteHex(ByVal value As UInt64, ByVal prefix As Boolean)
        Dim buf(24) As Byte
        Format.ToHex value, CPtr(Pointer To Byte, buf), prefix
        Write CPtr(Pointer To Byte, buf)
    End Sub

    ''
    ' @brief Writes formatted string to the attached sink (printf-equivalent).
    ' @param fmt Pointer to null-terminated format string (%s, %u, %d, %x, %c, %%).
    ' @param args Variadic format arguments.
    ''
    Public Unsafe Sub PrintF(ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64)
        Dim outBuf(256) As Byte
        Dim outPtr As Pointer To Byte = CPtr(Pointer To Byte, outBuf)
        Format.SprintF outPtr, 256, fmt, args
        Write outPtr
    End Sub

End Class
