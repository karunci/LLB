' Project Name: PROS (Personal Research Operating System)
' Filename: services/genesis/GenesisMain.bas
' Summary: Standalone Ring 3 Genesis PID 1 Root Coordinator daemon.
'          Initializes root system control plane, orchestrates service startup,
'          and monitors core operating system subsystems.

Import "../../include/pros.bas"

Module GenesisMain

    ''
    ' @brief Append unsigned 64-bit integer formatted as ASCII into buffer.
    ' @param val Unsigned integer to format.
    ' @param buf Output buffer.
    ' @param outIdx Current buffer write index (updated on return).
    ''
    Private Unsafe Sub AppendUInt(ByVal val As UInt64, ByVal buf As Pointer To Byte, ByRef outIdx As UInt32)
        If val = 0 Then
            buf(outIdx) = 48 ' '0'
            outIdx = outIdx + 1
            Exit Sub
        End If
        Dim tmp(23) As Byte
        Dim tIdx As UInt32 = 0
        Dim v As UInt64 = val
        While v > 0
            tmp(tIdx) = CType(Byte, (v Mod 10) + 48)
            v = v / 10
            tIdx = tIdx + 1
        Wend
        While tIdx > 0
            tIdx = tIdx - 1
            buf(outIdx) = tmp(tIdx)
            outIdx = outIdx + 1
        Wend
    End Sub

    ''
    ' @brief Main application entry point for PROS Genesis PID 1 Root Orchestrator.
    ' @param argc Argument count.
    ' @param argv Argument string vector.
    ' @return Exit code (0 for success).
    ''
    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        ConsoleWriteLine "[GENESIS] ======================================================="
        ConsoleWriteLine "[GENESIS] PROS Genesis Root Orchestrator Online (PID 1, CPL=3)"

        ' 1. Verify Process Identity
        Dim pid As UInt64 = GetPid()
        ConsolePrintWithUInt "[GENESIS] Active Orchestrator PID = ", pid, "\r\n"

        ' 2. Register Root System Node: 'sys.genesis' (Kind: System = 1, Caps: RWN = 7)
        Dim rootName(32) As Byte
        rootName(0)  = 115 ' 's'
        rootName(1)  = 121 ' 'y'
        rootName(2)  = 115 ' 's'
        rootName(3)  = 46  ' '.'
        rootName(4)  = 103 ' 'g'
        rootName(5)  = 101 ' 'e'
        rootName(6)  = 110 ' 'n'
        rootName(7)  = 101 ' 'e'
        rootName(8)  = 115 ' 's'
        rootName(9)  = 105 ' 'i'
        rootName(10) = 115 ' 's'
        rootName(11) = 0
        Dim rootNodeId As UInt64 = NodeRegister(NODE_KIND_SYSTEM, @rootName(0), 7)
        ConsolePrintWithUInt "[GENESIS] Registered Root System Node 'sys.genesis' -> Node #", rootNodeId, "\r\n"

        ' 3. Discover Service Supervisor: 'srv.plexus_mgr'
        Dim plexusName(32) As Byte
        plexusName(0)  = 115 ' 's'
        plexusName(1)  = 114 ' 'r'
        plexusName(2)  = 118 ' 'v'
        plexusName(3)  = 46  ' '.'
        plexusName(4)  = 112 ' 'p'
        plexusName(5)  = 108 ' 'l'
        plexusName(6)  = 101 ' 'e'
        plexusName(7)  = 120 ' 'x'
        plexusName(8)  = 117 ' 'u'
        plexusName(9)  = 115 ' 's'
        plexusName(10) = 95  ' '_'
        plexusName(11) = 109 ' 'm'
        plexusName(12) = 103 ' 'g'
        plexusName(13) = 114 ' 'r'
        plexusName(14) = 0
        Dim plexusNodeId As UInt64 = NodeLookup(@plexusName(0))
        Dim synPlexus As UInt64 = 0
        If plexusNodeId <> 0 Then
            ConsolePrintWithUInt "[GENESIS] Connected to Service Supervisor -> Node #", plexusNodeId, "\r\n"
            synPlexus = SynapseConnect(rootNodeId, plexusNodeId, 7)
            If synPlexus <> 0 Then
                ConsolePrintWithUInt "[GENESIS] Established Synapse Channel to Plexus Mgr -> Channel #", synPlexus, "\r\n"
            End If
        End If

        ' 4. Discover Device Arbiter: 'srv.dev_mgr'
        Dim devMgrName(32) As Byte
        devMgrName(0)  = 115 ' 's'
        devMgrName(1)  = 114 ' 'r'
        devMgrName(2)  = 118 ' 'v'
        devMgrName(3)  = 46  ' '.'
        devMgrName(4)  = 100 ' 'd'
        devMgrName(5)  = 101 ' 'e'
        devMgrName(6)  = 118 ' 'v'
        devMgrName(7)  = 95  ' '_'
        devMgrName(8)  = 109 ' 'm'
        devMgrName(9)  = 103 ' 'g'
        devMgrName(10) = 114 ' 'r'
        devMgrName(11) = 0
        Dim devMgrNodeId As UInt64 = NodeLookup(@devMgrName(0))
        Dim synDevMgr As UInt64 = 0
        If devMgrNodeId <> 0 Then
            ConsolePrintWithUInt "[GENESIS] Connected to Device Arbiter -> Node #", devMgrNodeId, "\r\n"
            synDevMgr = SynapseConnect(rootNodeId, devMgrNodeId, 7)
            If synDevMgr <> 0 Then
                ConsolePrintWithUInt "[GENESIS] Established Synapse Channel to Device Arbiter -> Channel #", synDevMgr, "\r\n"
            End If
        End If

        ' 5. Root Orchestration Loop
        ConsoleWriteLine "[GENESIS] Root Orchestration completed. Entering persistent supervisor loop..."
        ConsoleWriteLine "[GENESIS] ======================================================="

        Dim heartbeatCount As UInt64 = 0
        Do
            ProcessSleep 5000
            heartbeatCount = heartbeatCount + 1
        Loop

        user_main = 0
    End Function

End Module
