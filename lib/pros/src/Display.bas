' Project Name: Personal Research Operating System (PROS) / Low-Level Basic
' Filename: lib/pros/src/Display.bas
' Summary: High-level Display Port Client and Driver Protocol implementation for Ring 3.

Import Pros.Sys
Import Pros.Sys.RawSyscall
Import Pros.Sys.Process In "Process.bas"
Import Pros.Nodes In "Node.bas"
Import Pros.String In "String.bas"

Namespace Pros.Driver

    <Packed>
    Public Structure DisplayInfo
        Public Width    As Int32
        Public Height   As Int32
        Public Pitch    As UInt32
        Public Bpp      As UInt32
        Public PhysAddr As UInt64
    End Structure

    ' Display Driver IPC Protocol Message Types (Synapse Control Plane)
    Public Const DRV_DISP_INIT          As UInt32 = &H0701
    Public Const DRV_DISP_GET_CAPS      As UInt32 = &H0702
    Public Const DRV_DISP_FLUSH_RECT    As UInt32 = &H0703
    Public Const DRV_DISP_SET_CURSOR    As UInt32 = &H0704
    Public Const DRV_DISP_SET_MODE      As UInt32 = &H0705

    Public Const DRV_DISP_RESP_OK       As UInt32 = 700
    Public Const DRV_DISP_RESP_ERROR    As UInt32 = 701

    ' Display Driver Hardware Capability Flags
    Public Const DISP_CAP_DIRECT_LFB       As UInt32 = &H0001 ' Memory-mapped framebuffer
    Public Const DISP_CAP_HARDWARE_FIFO    As UInt32 = &H0002 ' Command FIFO queue available
    Public Const DISP_CAP_HARDWARE_CURSOR  As UInt32 = &H0004 ' Independent cursor hardware plane
    Public Const DISP_CAP_ACCEL_BLIT       As UInt32 = &H0008 ' GPU 2D hardware blit / fill

    <Packed>
    Public Structure DriverDispCaps
        Public CapsFlags      As UInt32
        Public MaxWidth       As UInt32
        Public MaxHeight      As UInt32
        Public PreferredBpp   As UInt32
        Public DriverName(32) As Byte
    End Structure

    <Packed>
    Public Structure DriverDispFlushReq
        Public X       As Int32
        Public Y       As Int32
        Public Width   As Int32
        Public Height  As Int32
        Public ShmId   As UInt64
        Public Offset  As UInt64
    End Structure

    <Packed>
    Public Structure DriverDispCursorReq
        Public Visible   As Boolean
        Public Reserved  As Byte
        Public X         As Int16
        Public Y         As Int16
        Public SpriteShm As UInt64
    End Structure

    Public Module Display

        ''
        ' @brief Query active display resolution and framebuffer geometry via microkernel syscall.
        ' @param info Reference to DisplayInfo structure to fill.
        ' @return True if display information was successfully retrieved.
        ''
        Public Unsafe Function GetInfo(ByRef info As DisplayInfo) As Boolean
            Dim infoPtr As UInt64 = UInt64(AddressOf info)
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call1(SYS_FB_GET_INFO, infoPtr)
            GetInfo = (res = 1)
        End Function

        ''
        ' @brief Map linear framebuffer memory aperture into calling process space.
        ' @param targetVaddr Desired virtual address in userspace (e.g. 0x78000000).
        ' @return Pointer to mapped 32-bit pixel buffer, or 0 on failure.
        ''
        Public Unsafe Function Map(ByVal targetVaddr As UInt64) As Pointer To UInt32
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call1(SYS_FB_MAP, targetVaddr)
            If res = 1 Then
                Map = *UInt32(targetVaddr)
            Else
                Map = Nothing
            End If
        End Function

    End Module

    Public Module DisplayClient

        Private g_dispSrvNodeId As UInt64 = 0
        Private g_clientNodeId  As UInt64 = 0
        Private g_synChan       As UInt64 = 0
        Private g_connected     As Boolean = False
        Private g_seq           As UInt64 = 1

        ''
        ' @brief Internal helper to establish connection to srv.display.
        ''
        Private Unsafe Function EnsureConnected() As Boolean
            If g_connected Then
                EnsureConnected = True
                Exit Function
            End If

            g_dispSrvNodeId = Pros.Nodes.NodeRegistry.Lookup("srv.display")
            If g_dispSrvNodeId = 0 Then
                EnsureConnected = False
                Exit Function
            End If

            Dim myPid As UInt64 = Pros.Sys.Process.GetPid()
            Dim cName(32) As Byte
            Dim cIdx As UInt32 = 0
            Pros.String.StringUtil.AppendStr "disp_cli.", Pointer To Byte(@cName(0)), cIdx
            Pros.String.StringUtil.AppendUInt myPid, Pointer To Byte(@cName(0)), cIdx
            cName(cIdx) = 0

            g_clientNodeId = Pros.Nodes.NodeRegistry.Lookup(Pointer To Byte(@cName(0)))
            If g_clientNodeId = 0 Then
                g_clientNodeId = Pros.Nodes.NodeRegistry.Register(1, Pointer To Byte(@cName(0)), 7)
            End If

            g_synChan = Pros.Nodes.NodeRegistry.Connect(g_clientNodeId, g_dispSrvNodeId, 7)
            If g_synChan = 0 Then
                EnsureConnected = False
                Exit Function
            End If

            g_connected = True
            EnsureConnected = True
        End Function

        ''
        ' @brief Connect to the active Display Port Server (srv.display).
        ' @return True if connected successfully.
        ''
        Public Unsafe Function Connect() As Boolean
            Connect = EnsureConnected()
        End Function

        ''
        ' @brief Present a damaged rectangular region to the display service for scanout.
        ' @param rx Dirty bounding box left coordinate.
        ' @param ry Dirty bounding box top coordinate.
        ' @param rw Dirty bounding box width.
        ' @param rh Dirty bounding box height.
        ' @param shmId Shared memory segment ID containing backbuffer pixels.
        ' @return True if presentation packet was queued successfully.
        ''
        Public Unsafe Function PresentRect(ByVal rx As Int32, ByVal ry As Int32, ByVal rw As Int32, ByVal rh As Int32, ByVal shmId As UInt64) As Boolean
            If Not EnsureConnected() Then
                PresentRect = False
                Exit Function
            End If

            Dim req As DriverDispFlushReq
            req.X = rx
            req.Y = ry
            req.Width = rw
            req.Height = rh
            req.ShmId = shmId
            req.Offset = 0

            Dim pkt As Pros.Nodes.AxonPacket
            pkt.Sequence = g_seq
            g_seq = g_seq + 1
            pkt.PacketType = DRV_DISP_FLUSH_RECT
            pkt.SourceNode = g_clientNodeId
            pkt.TargetNode = g_dispSrvNodeId
            pkt.PayloadLength = 32 ' sizeof(DriverDispFlushReq)

            Dim pReq As Pointer To Byte = Pointer To Byte(@req)
            Dim i As UInt32 = 0
            While i < 32
                pkt.Payload(i) = pReq(i)
                i = i + 1
            Wend

            PresentRect = Pros.Nodes.NodeRegistry.Push(g_synChan, pkt)
        End Function

        ''
        ' @brief Query active display hardware capabilities from the Display Port Server.
        ' @param caps Reference to DriverDispCaps structure to populate.
        ' @return True if capabilities were queried successfully.
        ''
        Public Unsafe Function GetCaps(ByRef caps As DriverDispCaps) As Boolean
            If Not EnsureConnected() Then
                GetCaps = False
                Exit Function
            End If

            Dim pkt As Pros.Nodes.AxonPacket
            pkt.Sequence = g_seq
            g_seq = g_seq + 1
            pkt.PacketType = DRV_DISP_GET_CAPS
            pkt.SourceNode = g_clientNodeId
            pkt.TargetNode = g_dispSrvNodeId
            pkt.PayloadLength = 0

            If Not Pros.Nodes.NodeRegistry.Push(g_synChan, pkt) Then
                GetCaps = False
                Exit Function
            End If

            Dim respPkt As Pros.Nodes.AxonPacket
            Dim attempts As UInt32 = 0
            While attempts < 50
                If Pros.Nodes.NodeRegistry.Pop(g_clientNodeId, respPkt) Then
                    If respPkt.PacketType = DRV_DISP_GET_CAPS And respPkt.PayloadLength >= 48 Then
                        Dim pCaps As Pointer To DriverDispCaps = CPtr(Pointer To DriverDispCaps, @respPkt.Payload(0))
                        caps = pCaps(0)
                        GetCaps = True
                        Exit Function
                    End If
                End If
                Pros.Sys.Process.Sleep 2
                attempts = attempts + 1
            Wend

            GetCaps = False
        End Function

        ''
        ' @brief Move or toggle the hardware/software cursor plane.
        ' @param visible True to show cursor sprite.
        ' @param x Screen X coordinate.
        ' @param y Screen Y coordinate.
        ' @param spriteShm Optional shared memory segment ID containing cursor sprite pixels.
        ' @return True if cursor packet was sent successfully.
        ''
        Public Unsafe Function SetCursor(ByVal visible As Boolean, ByVal x As Int32, ByVal y As Int32, ByVal spriteShm As UInt64) As Boolean
            If Not EnsureConnected() Then
                SetCursor = False
                Exit Function
            End If

            Dim req As DriverDispCursorReq
            req.Visible = visible
            req.Reserved = 0
            req.X = Int16(x)
            req.Y = Int16(y)
            req.SpriteShm = spriteShm

            Dim pkt As Pros.Nodes.AxonPacket
            pkt.Sequence = g_seq
            g_seq = g_seq + 1
            pkt.PacketType = DRV_DISP_SET_CURSOR
            pkt.SourceNode = g_clientNodeId
            pkt.TargetNode = g_dispSrvNodeId
            pkt.PayloadLength = 16 ' sizeof(DriverDispCursorReq)

            Dim pReq As Pointer To Byte = Pointer To Byte(@req)
            Dim i As UInt32 = 0
            While i < 16
                pkt.Payload(i) = pReq(i)
                i = i + 1
            Wend

            SetCursor = Pros.Nodes.NodeRegistry.Push(g_synChan, pkt)
        End Function

    End Module

End Namespace
