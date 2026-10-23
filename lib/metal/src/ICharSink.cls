' Project Name: LibLLB_Metal / Low-Level Basic
' Filename: lib/metal/src/ICharSink.cls
' Summary: Stream destination interface for character and string emission.

<Interface>
Public Interface ICharSink
    ''
    ' @brief Emit a single byte character to the sink.
    ' @param c ASCII or raw byte to write.
    ''
    Sub WriteChar(ByVal c As Byte)

    ''
    ' @brief Emit a null-terminated string to the sink.
    ' @param str Pointer to null-terminated ASCII/UTF-8 buffer.
    ''
    Sub WriteString(ByVal str As Pointer To Byte)
End Interface
