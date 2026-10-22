' Project Name: Low-Level Basic Kernel / llbc
' Filename: tests/kernel/src/drivers/SerialUart.cls
' Summary: 16550 UART COM1 Serial Port driver implementing ICharDevice.

Import Drivers.ICharDevice
Import Arch.X86_64.PortIO

Namespace Drivers

    <Instancing(SingleUse)>
    Public Class SerialUart
        Implements ICharDevice

        Private portBase As UInt16

        Public Sub Initialize()
            portBase = &H3F8 ' COM1 Base Port

            ' Disable interrupts
            Arch.X86_64.PortIO.OutB portBase + 1, 0

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

        ' Check if Transmit Holding Register Empty (bit 5 of Line Status Register)
        Public Function IsTransmitEmpty() As Boolean
            Dim status As Byte = Arch.X86_64.PortIO.InB(portBase + 5)
            If (status And &H20) <> 0 Then
                IsTransmitEmpty = True
            Else
                IsTransmitEmpty = False
            End If
        End Function

        ' Write a single character with timeout protection against hypervisor hang
        Public Unsafe Sub WriteChar(ByVal ch As Byte)
            Dim timeout As Int32 = 100
            While Not Me.IsTransmitEmpty()
                timeout = timeout - 1
                If timeout <= 0 Then
                    Exit Sub
                End If
                Asm
                    "pause"
                End Asm
            Wend

            Arch.X86_64.PortIO.OutB portBase, ch
        End Sub

        ' Write a null-terminated ASCII string
        Public Unsafe Sub WriteString(ByVal str As Pointer To Byte)
            Dim i As Int32 = 0
            Do While str(i) <> 0
                If str(i) = 10 Then
                    Me.WriteChar 13 ' Prepend CR before LF
                End If
                Me.WriteChar str(i)
                i = i + 1
            Loop
        End Sub

    End Class

End Namespace
