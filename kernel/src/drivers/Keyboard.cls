' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/Keyboard.cls
' Summary: PS/2 Keyboard controller and scancode decoder class.

Import Arch.X86_64.PortIO
Import Sync

Namespace Drivers

    <Instancing(SingleUse)>
    Public Class Keyboard

        Private Const KBD_DATA_PORT As UInt16 = &H60
        Private Const KBD_STATUS_PORT As UInt16 = &H64
        Private Const KBD_COMMAND_PORT As UInt16 = &H64
        Private Const BUFFER_SIZE As UInt32 = 256

        Private kbdBuffer(256) As Byte
        Private kbdHead As UInt32
        Private kbdTail As UInt32
        Private kbdLock As Sync.Spinlock

        Private shiftActive As Boolean
        Private ctrlActive As Boolean
        Private altActive As Boolean
        Private capsLockActive As Boolean
        Private e0Escape As Boolean

        Public Unsafe Sub Initialize()
            Sync.SpinlockOps.Init kbdLock
            kbdHead = 0
            kbdTail = 0
            shiftActive = False
            ctrlActive = False
            altActive = False
            capsLockActive = False
            e0Escape = False

            ' Flush output buffer
            While (Arch.X86_64.PortIO.InB(KBD_STATUS_PORT) And 1) <> 0
                Arch.X86_64.PortIO.InB KBD_DATA_PORT
            Wend

            ' Enable keyboard interface command (0xAE)
            Arch.X86_64.PortIO.OutB KBD_COMMAND_PORT, &HAE
        End Sub

        ' Push single character byte to keyboard ring buffer
        Private Sub EnqueueByte(ByVal ch As Byte)
            Dim nextHead As UInt32 = (kbdHead + 1) Mod BUFFER_SIZE
            If nextHead <> kbdTail Then
                kbdBuffer(kbdHead) = ch
                kbdHead = nextHead
            End If
        End Sub

        ' Map standard US scancode to ASCII
        Private Function MapScancode(ByVal scancode As Byte, ByVal isShifted As Boolean) As Byte
            Dim res As Byte = 0

            ' Symbol row (grave accent & tilde)
            If scancode = &H29 Then If isShifted Then res = 126 Else res = 96 ' ~ or `

            ' Digits row & top row symbols
            If scancode = &H02 Then If isShifted Then res = 33 Else res = 49 ' 1 or !
            If scancode = &H03 Then If isShifted Then res = 64 Else res = 50 ' 2 or @
            If scancode = &H04 Then If isShifted Then res = 35 Else res = 51 ' 3 or #
            If scancode = &H05 Then If isShifted Then res = 36 Else res = 52 ' 4 or $
            If scancode = &H06 Then If isShifted Then res = 37 Else res = 53 ' 5 or %
            If scancode = &H07 Then If isShifted Then res = 94 Else res = 54 ' 6 or ^
            If scancode = &H08 Then If isShifted Then res = 38 Else res = 55 ' 7 or &
            If scancode = &H09 Then If isShifted Then res = 42 Else res = 56 ' 8 or *
            If scancode = &H0A Then If isShifted Then res = 40 Else res = 57 ' 9 or (
            If scancode = &H0B Then If isShifted Then res = 41 Else res = 48 ' 0 or )
            If scancode = &H0C Then If isShifted Then res = 95 Else res = 45 ' _ or -
            If scancode = &H0D Then If isShifted Then res = 43 Else res = 61 ' + or =

            ' Letter case logic (Shift XOR CapsLock)
            Dim letterShifted As Boolean = isShifted Xor capsLockActive

            ' QWERTY row
            If scancode = &H10 Then If letterShifted Then res = 81 Else res = 113 ' Q
            If scancode = &H11 Then If letterShifted Then res = 87 Else res = 119 ' W
            If scancode = &H12 Then If letterShifted Then res = 69 Else res = 101 ' E
            If scancode = &H13 Then If letterShifted Then res = 82 Else res = 114 ' R
            If scancode = &H14 Then If letterShifted Then res = 84 Else res = 116 ' T
            If scancode = &H15 Then If letterShifted Then res = 89 Else res = 121 ' Y
            If scancode = &H16 Then If letterShifted Then res = 85 Else res = 117 ' U
            If scancode = &H17 Then If letterShifted Then res = 73 Else res = 105 ' I
            If scancode = &H18 Then If letterShifted Then res = 79 Else res = 111 ' O
            If scancode = &H19 Then If letterShifted Then res = 80 Else res = 112 ' P
            If scancode = &H1A Then If isShifted Then res = 123 Else res = 91    ' { or [
            If scancode = &H1B Then If isShifted Then res = 125 Else res = 93    ' } or ]
            If scancode = &H2B Then If isShifted Then res = 124 Else res = 92    ' | or \

            ' ASDFGHJKL row
            If scancode = &H1E Then If letterShifted Then res = 65 Else res = 97  ' A
            If scancode = &H1F Then If letterShifted Then res = 83 Else res = 115 ' S
            If scancode = &H20 Then If letterShifted Then res = 68 Else res = 100 ' D
            If scancode = &H21 Then If letterShifted Then res = 70 Else res = 102 ' F
            If scancode = &H22 Then If letterShifted Then res = 71 Else res = 103 ' G
            If scancode = &H23 Then If letterShifted Then res = 72 Else res = 104 ' H
            If scancode = &H24 Then If letterShifted Then res = 74 Else res = 106 ' J
            If scancode = &H25 Then If letterShifted Then res = 75 Else res = 107 ' K
            If scancode = &H26 Then If letterShifted Then res = 76 Else res = 108 ' L
            If scancode = &H27 Then If isShifted Then res = 58 Else res = 59     ' : or ;
            If scancode = &H28 Then If isShifted Then res = 34 Else res = 39     ' " or '

            ' ZXCVBNM row
            If scancode = &H2C Then If letterShifted Then res = 90 Else res = 122 ' Z
            If scancode = &H2D Then If letterShifted Then res = 88 Else res = 120 ' X
            If scancode = &H2E Then If letterShifted Then res = 67 Else res = 99  ' C
            If scancode = &H2F Then If letterShifted Then res = 86 Else res = 118 ' V
            If scancode = &H30 Then If letterShifted Then res = 66 Else res = 98  ' B
            If scancode = &H31 Then If letterShifted Then res = 78 Else res = 110 ' N
            If scancode = &H32 Then If letterShifted Then res = 77 Else res = 109 ' M
            If scancode = &H33 Then If isShifted Then res = 60 Else res = 44     ' < or ,
            If scancode = &H34 Then If isShifted Then res = 62 Else res = 46     ' > or .
            If scancode = &H35 Then If isShifted Then res = 63 Else res = 47     ' ? or /

            ' Special characters & control keys
            If scancode = &H1C Then res = 10 ' Enter / Newline
            If scancode = &H0E Then res = 8  ' Backspace
            If scancode = &H0F Then res = 9  ' Tab
            If scancode = &H39 Then res = 32 ' Space

            ' Keypad keys
            If scancode = &H37 Then res = 42 ' *
            If scancode = &H4A Then res = 45 ' -
            If scancode = &H4E Then res = 43 ' +
            If scancode = &H53 Then res = 46 ' .
            If scancode = &H52 Then res = 48 ' 0
            If scancode = &H4F Then res = 49 ' 1
            If scancode = &H50 Then res = 50 ' 2
            If scancode = &H51 Then res = 51 ' 3
            If scancode = &H4B Then res = 52 ' 4
            If scancode = &H4C Then res = 53 ' 5
            If scancode = &H4D Then res = 54 ' 6
            If scancode = &H47 Then res = 55 ' 7
            If scancode = &H48 Then res = 56 ' 8
            If scancode = &H49 Then res = 57 ' 9

            MapScancode = res
        End Function

        ' Process incoming scancode from PS/2 hardware IRQ 1
        Public Unsafe Sub HandleInterrupt()
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(kbdLock)

            Dim status As Byte = Arch.X86_64.PortIO.InB(KBD_STATUS_PORT)
            If (status And &H01) = 0 Or (status And &H20) <> 0 Then
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            Dim scancode As Byte = Arch.X86_64.PortIO.InB(KBD_DATA_PORT)

            ' Extended escape sequence
            If scancode = &HE0 Then
                e0Escape = True
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            If e0Escape Then
                Dim isRel As Boolean = (scancode And &H80) <> 0
                Dim baseCode As Byte = scancode And &H7F
                If baseCode = &H1D Then ctrlActive = Not isRel
                If baseCode = &H38 Then altActive = Not isRel

                If Not isRel Then
                    ' Extended Navigation & Cursor Keys -> Standard ANSI Sequences
                    If baseCode = &H48 Then     ' Up Arrow: \x1B[A
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 65
                    ElseIf baseCode = &H50 Then ' Down Arrow: \x1B[B
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 66
                    ElseIf baseCode = &H4D Then ' Right Arrow: \x1B[C
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 67
                    ElseIf baseCode = &H4B Then ' Left Arrow: \x1B[D
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 68
                    ElseIf baseCode = &H47 Then ' Home: \x1B[H
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 72
                    ElseIf baseCode = &H4F Then ' End: \x1B[F
                        Me.EnqueueByte 27: Me.EnqueueByte 91: Me.EnqueueByte 70
                    ElseIf baseCode = &H53 Then ' Delete: 127 (ASCII DEL)
                        Me.EnqueueByte 127
                    ElseIf baseCode = &H1C Then ' Keypad Enter: 10 (\n)
                        Me.EnqueueByte 10
                    ElseIf baseCode = &H35 Then ' Keypad Slash: 47 (/)
                        Me.EnqueueByte 47
                    End If
                End If

                e0Escape = False
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            ' Key release handling
            If (scancode And &H80) <> 0 Then
                Dim releasedKey As Byte = scancode And &H7F
                If releasedKey = &H2A Or releasedKey = &H36 Then shiftActive = False
                If releasedKey = &H1D Then ctrlActive = False
                If releasedKey = &H38 Then altActive = False
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            ' Key press modifier tracking
            If scancode = &H2A Or scancode = &H36 Then
                shiftActive = True
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If
            If scancode = &H1D Then
                ctrlActive = True
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If
            If scancode = &H38 Then
                altActive = True
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            ' CapsLock toggle
            If scancode = &H3A Then
                capsLockActive = Not capsLockActive
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                Exit Sub
            End If

            ' Translate scancode to ASCII
            If scancode < 128 Then
                Dim asciiChar As Byte = Me.MapScancode(scancode, shiftActive)
                If asciiChar <> 0 Then
                    Me.EnqueueByte asciiChar
                End If
            End If

            Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
        End Sub

        ' Non-blocking character read from keyboard ring buffer
        Public Unsafe Function GetChar() As Byte
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(kbdLock)

            If kbdHead = kbdTail Then
                Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
                GetChar = 0
                Exit Function
            End If

            Dim ch As Byte = kbdBuffer(kbdTail)
            kbdTail = (kbdTail + 1) Mod BUFFER_SIZE

            Sync.SpinlockOps.ReleaseIrqRestore kbdLock, flags
            GetChar = ch
        End Function

    End Class

End Namespace
