' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: drivers/disp/svga/SvgaDriverMain.bas
' Summary: VMware SVGA-II / VirtualBox VBoxSVGA hardware acceleration driver daemon.
'          Detects PCI 0x15AD:0x0405, negotiates SVGA_ID_2, initializes hardware
'          FIFO command queue, and offloads presentation damage updates and cursor planes.

Import "../../../include/pros.bas"

Module SvgaDriverMain

    Public Declare Sub fast_blit32_nt Lib "libc" (ByVal dst As Pointer To UInt32, ByVal src As Pointer To UInt32, ByVal count As UInt64)

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

    ' Hardware State
    Private ioBase        As UInt16 = 0
    Private pFifo         As Pointer To UInt32 = 0
    Private fifoSizeBytes As UInt32 = 0
    Private hasFifo       As Boolean = False
    Private pFront        As Pointer To UInt32 = 0
    Private dispInfo      As DisplayInfo
    Private activeShmId   As UInt64 = 0
    Private pShm          As Pointer To UInt32 = 0

    ''
    ' @brief Read a 32-bit register from VMware SVGA-II display controller.
    ''
    Private Unsafe Function ReadReg(ByVal regIdx As UInt32) As UInt32
        PortOut32 ioBase + 0, regIdx
        ReadReg = PortIn32(ioBase + 1)
    End Function

    ''
    ' @brief Write a 32-bit register to VMware SVGA-II display controller.
    ''
    Private Unsafe Sub WriteReg(ByVal regIdx As UInt32, ByVal val As UInt32)
        PortOut32 ioBase + 0, regIdx
        PortOut32 ioBase + 1, val
    End Sub

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
    ' @brief Submit hardware damage update rectangle to hypervisor FIFO.
    ''
    Private Unsafe Sub UpdateRect(ByVal x As Int32, ByVal y As Int32, ByVal w As Int32, ByVal h As Int32)
        If w <= 0 Or h <= 0 Then Exit Sub

        If hasFifo And pFifo <> 0 Then
            FifoPush SVGA_CMD_UPDATE
            FifoPush UInt32(x)
            FifoPush UInt32(y)
            FifoPush UInt32(w)
            FifoPush UInt32(h)
            WriteReg SVGA_REG_SYNC, 1
        Else
            WriteReg SVGA_REG_SYNC, 1
        End If
    End Sub

    ''
    ' @brief Main entry point for VMware SVGA-II Hardware Display Driver Daemon.
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DRV_SVGA] ======================================================="
        ConsoleWriteLine "[DRV_SVGA] VMware SVGA-II Hardware Acceleration Driver Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DRV_SVGA] Active Driver PID = ", pid, "\r\n"

        ' 2. Probe PCI configuration space for 0x15AD:0x0405
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
            ConsoleWriteLine "[DRV_SVGA] VMware SVGA-II device (0x15AD:0x0405) not present on PCI bus."
            ' Yield peacefully; system will use generic LFB fallback driver
            Do
                ProcessSleep 10000
            Loop
            user_main = 0
            Exit Function
        End If

        ' Extract I/O Port base from BAR0
        If Not targetDev.Bar0.IsIo Or targetDev.Bar0.PhysBase = 0 Then
            ConsoleWriteLine "[DRV_SVGA] Error: BAR0 is not an I/O space aperture."
            user_main = 1
            Exit Function
        End If

        ioBase = UInt16(targetDev.Bar0.PhysBase And &HFFFF)
        ConsolePrintWithUInt "[DRV_SVGA] Located SVGA-II Controller at I/O Port: 0x", UInt64(ioBase), "\r\n"

        ' 3. Negotiate SVGA_ID_2 protocol
        WriteReg SVGA_REG_ID, SVGA_ID_2
        Dim readId As UInt32 = ReadReg(SVGA_REG_ID)
        If readId <> SVGA_ID_2 Then
            ConsolePrintWithUInt "[DRV_SVGA] Protocol negotiation failed. Returned ID: 0x", UInt64(readId), "\r\n"
            user_main = 2
            Exit Function
        End If
        ConsoleWriteLine "[DRV_SVGA] SVGA_ID_2 Protocol Negotiated Successfully!"

        ' 4. Read Device Capabilities and Memory Dimensions
        Dim vramSize As UInt32 = ReadReg(SVGA_REG_VRAM_SIZE)
        Dim fbSize As UInt32 = ReadReg(SVGA_REG_FB_SIZE)
        Dim hwCaps As UInt32 = ReadReg(SVGA_REG_CAPABILITIES)
        ConsolePrintWithUInt "[DRV_SVGA] VRAM Size: ", UInt64(vramSize / 1024), " KB\r\n"
        ConsolePrintWithUInt "[DRV_SVGA] Hardware Capabilities: 0x", UInt64(hwCaps), "\r\n"

        ' 5. Map FIFO Command Buffer from BAR2 (if present)
        If targetDev.Bar2.PhysBase <> 0 And targetDev.Bar2.SizeBytes >= 4096 Then
            Dim fifoVirt As VirtualAddress = &H74000000
            Dim pMapped As Pointer To UInt32 = PciMapBar(foundIndex, 2, fifoVirt, False)
            If pMapped <> 0 Then
                pFifo = pMapped
                fifoSizeBytes = UInt32(targetDev.Bar2.SizeBytes)
                If fifoSizeBytes > &H00200000 Then fifoSizeBytes = &H00200000 ' Cap at 2MB

                pFifo(SVGA_FIFO_MIN) = 16
                pFifo(SVGA_FIFO_MAX) = fifoSizeBytes
                pFifo(SVGA_FIFO_NEXT_CMD) = 16
                pFifo(SVGA_FIFO_STOP) = 16

                WriteReg SVGA_REG_CONFIG_DONE, 1
                hasFifo = True
                ConsolePrintWithUInt "[DRV_SVGA] Hardware FIFO Command Queue Active (Size: ", UInt64(fifoSizeBytes / 1024), " KB at 0x74000000)\r\n"
            Else
                ConsoleWriteLine "[DRV_SVGA] Warning: Failed to map BAR2 FIFO aperture."
            End If
        End If

        ' 6. Enable Hardware SVGA Engine
        WriteReg SVGA_REG_ENABLE, 1
        ConsoleWriteLine "[DRV_SVGA] Hardware Acceleration Engine Enabled."

        ' 7. Map Physical Framebuffer Aperture to User Space at 0x78000000
        pFront = MapFramebuffer(&H78000000)
        If pFront = 0 Then
            ConsoleWriteLine "[DRV_SVGA] ERR: Failed to map physical VRAM aperture!"
            user_main = 3
            Exit Function
        End If
        ConsoleWriteLine "[DRV_SVGA] Mapped VRAM Aperture at 0x78000000"

        ' Query display geometry
        If Not GetDisplayInfo(dispInfo) Then
            ConsoleWriteLine "[DRV_SVGA] WARN: Could not query display info; defaulting to 1024x768"
            dispInfo.Width = 1024
            dispInfo.Height = 768
            dispInfo.Pitch = 4096
            dispInfo.Bpp = 32
        End If

        ' 8. Register Node 'drv.disp.svga'
        Dim drvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, "drv.disp.svga", 7)
        If drvNodeId = 0 Then
            ConsoleWriteLine "[DRV_SVGA] ERR: Failed to register 'drv.disp.svga' node!"
            user_main = 4
            Exit Function
        End If
        ConsolePrintWithUInt "[DRV_SVGA] Registered Node 'drv.disp.svga' -> Node #", drvNodeId, "\r\n"

        ' 9. Active Event Loop
        ConsoleWriteLine "[DRV_SVGA] Hardware accelerator ready. Entering daemon loop..."
        Dim inPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim seq As UInt64 = 0

        Do
            If SynapsePop(drvNodeId, inPkt) Then
                If inPkt.PacketType = DRV_DISP_GET_CAPS Then
                    Dim caps As DriverDispCaps
                    caps.CapsFlags = DISP_CAP_DIRECT_LFB Or DISP_CAP_HARDWARE_FIFO Or DISP_CAP_HARDWARE_CURSOR Or DISP_CAP_ACCEL_BLIT
                    caps.MaxWidth = UInt32(dispInfo.Width)
                    caps.MaxHeight = UInt32(dispInfo.Height)
                    caps.PreferredBpp = dispInfo.Bpp

                    Dim dName(32) As Byte
                    Dim nIdx As UInt32 = 0
                    AppendStr "VMware SVGA-II Accelerator", @dName(0), nIdx
                    dName(nIdx) = 0
                    Dim di As UInt32 = 0
                    While di < 32
                        caps.DriverName(di) = dName(di)
                        di = di + 1
                    Wend

                    respPkt.Sequence = seq
                    seq = seq + 1
                    respPkt.PacketType = DRV_DISP_GET_CAPS
                    respPkt.SourceNode = drvNodeId
                    respPkt.TargetNode = inPkt.SourceNode
                    respPkt.PayloadLength = 48 ' sizeof(DriverDispCaps)

                    Dim pCapsByte As Pointer To Byte = CPtr(Pointer To Byte, @caps)
                    Dim bi As UInt32 = 0
                    While bi < 48
                        respPkt.Payload(bi) = pCapsByte(bi)
                        bi = bi + 1
                    Wend

                    Dim replyChan As UInt64 = SynapseConnect(drvNodeId, inPkt.SourceNode, 7)
                    If replyChan <> 0 Then
                        SynapsePush replyChan, respPkt
                    End If

                ElseIf inPkt.PacketType = DRV_DISP_FLUSH_RECT Then
                    If inPkt.PayloadLength >= 32 Then
                        Dim pReq As Pointer To DriverDispFlushReq = CPtr(Pointer To DriverDispFlushReq, @inPkt.Payload(0))

                        ' Attach Shared Memory segment if changed
                        If pReq.ShmId <> activeShmId Then
                            If activeShmId <> 0 Then
                                ShmemDetach activeShmId
                                activeShmId = 0
                                pShm = 0
                            End If
                            Dim mapped As UInt64 = ShmemAttach(pReq.ShmId, &H6E000000)
                            If mapped <> 0 Then
                                activeShmId = pReq.ShmId
                                pShm = CPtr(Pointer To UInt32, &H6E000000)
                            End If
                        End If

                        ' Perform burst blit to VRAM aperture
                        If pShm <> 0 And pFront <> 0 Then
                            Dim x0 As Int32 = pReq.X
                            Dim y0 As Int32 = pReq.Y
                            Dim x1 As Int32 = pReq.X + pReq.Width
                            Dim y1 As Int32 = pReq.Y + pReq.Height

                            If x0 < 0 Then x0 = 0
                            If y0 < 0 Then y0 = 0
                            If x1 > dispInfo.Width Then x1 = dispInfo.Width
                            If y1 > dispInfo.Height Then y1 = dispInfo.Height

                            If x0 < x1 And y0 < y1 Then
                                Dim clipW As Int32 = x1 - x0
                                Dim clipH As Int32 = y1 - y0
                                Dim pitchPix As UInt32 = dispInfo.Pitch / 4
                                Dim py As Int32 = y0
                                While py < y1
                                    Dim pixOff As UInt64 = (UInt64(py) * UInt64(pitchPix)) + UInt64(x0)
                                    Dim dstPtr As Pointer To UInt32 = pFront + pixOff
                                    Dim srcPtr As Pointer To UInt32 = pShm + pixOff
                                    fast_blit32_nt dstPtr, srcPtr, clipW
                                    py = py + 1
                                Wend

                                ' Submit FIFO damage update to hypervisor
                                UpdateRect x0, y0, clipW, clipH
                            End If
                        End If
                    End If

                ElseIf inPkt.PacketType = DRV_DISP_SET_CURSOR Then
                    If inPkt.PayloadLength >= 16 Then
                        Dim pCur As Pointer To DriverDispCursorReq = CPtr(Pointer To DriverDispCursorReq, @inPkt.Payload(0))
                        If pCur.Visible Then
                            WriteReg SVGA_REG_CURSOR_ON, 1
                            WriteReg SVGA_REG_CURSOR_X, UInt32(pCur.X)
                            WriteReg SVGA_REG_CURSOR_Y, UInt32(pCur.Y)
                        Else
                            WriteReg SVGA_REG_CURSOR_ON, 0
                        End If
                    End If
                End If
            Else
                ProcessSleep 2
            End If
        Loop

        user_main = 0
    End Function

End Module

