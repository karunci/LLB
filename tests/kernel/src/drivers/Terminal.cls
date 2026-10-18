' Project Name: PRK-OS
' Filename: src/drivers/Terminal.cls
' Workspace Path: src/drivers/Terminal.cls
' Summary: Object-oriented VGA text-mode driver providing color output, cursor tracking,
'          and hardware row scrolling for Low-Level Basic kernels.

Class Drivers.Terminal

    ' VGA Text Mode Constants (80x25 character grid)
    Private Const VGA_WIDTH As UInt32 = 80
    Private Const VGA_HEIGHT As UInt32 = 25
    Private Const VGA_MEMORY_ADDRESS As UInt64 = &HB8000

    ' Hardware Colors
    Public Const COLOR_BLACK As Byte = 0
    Public Const COLOR_BLUE As Byte = 1
    Public Const COLOR_GREEN As Byte = 2
    Public Const COLOR_CYAN As Byte = 3
    Public Const COLOR_RED As Byte = 4
    Public Const COLOR_MAGENTA As Byte = 5
    Public Const COLOR_BROWN As Byte = 6
    Public Const COLOR_LIGHT_GREY As Byte = 7
    Public Const COLOR_DARK_GREY As Byte = 8
    Public Const COLOR_LIGHT_BLUE As Byte = 9
    Public Const COLOR_LIGHT_GREEN As Byte = 10
    Public Const COLOR_LIGHT_CYAN As Byte = 11
    Public Const COLOR_LIGHT_RED As Byte = 12
    Public Const COLOR_LIGHT_MAGENTA As Byte = 13
    Public Const COLOR_LIGHT_BROWN As Byte = 14
    Public Const COLOR_WHITE As Byte = 15

    ' Terminal State Fields
    Private buffer As Volatile Pointer To UInt16
    Private cursorX As UInt32
    Private cursorY As UInt32
    Private currentAttribute As Byte

    ' Helper to pack foreground and background colors into a single VGA attribute byte
    Private Function MakeAttribute(ByVal fg As Byte, ByVal bg As Byte) As Byte
        MakeAttribute = fg Or (bg LShift 4)
    End Function

    ' Helper to pack an ASCII character byte and VGA attribute byte into a 16-bit word
    Private Function MakeVgaEntry(ByVal ch As Byte, ByVal attr As Byte) As UInt16
        MakeVgaEntry = CType(UInt16, ch) Or (CType(UInt16, attr) LShift 8)
    End Function

    ' Initialize Terminal state and assign video memory pointer
    Public Unsafe Sub Initialize(Optional ByVal fg As Byte = COLOR_WHITE, Optional ByVal bg As Byte = COLOR_BLACK)
        Me.buffer = CPtr(Volatile Pointer To UInt16, VGA_MEMORY_ADDRESS)
        Me.cursorX = 0
        Me.cursorY = 0
        Me.currentAttribute = Me.MakeAttribute(fg, bg)
        Me.Clear
    End Sub

    ' Set active foreground and background color for subsequent text output
    Public Sub SetColor(ByVal fg As Byte, Optional ByVal bg As Byte = COLOR_BLACK)
        Me.currentAttribute = Me.MakeAttribute(fg, bg)
    End Sub

    ' Clear the entire screen with the active background color and reset cursor
    Public Unsafe Sub Clear()
        Dim blankEntry As UInt16
        blankEntry = Me.MakeVgaEntry(32, Me.currentAttribute) ' 32 = ASCII Space

        Dim i As UInt32
        For i = 0 To (VGA_WIDTH * VGA_HEIGHT) - 1
            Me.buffer(i) = blankEntry
        Next i

        Me.cursorX = 0
        Me.cursorY = 0
    End Sub

    ' Scroll the screen up by one row when the cursor reaches the bottom line
    Public Unsafe Private Sub Scroll()
        Dim row As UInt32
        Dim col As UInt32
        Dim destOffset As UInt32
        Dim srcOffset As UInt32

        ' Move rows 1..24 up to rows 0..23
        For row = 1 To VGA_HEIGHT - 1
            For col = 0 To VGA_WIDTH - 1
                destOffset = ((row - 1) * VGA_WIDTH) + col
                srcOffset = (row * VGA_WIDTH) + col
                Me.buffer(destOffset) = Me.buffer(srcOffset)
            Next col
        Next row

        ' Clear the bottom row (row 24)
        Dim blankEntry As UInt16
        blankEntry = Me.MakeVgaEntry(32, Me.currentAttribute)
        Dim bottomRowOffset As UInt32
        bottomRowOffset = (VGA_HEIGHT - 1) * VGA_WIDTH

        For col = 0 To VGA_WIDTH - 1
            Me.buffer(bottomRowOffset + col) = blankEntry
        Next col

        Me.cursorY = VGA_HEIGHT - 1
    End Sub

    ' Write a single character to the terminal
    Public Unsafe Sub WriteChar(ByVal ch As Byte)
        ' Handle Newline (\n)
        If ch = 10 Then
            Me.cursorX = 0
            Me.cursorY = Me.cursorY + 1
        ' Handle Carriage Return (\r)
        ElseIf ch = 13 Then
            Me.cursorX = 0
        ' Handle Backspace (\b)
        ElseIf ch = 8 Then
            If Me.cursorX > 0 Then
                Me.cursorX = Me.cursorX - 1
                Dim offset As UInt32
                offset = (Me.cursorY * VGA_WIDTH) + Me.cursorX
                Me.buffer(offset) = Me.MakeVgaEntry(32, Me.currentAttribute)
            End If
        ' Printable ASCII Characters
        Else
            Dim charOffset As UInt32
            charOffset = (Me.cursorY * VGA_WIDTH) + Me.cursorX
            Me.buffer(charOffset) = Me.MakeVgaEntry(ch, Me.currentAttribute)
            Me.cursorX = Me.cursorX + 1
        End If

        ' Wrap cursor to next line if width exceeded
        If Me.cursorX >= VGA_WIDTH Then
            Me.cursorX = 0
            Me.cursorY = Me.cursorY + 1
        End If

        ' Scroll screen if cursor exceeds total height
        If Me.cursorY >= VGA_HEIGHT Then
            Me.Scroll
        End If
    End Sub

    ' Write a null-terminated string to the terminal
    Public Unsafe Sub WriteString(ByVal strPtr As Pointer To Byte)
        Dim i As UInt64
        i = 0
        Do While strPtr(i) <> 0
            Me.WriteChar strPtr(i)
            i = i + 1
        Loop
    End Sub

    ' Write a line of text followed by a newline character
    Public Unsafe Sub WriteLine(ByVal strPtr As Pointer To Byte)
        Me.WriteString strPtr
        Me.WriteChar 10 ' Newline
    End Sub

    ' Render an unsigned 64-bit integer as a Hexadecimal string (e.g., 0x00200000)
    Public Unsafe Sub WriteHex(ByVal value As UInt64)
        Me.WriteString CPtr(Pointer To Byte, "0x")
        
        If value = 0 Then
            Me.WriteString CPtr(Pointer To Byte, "0")
            Exit Sub
        End If

        Dim digits As Pointer To Byte
        digits = CPtr(Pointer To Byte, "0123456789ABCDEF")

        Dim buffer(16) As Byte
        Dim pos As Int32
        pos = 0

        Do While value > 0
            buffer(pos) = digits(CType(Byte, value And &HF))
            value = value RShift 4
            pos = pos + 1
        Loop

        ' Print in reverse order
        Dim i As Int32
        For i = pos - 1 To 0 Step -1
            Me.WriteChar buffer(i)
        Next i
    End Sub

End Class