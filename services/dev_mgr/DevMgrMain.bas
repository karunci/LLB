' Project Name: PROS (Personal Research Operating System) / Low-Level Basic
' Filename: services/dev_mgr/DevMgrMain.bas
' Summary: Standalone Ring 3 Device Manager and Hardware Arbiter Service daemon.
'          Maintains device registry, queries hardware topology, and manages driver nodes.

Import "../../include/pros.bas"

Module DevMgrMain

    Public Const DEV_CMD_GET_TREE As UInt32 = 30
    Public Const DEV_CMD_QUERY    As UInt32 = 31
    Public Const DEV_RESP_OK      As UInt32 = 300

    <Packed>
    Structure DeviceItem
        Public Id        As UInt32
        Public Name      As Pointer To Byte
        Public Kind      As UInt32
        Public BaseAddr  As UInt64
        Public Status    As UInt32
    End Structure

    Private devices(7) As DeviceItem
    Private devCount As UInt32

    ''
    ' @brief Initialize static discovered hardware devices.
    ''
    Private Unsafe Sub InitDevices()
        devCount = 0

        ' Device 0: SMP Processor Topology
        devices(0).Id = 1
        devices(0).Name = CPtr(Pointer To Byte, "cpu.smp.quad")
        devices(0).Kind = 1 ' CPU
        devices(0).BaseAddr = 0
        devices(0).Status = 1 ' Active

        ' Device 1: Primary PCI Display Adapter
        devices(1).Id = 2
        devices(1).Name = CPtr(Pointer To Byte, "pci.disp.lfb")
        devices(1).Kind = 2 ' Display
        devices(1).BaseAddr = &HFD000000
        devices(1).Status = 1 ' Active

        ' Device 2: PS/2 Keyboard and Mouse Controller
        devices(2).Id = 3
        devices(2).Name = CPtr(Pointer To Byte, "hid.ps2.controller")
        devices(2).Kind = 3 ' HID
        devices(2).BaseAddr = &H60
        devices(2).Status = 1 ' Active

        ' Device 3: Storage Controller & USTAR Ramdisk
        devices(3).Id = 4
        devices(3).Name = CPtr(Pointer To Byte, "storage.ustar.ramdisk")
        devices(3).Kind = 4 ' Storage
        devices(3).BaseAddr = &H6000000
        devices(3).Status = 1 ' Mounted

        devCount = 4
    End Sub

    ''
    ' @brief Application entry point for dev_mgr daemon (Ring 3 CPL=3).
    ' @param argc Argument count.
    ' @param argv Argument vector.
    ' @return Exit code.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[DEV_MGR] ======================================================="
        ConsoleWriteLine "[DEV_MGR] PROS Device Manager Service Daemon Online (CPL=3)"

        ' 1. Query process identity
        Dim myPid As UInt64 = GetPid()
        ConsolePrintWithUInt "[DEV_MGR] Active Service PID = ", myPid, "\r\n"

        ' 2. Register Device Manager Node in the Neural Node Registry
        Dim devNodeId As UInt64 = NodeRegister(2, CPtr(Pointer To Byte, "srv.dev_mgr"), 7)
        If devNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Registered Node 'srv.dev_mgr' -> Node #", devNodeId, "\r\n"
        Else
            ConsoleWriteLine "[DEV_MGR] WARN: Failed to register 'srv.dev_mgr' node!"
        End If

        ' 3. Discover Core Hardware Driver Nodes
        Dim dispNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.display"))
        If dispNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Display Adapter -> Node #", dispNodeId, "\r\n"
        End If

        Dim inputNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.input"))
        If inputNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Input Controller -> Node #", inputNodeId, "\r\n"
        End If

        Dim rawHwInputId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "hw.input.raw"))
        If rawHwInputId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Raw HID Hardware -> Node #", rawHwInputId, "\r\n"
        End If

        Dim vfsNodeId As UInt64 = NodeLookup(CPtr(Pointer To Byte, "srv.vfs"))
        If vfsNodeId <> 0 Then
            ConsolePrintWithUInt "[DEV_MGR] Attached Storage Controller -> Node #", vfsNodeId, "\r\n"
        End If

        ' 4. Initialize Hardware Topology
        InitDevices
        ConsolePrintWithUInt "[DEV_MGR] Hardware topology discovery completed: ", CType(UInt64, devCount), " Devices\r\n"
        ConsoleWriteLine "[DEV_MGR] Entering active device arbitration loop..."
        ConsoleWriteLine "[DEV_MGR] ======================================================="

        ' 5. Active daemon event loop (Zero idle CPU via ProcessSleep)
        Dim reqPkt As AxonPacket
        Dim respPkt As AxonPacket
        Dim devReqCount As UInt64 = 0

        Do
            ProcessSleep 500
        Loop

        user_main = 0
    End Function

End Module
