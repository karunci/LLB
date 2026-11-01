' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: drivers/disp/lfb/LfbDriverMain.bas
' Summary: Generic Linear Framebuffer fallback display driver daemon.
'          Maps physical LFB aperture to user space at 0x78000000,
'          services presentation damage flushes via fast_blit32_nt,
'          and attaches zero-copy shared memory surfaces dynamically.

Import "../../../include/pros.bas"

Module LfbDriverMain

    Public Declare Sub fast_blit32_nt Lib "libc" (ByVal dst As Pointer To UInt32, ByVal src As Pointer To UInt32, ByVal count As UInt64)

    Private dispInfo As DisplayInfo
    Private pFront As Pointer To UInt32 = 0
    Private activeShmId As UInt64 = 0
    Private pShm As Pointer To UInt32 = 0

    ''
    ' @brief Main entry point for Generic Linear Framebuffer Driver Daemon.
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit status code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DRV_LFB] ======================================================="
        ConsoleWriteLine "[DRV_LFB] Generic Linear Framebuffer Driver Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DRV_LFB] Active Driver PID = ", pid, "\r\n"

        ' 2. Query Display Geometry
        If Not GetDisplayInfo(dispInfo) Then
            ConsoleWriteLine "[DRV_LFB] ERR: Failed to query display geometry!"
            user_main = 1
            Exit Function
        End If

        Dim resBuf(64) As Byte
        Dim rIdx As UInt32 = 0
        AppendStr "[DRV_LFB] Mode: ", @resBuf(0), rIdx
        AppendUInt dispInfo.Width, @resBuf(0), rIdx
        AppendStr "x", @resBuf(0), rIdx
        AppendUInt dispInfo.Height, @resBuf(0), rIdx
        AppendStr " @ ", @resBuf(0), rIdx
        AppendUInt dispInfo.Bpp, @resBuf(0), rIdx
        AppendStr " BPP, Pitch: ", @resBuf(0), rIdx
        AppendUInt dispInfo.Pitch, @resBuf(0), rIdx
        AppendStr " bytes", @resBuf(0), rIdx
        resBuf(rIdx) = 0
        ConsoleWriteLine @resBuf(0)

        ' 3. Map Linear Framebuffer Aperture at 0x78000000
        pFront = MapFramebuffer(&H78000000)
        If pFront = 0 Then
            ConsoleWriteLine "[DRV_LFB] ERR: Failed to map physical LFB aperture!"
            user_main = 2
            Exit Function
        End If
        ConsoleWriteLine "[DRV_LFB] Mapped Framebuffer Aperture at 0x78000000"

        ' 4. Register Device Node: 'drv.disp.lfb'
        Dim drvNodeId As UInt64 = NodeRegister(NODE_KIND_DEVICE, "drv.disp.lfb", 7)
        If drvNodeId = 0 Then
            ConsoleWriteLine "[DRV_LFB] ERR: Failed to register 'drv.disp.lfb' node!"
            user_main = 3
            Exit Function
        End If
        ConsolePrintWithUInt "[DRV_LFB] Registered Node 'drv.disp.lfb' -> Node #", drvNodeId, "\r\n"

        ' 5. Active Event Loop
        ConsoleWriteLine "[DRV_LFB] Ready for scanout requests. Entering daemon loop..."
        Dim inPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim seq As UInt64 = 0

        Do
            If SynapsePop(drvNodeId, inPkt) Then
                If inPkt.PacketType = DRV_DISP_GET_CAPS Then
                    Dim caps As DriverDispCaps
                    caps.CapsFlags = DISP_CAP_DIRECT_LFB
                    caps.MaxWidth = UInt32(dispInfo.Width)
                    caps.MaxHeight = UInt32(dispInfo.Height)
                    caps.PreferredBpp = dispInfo.Bpp

                    Dim dName(32) As Byte
                    Dim nIdx As UInt32 = 0
                    AppendStr "Generic LFB Driver", @dName(0), nIdx
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
                                Dim pitchPix As UInt32 = dispInfo.Pitch / 4
                                Dim py As Int32 = y0
                                While py < y1
                                    Dim pixOff As UInt64 = (UInt64(py) * UInt64(pitchPix)) + UInt64(x0)
                                    Dim dstPtr As Pointer To UInt32 = pFront + pixOff
                                    Dim srcPtr As Pointer To UInt32 = pShm + pixOff
                                    fast_blit32_nt dstPtr, srcPtr, clipW
                                    py = py + 1
                                Wend
                            End If
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

