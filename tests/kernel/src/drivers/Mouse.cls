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
        Private maxBoundX      As Int32
        Private maxBoundY      As Int32
        Private irqCount       As UInt32
        Private idleTicks      As UInt32

        ' Structure of Arrays (SoA) for lock-free ring buffer
        Private packetButtons(64) As Byte
        Private packetDx(64)      As Int32
        Private packetDy(64)      As Int32
        Private packetPosX(64)    As Int32
        Private packetPosY(64)    As Int32
        Private queueHead         As UInt32
        Private queueTail         As UInt32

        ''
        ' @brief Set dynamic display boundaries for cursor clamping.
        ''
        Public Sub SetScreenBounds(ByVal w As Int32, ByVal h As Int32)
            If w > 0 Then maxBoundX = w - 1 Else maxBoundX = 1023
            If h > 0 Then maxBoundY = h - 1 Else maxBoundY = 767
            currentX = w / 2
            currentY = h / 2
        End Sub

        Public Function GetIrqCount() As UInt32
            GetIrqCount = irqCount
        End Function

        ''
        ' @brief Wait for PS/2 controller status buffer condition.
        ' @param waitType 0 = wait for data ready (bit 0=1), 1 = wait for signal clear (bit 1=0).
        ''
        Private Unsafe Sub MouseWait(ByVal waitType As Byte)
            Dim timeout As UInt32 = 500000
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
            maxBoundX = 1023
            maxBoundY = 767
            currentX = 512
            currentY = 384
            currentButtons = 0
            irqCount = 0
            queueHead = 0
            queueTail = 0

            ' Flush residual bytes in 8042 buffer
            While (Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT) And 1) <> 0
                Arch.X86_64.PortIO.InB MOUSE_DATA_PORT
            Wend

            ' 1. Enable auxiliary mouse device (Command 0xA8)
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &HA8

            ' 2. Enable mouse clock (clear Bit 5) without enabling interrupts yet
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H20
            MouseWait 0
            Dim status As Byte = Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT)
            status = (status Or &H01) And &HCF ' Enable Port 1 & 2 Clocks (clear bit 4 & 5)
            status = status And &HFD          ' Keep IRQ 12 disabled during handshake

            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H60
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_DATA_PORT, status

            ' 3. Set default settings (0xF6) and enable packet streaming (0xF4)
            MouseWrite &HF6
            Dim ack1 As Byte = MouseRead()
            MouseWrite &HF4
            Dim ack2 As Byte = MouseRead()
            Serial.PrintF "[MOUSE] Handshake ACKs: 0x%x, 0x%x (expected 0xFA, 0xFA)\r\n", ack1, ack2

            ' 4. Flush any residual ACK bytes in 8042 buffer
            While (Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT) And 1) <> 0
                Arch.X86_64.PortIO.InB MOUSE_DATA_PORT
            Wend

            ' 5. Enable mouse interrupts (Bit 1) now that streaming handshake is complete
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H20
            MouseWait 0
            status = (Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT) Or &H03) And &HCF

            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_COMMAND_PORT, &H60
            MouseWait 1
            Arch.X86_64.PortIO.OutB MOUSE_DATA_PORT, status
            Serial.PrintF "[MOUSE] 8042 Controller Config Byte: 0x%x\r\n", status

            mouseCycle = 0
            Serial.PrintF "[MOUSE] PS/2 Auxiliary Mouse Driver online. Center: (%d, %d)\r\n", currentX, currentY
        End Sub

        ''
        ' @brief Hardware interrupt handler called from IDT Vector 44 (IRQ 12).
        '        Collects 3-byte packets, decodes deltas, and updates the ring buffer.
        ''
        Public Sub TickIdle()
            If mouseCycle > 0 Then
                idleTicks = idleTicks + 1
                If idleTicks > 25 Then
                    mouseCycle = 0
                    idleTicks = 0
                End If
            Else
                idleTicks = 0
            End If
        End Sub

        ''
        ' @brief Hardware interrupt handler called from IDT Vector 44 (IRQ 12) or DispatchPs2.
        '        Consumes exactly one byte per call, decodes 3-byte packets, and updates coordinates.
        '        Zero-polling, zero-VM-exit overhead.
        ''
        Public Unsafe Sub HandleInterrupt()
            Dim status As Byte = Arch.X86_64.PortIO.InB(MOUSE_STATUS_PORT)
            ' Exit if output buffer is empty or byte is not from auxiliary device (Bit 5 = 0)
            If (status And &H01) = 0 Or (status And &H20) = 0 Then
                Exit Sub
            End If

            irqCount = irqCount + 1
            idleTicks = 0

            ' Read byte from 8042 data port
            Dim data As Byte = Arch.X86_64.PortIO.InB(MOUSE_DATA_PORT)
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(mouseLock)

            If mouseCycle = 0 Then
                ' Bit 3 must be 1 for valid packet alignment; drop corrupt or overflow packets
                If (data And &H08) = 0 Or (data And &HC0) <> 0 Then
                    mouseCycle = 0
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

                ' Validate no hardware overflow occurred on deltas
                If (flagsByte And &HC0) = 0 Then
                    ' Standard Linux 9-bit signed delta formula:
                    ' dx = packet[1] - ((packet[0] << 4) & 0x100)
                    ' dy = packet[2] - ((packet[0] << 3) & 0x100)
                    Dim rawDx As Int32 = CType(Int32, mouseBytes(1)) - CType(Int32, (CType(UInt32, flagsByte) LShift 4) And &H100)
                    Dim rawDy As Int32 = CType(Int32, mouseBytes(2)) - CType(Int32, (CType(UInt32, flagsByte) LShift 3) And &H100)

                    ' Sanity filter: ignore impossible delta spikes (> 250 px in one burst)
                    If rawDx >= -250 And rawDx <= 250 And rawDy >= -250 And rawDy <= 250 Then
                        Dim newX As Int32 = currentX + rawDx
                        Dim newY As Int32 = currentY - rawDy

                        ' Clamp to dynamic screen bounds
                        If newX < 0 Then newX = 0
                        If newX > maxBoundX Then newX = maxBoundX
                        If newY < 0 Then newY = 0
                        If newY > maxBoundY Then newY = maxBoundY

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
