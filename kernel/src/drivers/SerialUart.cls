' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/SerialUart.cls
' Summary: 16550 UART COM1 Serial Port driver implementing ICharDevice.

Import Drivers.ICharDevice
Import Arch.X86_64.PortIO
Import Sync

Namespace Drivers

    <Instancing(SingleUse)>
    Public Class SerialUart
        Implements ICharDevice

        Private Declare Function SprintF Lib "libllb_metal" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32

        Private portBase As UInt16
        Private uartLock As Sync.Spinlock
        Private isPortAvailable As Boolean

        Public Sub Initialize()
            Sync.SpinlockOps.Init uartLock
            portBase = &H3F8 ' COM1 Base Port
            isPortAvailable = True

            ' Disable interrupts
            Arch.X86_64.PortIO.OutB portBase + 1, 0

            ' Probe UART scratchpad register (portBase + 7) with dual test patterns to verify real 16550 silicon
            Arch.X86_64.PortIO.OutB portBase + 7, &H5A
            If Arch.X86_64.PortIO.InB(portBase + 7) <> &H5A Then
                isPortAvailable = False
                Exit Sub
            End If

            Arch.X86_64.PortIO.OutB portBase + 7, &HA5
            If Arch.X86_64.PortIO.InB(portBase + 7) <> &HA5 Then
                isPortAvailable = False
                Exit Sub
            End If

            ' Enable DLAB (set baud rate divisor)
            Arch.X86_64.PortIO.OutB portBase + 3, &H80

            ' Set divisor to 3 (38400 baud) or 1 (115200 baud) -> using 38400 (divisor = 3)
            Arch.X86_64.PortIO.OutB portBase + 0, 3
            Arch.X86_64.PortIO.OutB portBase + 1, 0

            ' 8 bits, no parity, one stop bit (8N1)
            Arch.X86_64.PortIO.OutB portBase + 3, &H03

            ' Enable FIFO, clear them, with 14-byte threshold
            Arch.X86_64.PortIO.OutB portBase + 2, &HC7

            ' IRQs enabled, RTS/DSR set
            Arch.X86_64.PortIO.OutB portBase + 4, &H0B
        End Sub

        ' Check if hardware serial port is detected and usable
        Public Function IsAvailable() As Boolean
            IsAvailable = isPortAvailable
        End Function

        ' Check if Transmit Holding Register Empty (bit 5 of Line Status Register)
        Public Function IsTransmitEmpty() As Boolean
            If Not isPortAvailable Then
                IsTransmitEmpty = False
                Exit Function
            End If
            Dim status As Byte = Arch.X86_64.PortIO.InB(portBase + 5)
            If (status And &H20) <> 0 Then
                IsTransmitEmpty = True
            Else
                IsTransmitEmpty = False
            End If
        End Function

        ' Raw un-synchronized character write to COM1 (internal use under uartLock)
        Private Unsafe Sub WriteCharRaw(ByVal ch As Byte)
            If Not isPortAvailable Then Exit Sub

            Dim timeout As UInt32 = 100
            While Not Me.IsTransmitEmpty()
                timeout = timeout - 1
                If timeout = 0 Then Exit Sub
                Asm "pause" : : : "memory"
            Wend

            Arch.X86_64.PortIO.OutB portBase, ch
        End Sub

        ' Write a single character (thread-safe, acquires uartLock)
        Public Unsafe Sub WriteChar(ByVal ch As Byte)
            If Not isPortAvailable Then Exit Sub
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(uartLock)
            Me.WriteCharRaw ch
            Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
        End Sub

        ' Write a raw buffer of bytes of given length atomically (thread-safe, acquires uartLock)
        Public Unsafe Sub WriteBuffer(ByVal bufPtr As Pointer To Byte, ByVal length As UInt64)
            If Not isPortAvailable Or bufPtr = 0 Or length = 0 Then Exit Sub
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(uartLock)
            Dim i As UInt64 = 0
            Do While i < length
                If bufPtr(i) = 10 Then
                    Me.WriteCharRaw 13 ' Prepend CR before LF
                End If
                Me.WriteCharRaw bufPtr(i)
                i = i + 1
            Loop
            Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
        End Sub

        ' Write a null-terminated ASCII string (thread-safe, acquires uartLock)
        Public Unsafe Sub WriteString(ByVal strPtr As Pointer To Byte)
            If Not isPortAvailable Or strPtr = 0 Then Exit Sub
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(uartLock)
            Dim i As UInt64 = 0
            Do While strPtr(i) <> 0
                If strPtr(i) = 10 Then
                    Me.WriteCharRaw 13 ' Prepend CR before LF
                End If
                Me.WriteCharRaw strPtr(i)
                i = i + 1
            Loop
            Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
        End Sub

        ' Write a line of text followed by newline (thread-safe, acquires uartLock across whole line)
        Public Unsafe Sub WriteLine(ByVal str As Pointer To Byte)
            If Not isPortAvailable Or str = 0 Then Exit Sub
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(uartLock)
            Dim i As UInt64 = 0
            Do While str(i) <> 0
                If str(i) = 10 Then
                    Me.WriteCharRaw 13 ' Prepend CR before LF
                End If
                Me.WriteCharRaw str(i)
                i = i + 1
            Loop
            Me.WriteCharRaw 13
            Me.WriteCharRaw 10
            Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
        End Sub

        ' Write a 64-bit integer formatted in hexadecimal (thread-safe, acquires uartLock)
        Public Unsafe Sub WriteHex(ByVal value As UInt64)
            If Not isPortAvailable Then Exit Sub
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(uartLock)
            Me.WriteCharRaw 48 ' '0'
            Me.WriteCharRaw 120 ' 'x'
            If value = 0 Then
                Me.WriteCharRaw 48 ' '0'
                Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
                Exit Sub
            End If

            Dim digits As Pointer To Byte = CPtr(Pointer To Byte, "0123456789ABCDEF")
            Dim buffer(16) As Byte
            Dim pos As Int32 = 0

            Do While value > 0
                buffer(pos) = digits(CType(Byte, value And CType(UInt64, 15)))
                value = value RShift 4
                pos = pos + 1
            Loop

            Dim i As Int32
            For i = pos - 1 To 0 Step -1
                Me.WriteCharRaw buffer(i)
            Next i
            Sync.SpinlockOps.ReleaseIrqRestore uartLock, flags
        End Sub

        ' Write a formatted string (printf-style %s, %u, %d, %x, %c, %%)
        Public Unsafe Sub PrintF(ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64)
            If Not isPortAvailable Then Exit Sub
            Dim buffer(256) As Byte
            Dim bufPtr As Pointer To Byte = CPtr(Pointer To Byte, buffer)
            SprintF bufPtr, 256, fmt, args
            Me.WriteString bufPtr
        End Sub

    End Class

End Namespace
