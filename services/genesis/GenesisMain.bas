' Project Name: PROS (Personal Research Operating System)
' Filename: services/genesis/GenesisMain.bas
' Summary: Standalone Ring 3 Genesis PID 1 Root Coordinator daemon.
'          Initializes root system control plane, orchestrates service startup,
'          and monitors core operating system subsystems.

Import "../../include/pros.bas"

Module GenesisMain

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
        Dim rootName As String = "sys.genesis"
        Dim rootNodeId As UInt64 = NodeRegister(NODE_KIND_SYSTEM, rootName, 7)
        ConsolePrintWithUInt "[GENESIS] Registered Root System Node 'sys.genesis' -> Node #", rootNodeId, "\r\n"

        ' 3. Discover Service Supervisor: 'srv.plexus_mgr'
        Dim plexusName As String = "srv.plexus_mgr"
        Dim plexusNodeId As UInt64 = NodeLookup(plexusName)
        Dim synPlexus As UInt64 = 0
        If plexusNodeId <> 0 Then
            ConsolePrintWithUInt "[GENESIS] Connected to Service Supervisor -> Node #", plexusNodeId, "\r\n"
            synPlexus = SynapseConnect(rootNodeId, plexusNodeId, 7)
            If synPlexus <> 0 Then
                ConsolePrintWithUInt "[GENESIS] Established Synapse Channel to Plexus Mgr -> Channel #", synPlexus, "\r\n"
            End If
        End If

        ' 4. Discover Device Arbiter: 'srv.dev_mgr'
        Dim devMgrName As String = "srv.dev_mgr"
        Dim devMgrNodeId As UInt64 = NodeLookup(devMgrName)
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
