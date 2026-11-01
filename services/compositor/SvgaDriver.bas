' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: services/compositor/SvgaDriver.bas
' Summary: VMware SVGA-II / VirtualBox VBoxSVGA hardware acceleration driver.
'          Detects PCI 0x15AD:0x0405, negotiates SVGA_ID_2, initializes hardware
'          FIFO command queue, and offloads presentation damage updates and cursor planes.

Import "../../include/pros.bas"

Namespace Pros.Compositor.Gpu

    Public Module SvgaDriver

        ' VMware SVGA-II Register Indices
        Public Const SVGA_REG_ID            As UInt32 = 0
        Public Const SVGA_REG_ENABLE        As UInt32 = 1
        Public Const SVGA_REG_WIDTH         As UInt32 = 2
        Public Const SVGA_REG_HEIGHT        As UInt32 = 3
        Public Const SVGA_REG_BITS_PER_PIXEL As UInt32 = 7
        Public Const SVGA_REG_BYTES_PER_LINE As UInt32 = 14
        Public Const SVGA_REG_FB_OFFSET     As UInt32 = 16
        Public Const SVGA_REG_VRAM_SIZE     As UInt32 = 15
        Public Const SVGA_REG_FB_SIZE       As UInt32 = 17
        Public Const SVGA_REG_CAPABILITIES  As UInt32 = 18
        Public Const SVGA_REG_FIFO_OFFSET   As UInt32 = 19
        Public Const SVGA_REG_FIFO_SIZE     As UInt32 = 20
        Public Const SVGA_REG_CONFIG_DONE   As UInt32 = 21
        Public Const SVGA_REG_SYNC          As UInt32 = 22
        Public Const SVGA_REG_BUSY          As UInt32 = 23
        Public Const SVGA_REG_CURSOR_ID     As UInt32 = 29
        Public Const SVGA_REG_CURSOR_X      As UInt32 = 30
        Public Const SVGA_REG_CURSOR_Y      As UInt32 = 31
        Public Const SVGA_REG_CURSOR_ON     As UInt32 = 32

        ' Magic Protocol Identification Constants
        Public Const SVGA_ID_MAGIC          As UInt32 = &H90000000
        Public Const SVGA_ID_0              As UInt32 = &H90000000
        Public Const SVGA_ID_1              As UInt32 = &H90000001
        Public Const SVGA_ID_2              As UInt32 = &H90000002

        ' FIFO Acceleration Command Types
        Public Const SVGA_CMD_UPDATE        As UInt32 = 1
        Public Const SVGA_CMD_RECT_FILL     As UInt32 = 2
        Public Const SVGA_CMD_RECT_COPY     As UInt32 = 3
        Public Const SVGA_CMD_DEFINE_CURSOR As UInt32 = 19

        ' FIFO Register Offsets (in 32-bit DWORDs)
        Public Const SVGA_FIFO_MIN          As UInt32 = 0
        Public Const SVGA_FIFO_MAX          As UInt32 = 1
        Public Const SVGA_FIFO_NEXT_CMD     As UInt32 = 2
        Public Const SVGA_FIFO_STOP         As UInt32 = 3

        ' Driver State
        Private isAvailable  As Boolean = False
        Private ioBase       As UInt16 = 0
        Private pFifo        As Pointer To UInt32 = 0
        Private fifoSizeBytes As UInt32 = 0
        Private hasFifo      As Boolean = False

        ''
        ' @brief Read a 32-bit register from VMware SVGA-II display controller.
        ''
        Public Unsafe Function ReadReg(ByVal regIdx As UInt32) As UInt32
            PortOut32 ioBase + 0, regIdx
            ReadReg = PortIn32(ioBase + 1)
        End Function

        ''
        ' @brief Write a 32-bit register to VMware SVGA-II display controller.
        ''
        Public Unsafe Sub WriteReg(ByVal regIdx As UInt32, ByVal val As UInt32)
            PortOut32 ioBase + 0, regIdx
            PortOut32 ioBase + 1, val
        End Sub

        ''
        ' @brief Probe PCI configuration space and initialize VMware SVGA-II accelerator.
        ' @return True if VMware SVGA-II was detected, negotiated, and activated.
        ''
        Public Unsafe Function Initialize() As Boolean
            isAvailable = False
            ioBase = 0
            pFifo = 0
            hasFifo = False

            Dim devCount As UInt32 = PciGetDeviceCount()
            Dim dIdx As UInt32 = 0
            Dim targetDev As PciDevice
            Dim found As Boolean = False
            Dim foundIndex As UInt32 = 0

            While dIdx < devCount
                Dim dev As PciDevice
                If PciGetDevice(dIdx, dev) Then
                    If dev.VendorId = &H15AD And dev.DeviceId = &H0405 Then
                        targetDev = dev
                        found = True
                        foundIndex = dIdx
                        Exit While
                    End If
                End If
                dIdx = dIdx + 1
            Wend

            If Not found Then
                ConsoleWriteLine "[SVGA] VMware SVGA-II device (0x15AD:0x0405) not present on PCI bus."
                Initialize = False
                Exit Function
            End If

            ' Extract I/O Port base from BAR0
            If Not targetDev.Bar0.IsIo Or targetDev.Bar0.PhysBase = 0 Then
                ConsoleWriteLine "[SVGA] Error: BAR0 is not an I/O space aperture."
                Initialize = False
                Exit Function
            End If

            ioBase = UInt16(targetDev.Bar0.PhysBase And &HFFFF)
            ConsolePrintWithUInt "[SVGA] Located VMware SVGA-II Controller at I/O Port: 0x", UInt64(ioBase), "\r\n"

            ' 1. Negotiate SVGA_ID_2 protocol
            WriteReg SVGA_REG_ID, SVGA_ID_2
            Dim readId As UInt32 = ReadReg(SVGA_REG_ID)
            If readId <> SVGA_ID_2 Then
                ConsolePrintWithUInt "[SVGA] Protocol negotiation failed. Hardware returned ID: 0x", UInt64(readId), "\r\n"
                Initialize = False
                Exit Function
            End If
            ConsoleWriteLine "[SVGA] SVGA_ID_2 Protocol Negotiated Successfully!"

            ' 2. Read Device Capabilities and Memory Dimensions
            Dim vramSize As UInt32 = ReadReg(SVGA_REG_VRAM_SIZE)
            Dim fbSize As UInt32 = ReadReg(SVGA_REG_FB_SIZE)
            Dim caps As UInt32 = ReadReg(SVGA_REG_CAPABILITIES)
            ConsolePrintWithUInt "[SVGA] VRAM Size: ", UInt64(vramSize / 1024), " KB\r\n"
            ConsolePrintWithUInt "[SVGA] Hardware Capabilities: 0x", UInt64(caps), "\r\n"

            ' 3. Map FIFO Command Buffer from BAR2 (if present)
            If targetDev.Bar2.PhysBase <> 0 And targetDev.Bar2.SizeBytes >= 4096 Then
                Dim fifoVirt As VirtualAddress = &H74000000
                Dim pMapped As Pointer To UInt32 = PciMapBar(foundIndex, 2, fifoVirt, False)
                If pMapped <> 0 Then
                    pFifo = pMapped
                    fifoSizeBytes = UInt32(targetDev.Bar2.SizeBytes)
                    If fifoSizeBytes > &H00200000 Then fifoSizeBytes = &H00200000 ' Cap at 2MB

                    ' Initialize Standard VMware FIFO registers
                    pFifo(SVGA_FIFO_MIN) = 16 ' Minimum command offset: 16 bytes (4 dwords)
                    pFifo(SVGA_FIFO_MAX) = fifoSizeBytes
                    pFifo(SVGA_FIFO_NEXT_CMD) = 16
                    pFifo(SVGA_FIFO_STOP) = 16

                    ' Notify hardware that FIFO configuration is complete
                    WriteReg SVGA_REG_CONFIG_DONE, 1
                    hasFifo = True
                    ConsolePrintWithUInt "[SVGA] Hardware FIFO Command Queue Active (Size: ", UInt64(fifoSizeBytes / 1024), " KB at 0x74000000)\r\n"
                Else
                    ConsoleWriteLine "[SVGA] Warning: Failed to map BAR2 FIFO aperture."
                End If
            End If

            ' 4. Enable Hardware SVGA Engine
            WriteReg SVGA_REG_ENABLE, 1
            ConsoleWriteLine "[SVGA] Hardware Acceleration Engine Enabled."

            isAvailable = True
            Initialize = True
        End Function

        ''
        ' @brief Check if SVGA hardware acceleration is active.
        ''
        Public Function IsActive() As Boolean
            IsActive = isAvailable
        End Function

        ''
        ' @brief Push 32-bit DWORD into FIFO command queue.
        ''
        Private Unsafe Sub FifoPush(ByVal val As UInt32)
            If Not hasFifo Or pFifo = 0 Then Exit Sub
            Dim nextCmd As UInt32 = pFifo(SVGA_FIFO_NEXT_CMD)
            Dim maxOffset As UInt32 = pFifo(SVGA_FIFO_MAX)
            Dim minOffset As UInt32 = pFifo(SVGA_FIFO_MIN)

            Dim idx As UInt32 = nextCmd / 4
            pFifo(idx) = val

            nextCmd = nextCmd + 4
            If nextCmd >= maxOffset Then
                nextCmd = minOffset
            End If
            pFifo(SVGA_FIFO_NEXT_CMD) = nextCmd
        End Sub

        ''
        ' @brief Submit hardware damage update rectangle to hypervisor.
        '        Eliminates software full-screen copies and reduces VM-Exit storms.
        ''
        Public Unsafe Sub UpdateRect(ByVal x As Int32, ByVal y As Int32, ByVal w As Int32, ByVal h As Int32)
            If Not isAvailable Then Exit Sub
            If w <= 0 Or h <= 0 Then Exit Sub

            If hasFifo And pFifo <> 0 Then
                FifoPush SVGA_CMD_UPDATE
                FifoPush UInt32(x)
                FifoPush UInt32(y)
                FifoPush UInt32(w)
                FifoPush UInt32(h)
                ' Signal hypervisor of pending commands
                WriteReg SVGA_REG_SYNC, 1
            Else
                ' Fallback: Synchronous register sync
                WriteReg SVGA_REG_SYNC, 1
            End If
        End Sub

        ''
        ' @brief Update hardware cursor coordinates directly on display controller.
        '        Bypasses frontbuffer blit entirely with zero latency.
        ''
        Public Unsafe Sub SetCursorPosition(ByVal x As Int32, ByVal y As Int32, ByVal visible As Boolean)
            If Not isAvailable Then Exit Sub
            If visible Then
                WriteReg SVGA_REG_CURSOR_ON, 1
                WriteReg SVGA_REG_CURSOR_X, UInt32(x)
                WriteReg SVGA_REG_CURSOR_Y, UInt32(y)
            Else
                WriteReg SVGA_REG_CURSOR_ON, 0
            End If
        End Sub

        ''
        ' @brief Flush pending FIFO commands and synchronize with hypervisor.
        ''
        Public Unsafe Sub Sync()
            If Not isAvailable Then Exit Sub
            WriteReg SVGA_REG_SYNC, 1
            While ReadReg(SVGA_REG_BUSY) <> 0
                ' Brief spinlock barrier waiting for hardware completion
            Wend
        End Sub

    End Module

End Namespace

