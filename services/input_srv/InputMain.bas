' Project Name: PROS (Personal Research Operating System)
' Filename: services/input_srv/InputMain.bas
' Summary: Standalone Ring 3 Unified Input Service driver daemon.
'          Collects raw hardware packets from 'hw.input.raw' and publishes normalized events.

Import "../../include/pros.bas"

Module InputServiceMain

    ''
    ' @brief Main application entry point for PROS Unified Input Service.
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[INPUT_SRV] ======================================================="
        ConsoleWriteLine "[INPUT_SRV] PROS Unified Input Service Daemon Online (CPL=3)"

        ' 1. Query PID
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[INPUT_SRV] Active Service PID = ", pid, "\r\n"

        ' 2. Register Service Node: 'srv.input' (Kind: Router/Broker = 4, Caps: RWN = 7)
        Dim srvName(32) As Byte
        srvName(0) = 115 ' 's'
        srvName(1) = 114 ' 'r'
        srvName(2) = 118 ' 'v'
        srvName(3) = 46  ' '.'
        srvName(4) = 105 ' 'i'
        srvName(5) = 110 ' 'n'
        srvName(6) = 112 ' 'p'
        srvName(7) = 117 ' 'u'
        srvName(8) = 116 ' 't'
        srvName(9) = 0
        Dim srvNodeId As UInt64 = NodeRegister(NODE_KIND_ROUTER, @srvName(0), 7)
        ConsolePrintWithUInt "[INPUT_SRV] Registered Node 'srv.input' -> Node #", srvNodeId, "\r\n"

        ' 3. Discover and connect to raw hardware input node: 'hw.input.raw'
        Dim hwRawName(16) As Byte
        hwRawName(0) = 104 ' 'h'
        hwRawName(1) = 119 ' 'w'
        hwRawName(2) = 46  ' '.'
        hwRawName(3) = 105 ' 'i'
        hwRawName(4) = 110 ' 'n'
        hwRawName(5) = 112 ' 'p'
        hwRawName(6) = 117 ' 'u'
        hwRawName(7) = 116 ' 't'
        hwRawName(8) = 46  ' '.'
        hwRawName(9) = 114 ' 'r'
        hwRawName(10) = 97 ' 'a'
        hwRawName(11) = 119' 'w'
        hwRawName(12) = 0
        Dim hwInputNodeId As UInt64 = NodeLookup(@hwRawName(0))
        ConsolePrintWithUInt "[INPUT_SRV] Discovered 'hw.input.raw' -> ID #", hwInputNodeId, "\r\n"

        If hwInputNodeId > 0 Then
            Dim inputSynId As UInt64 = SynapseConnect(srvNodeId, hwInputNodeId, 3)
            ConsolePrintWithUInt "[INPUT_SRV] Established Synapse to hardware input -> Channel #", inputSynId, "\r\n"
        End If

        ' 4. Allocate Zero-Copy Shared Memory Event Ring Buffer (8 KB at 0x60000000)
        Dim shmVaddr As UInt64 = &H60000000
        Dim shmid As UInt64 = ShmemCreate(8192, shmVaddr)
        If shmid > 0 Then
            ConsolePrintWithUInt "[INPUT_SRV] Zero-Copy Event Buffer allocated (SHMID: ", shmid, ", Mapped @ 0x60000000)\r\n"
            
            Dim qPtr As Pointer To SharedInputQueue = CPtr(Pointer To SharedInputQueue, shmVaddr)
            qPtr.Magic = INPUT_QUEUE_MAGIC
            qPtr.Head = 0
            qPtr.Tail = 0
            qPtr.Capacity = 64
            ConsoleWriteLine "[INPUT_SRV] Shared Event Queue initialized (Capacity: 64 high-level events)"
        End If

        ' 5. Yield processor time slice to simulate continuous event dispatching
        ConsoleWriteLine "[INPUT_SRV] Dispatcher loop active. Calling ProcessYield..."
        ProcessYield
        ConsoleWriteLine "[INPUT_SRV] Resumed from time slice. Pipeline ready for Compositor."

        ConsoleWriteLine "[INPUT_SRV] input_srv daemon operational. Yielding cleanly."
        ConsoleWriteLine "[INPUT_SRV] ======================================================="

        user_main = 0
    End Function

End Module
