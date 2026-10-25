' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/Mouse.cls
' Summary: PS/2 Mouse controller, 3-byte packet decoder, and raw input ring buffer.
'          Ports PRK kernel/mouse.c to Low-Level Basic.

Import Arch.X86_64.PortIO
Import Sync
Use Drivers.SerialUart As Serial

Namespace Drivers

    <Instancing(SingleUse)>
    Public Class Mouse

        Private Const MOUSE_DATA_PORT    As UInt16 = &H60
        Private Const MOUSE_STATUS_PORT  As UInt16 = &H64
        Private Const MOUSE_COMMAND_PORT As UInt16 = &H64
        Private Const MOUSE_QUEUE_SIZE   As UInt32 = 64

        Private mouseLock      As Sync.Spinlock
        Private mouseCycle     As Byte
        Private mouseBytes(3)  As Byte

        Private currentX       As Int32
        Private currentY       As Int32
        Private currentButtons As Byte

        ' Structure of Arrays (SoA) for lock-free ring buffer
        Private packetButtons(64) As Byte
        Private packetDx(64)      As Int32
        Private packetDy(64)      As Int32
        Private packetPosX(64)    As Int32
        Private packetPosY(64)    As Int32
        Private queueHead         As UInt32
        Private queueTail         As UInt32

        ''
        ' @brief Wait for PS/2 controller status buffer condition.
        ' @param waitType 0 = wait for data ready (bit 0=1), 1 = wait for signal clear (bit 1=0).
        ''
        Private Unsafe Sub MouseWait(ByVal waitType As Byte)
            Dim timeout As UInt32 = 100000
            If waitType = 0 Then
                While timeout > 0
                    If (Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT) And 1) <> 0 Then Exit Sub
                    timeout = timeout - 1
                Wend
            Else
                While timeout > 0
                    If (Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT) And 2) = 0 Then Exit Sub
                    timeout = timeout - 1
                Wend
            End If
        End Sub

        ''
        ' @brief Write byte to auxiliary mouse device via controller command 0xD4.
        ' @param val Byte value to transmit to mouse.
        ''
        Private Unsafe Sub MouseWrite(ByVal val As Byte)
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &HD4
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_DATA_PORT, val
        End Sub

        ''
        ' @brief Read byte from mouse data port after waiting for buffer ready.
        ' @return Byte read from controller.
        ''
        Private Unsafe Function MouseRead() As Byte
            MouseWait 0
            MouseRead = Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT)
        End Function

        ''
        ' @brief Initialize PS/2 auxiliary mouse hardware and enable IRQ12 streaming.
        ''
        Public Unsafe Sub Initialize()
            Sync.SpinlockOps.Init mouseLock
            mouseCycle = 0
            currentX = 512
            currentY = 384
            currentButtons = 0
            queueHead = 0
            queueTail = 0

            ' 1. Enable auxiliary mouse device (Command 0xA8)
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &HA8

            ' 2. Enable mouse interrupts via Compaq status byte (Command 0x20 / 0x60)
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H20
            MouseWait 0
            Dim status As Byte = Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT) Or 2

            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H60
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_DATA_PORT, status

            ' 3. Set default settings (0xF6) and enable packet streaming (0xF4)
            MouseWrite &HF6
            MouseRead
            MouseWrite &HF4
            MouseRead

            Serial.PrintF "[MOUSE] PS/2 Auxiliary Mouse Driver online. Center: (%d, %d)\r\n", currentX, currentY
        End Sub

        ''
        ' @brief Hardware interrupt handler called from IDT Vector 44 (IRQ 12).
        '        Collects 3-byte packets, decodes deltas, and updates the ring buffer.
        ''
        Public Unsafe Sub HandleInterrupt()
            Dim status As Byte = Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT)
            If (status And &H01) = 0 Or (status And &H20) = 0 Then Exit Sub

            Dim data As Byte = Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT)
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(mouseLock)

            If mouseCycle = 0 Then
                ' Bit 3 must be 1 for valid packet alignment
                If (data And &H08) = 0 Then
                    Sync.SpinlockOps.ReleaseIrqRestore mouseLock, flags
                    Exit Sub
                End If
                mouseBytes(0) = data
                mouseCycle = 1
            ElseIf mouseCycle = 1 Then
                mouseBytes(1) = data
                mouseCycle = 2
            ElseIf mouseCycle = 2 Then
                mouseBytes(2) = data
                mouseCycle = 0

                Dim flagsByte As Byte = mouseBytes(0)
                currentButtons = flagsByte And &H07

                ' Sign extension based on PS/2 flags bits 4 and 5
                Dim rawDx As Int32 = CType(Int32, mouseBytes(1))
                If (flagsByte And &H10) <> 0 Then
                    rawDx = rawDx Or CType(Int32, &HFFFFFF00)
                End If

                Dim rawDy As Int32 = CType(Int32, mouseBytes(2))
                If (flagsByte And &H20) <> 0 Then
                    rawDy = rawDy Or CType(Int32, &HFFFFFF00)
                End If

                Dim newX As Int32 = currentX + rawDx
                Dim newY As Int32 = currentY - rawDy

                ' Clamp to screen bounds (1024x768)
                If newX < 0 Then newX = 0
                If newX > 1023 Then newX = 1023
                If newY < 0 Then newY = 0
                If newY > 767 Then newY = 767

                currentX = newX
                currentY = newY

                ' Enqueue into ring buffer
                Dim nextHead As UInt32 = (queueHead + 1) Mod MOUSE_QUEUE_SIZE
                If nextHead <> queueTail Then
                    packetButtons(queueHead) = currentButtons
                    packetDx(queueHead) = rawDx
                    packetDy(queueHead) = rawDy
                    packetPosX(queueHead) = currentX
                    packetPosY(queueHead) = currentY
                    queueHead = nextHead
                End If
            End If

            Sync.SpinlockOps.ReleaseIrqRestore mouseLock, flags
        End Sub

        ''
        ' @brief Fetch the current absolute screen coordinates and button state.
        ' @param outX Receives clamped X coordinate.
        ' @param outY Receives clamped Y coordinate.
        ' @param outButtons Receives button bitmask (Bit 0: Left, Bit 1: Right, Bit 2: Middle).
        ''
        Public Unsafe Sub GetState(ByRef outX As Int32, ByRef outY As Int32, ByRef outButtons As Byte)
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(mouseLock)
            outX = currentX
            outY = currentY
            outButtons = currentButtons
            Sync.SpinlockOps.ReleaseIrqRestore mouseLock, flags
        End Sub

        ''
        ' @brief Dequeue a raw mouse packet from the ring buffer.
        ' @return True if a packet was dequeued, False if buffer was empty.
        ''
        Public Unsafe Function PopPacket(ByRef outButtons As Byte, ByRef outDx As Int32, ByRef outDy As Int32, ByRef outX As Int32, ByRef outY As Int32) As Boolean
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(mouseLock)

            If queueHead = queueTail Then
                Sync.SpinlockOps.ReleaseIrqRestore mouseLock, flags
                PopPacket = False
                Exit Function
            End If

            outButtons = packetButtons(queueTail)
            outDx = packetDx(queueTail)
            outDy = packetDy(queueTail)
            outX = packetPosX(queueTail)
            outY = packetPosY(queueTail)
            queueTail = (queueTail + 1) Mod MOUSE_QUEUE_SIZE

            Sync.SpinlockOps.ReleaseIrqRestore mouseLock, flags
            PopPacket = True
        End Function

    End Class

End Namespace
