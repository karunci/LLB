' Project Name: Low-Level Basic Kernel / llbc
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
        Private e0Escape As Boolean

        Public Unsafe Sub Initialize()
            Sync.SpinlockOps.Init kbdLock
            kbdHead = 0
            kbdTail = 0
            shiftActive = False
            ctrlActive = False
            altActive = False
            e0Escape = False

            ' Flush output buffer
            While (Arch.X86_64.PortIO.InB(KBD_STATUS_PORT) And 1) <> 0
                Arch.X86_64.PortIO.InB KBD_DATA_PORT
            Wend

            ' Enable keyboard interface command (0xAE)
            Arch.X86_64.PortIO.OutB KBD_COMMAND_PORT, &HAE
        End Sub

        ' Map standard US scancode to ASCII
        Private Function MapScancode(ByVal scancode As Byte, ByVal isShifted As Boolean) As Byte
            Dim res As Byte = 0

            ' Digits and letters
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

            If scancode = &H10 Then If isShifted Then res = 81 Else res = 113 ' Q
            If scancode = &H11 Then If isShifted Then res = 87 Else res = 119 ' W
            If scancode = &H12 Then If isShifted Then res = 69 Else res = 101 ' E
            If scancode = &H13 Then If isShifted Then res = 82 Else res = 114 ' R
            If scancode = &H14 Then If isShifted Then res = 84 Else res = 116 ' T
            If scancode = &H15 Then If isShifted Then res = 89 Else res = 121 ' Y
            If scancode = &H16 Then If isShifted Then res = 85 Else res = 117 ' U
            If scancode = &H17 Then If isShifted Then res = 73 Else res = 105 ' I
            If scancode = &H18 Then If isShifted Then res = 79 Else res = 111 ' O
            If scancode = &H19 Then If isShifted Then res = 80 Else res = 112 ' P

            If scancode = &H1E Then If isShifted Then res = 65 Else res = 97  ' A
            If scancode = &H1F Then If isShifted Then res = 83 Else res = 115 ' S
            If scancode = &H20 Then If isShifted Then res = 68 Else res = 100 ' D
            If scancode = &H21 Then If isShifted Then res = 70 Else res = 102 ' F
            If scancode = &H22 Then If isShifted Then res = 71 Else res = 103 ' G
            If scancode = &H23 Then If isShifted Then res = 72 Else res = 104 ' H
            If scancode = &H24 Then If isShifted Then res = 74 Else res = 106 ' J
            If scancode = &H25 Then If isShifted Then res = 75 Else res = 107 ' K
            If scancode = &H26 Then If isShifted Then res = 76 Else res = 108 ' L

            If scancode = &H2C Then If isShifted Then res = 90 Else res = 122 ' Z
            If scancode = &H2D Then If isShifted Then res = 88 Else res = 120 ' X
            If scancode = &H2E Then If isShifted Then res = 67 Else res = 99  ' C
            If scancode = &H2F Then If isShifted Then res = 86 Else res = 118 ' V
            If scancode = &H30 Then If isShifted Then res = 66 Else res = 98  ' B
            If scancode = &H31 Then If isShifted Then res = 78 Else res = 110 ' N
            If scancode = &H32 Then If isShifted Then res = 77 Else res = 109 ' M

            ' Special characters & control keys
            If scancode = &H1C Then res = 10 ' Enter / Newline
            If scancode = &H0E Then res = 8  ' Backspace
            If scancode = &H0F Then res = 9  ' Tab
            If scancode = &H39 Then res = 32 ' Space

            MapScancode = res
        End Function

        ' Process incoming scancode from PS/2 hardware IRQ 1
        Public Unsafe Sub HandleInterrupt()
            Dim status As Byte = Arch.X86_64.PortIO.InB(KBD_STATUS_PORT)
            If (status And &H01) = 0 Or (status And &H20) <> 0 Then
                Exit Sub
            End If

            Dim scancode As Byte = Arch.X86_64.PortIO.InB(KBD_DATA_PORT)

            ' Extended escape sequence
            If scancode = &HE0 Then
                e0Escape = True
                Exit Sub
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(kbdLock)

            If e0Escape Then
                Dim isRel As Boolean = (scancode And &H80) <> 0
                Dim baseCode As Byte = scancode And &H7F
                If baseCode = &H1D Then ctrlActive = Not isRel
                If baseCode = &H38 Then altActive = Not isRel
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

            ' Translate scancode to ASCII
            If scancode < 128 Then
                Dim asciiChar As Byte = Me.MapScancode(scancode, shiftActive)
                If asciiChar <> 0 Then
                    Dim nextHead As UInt32 = (kbdHead + 1) Mod BUFFER_SIZE
                    If nextHead <> kbdTail Then
                        kbdBuffer(kbdHead) = asciiChar
                        kbdHead = nextHead
                    End If
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
