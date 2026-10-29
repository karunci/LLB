' Project Name: Low-Level Basic Node Registration & Lookup Stress Test Suite
' Filename: tests/node_stress_test/src/NodeStressMain.bas
' Summary: Comprehensive empirical stress test for Node Registration & Lookup parameters,
'          including boundary string lengths, dynamic string building, case sensitivity,
'          truncation invariants, capacity limits, and String ABI interop.

Import "../../../include/pros.bas"

Module NodeStressMain

    Private Const TEST_MAX_NODES As UInt32 = 64

    <Packed>
    Private Structure MockNodeItem
        Public NodeId       As UInt64
        Public Kind         As UInt32
        Public OwnerPid     As UInt64
        Public Capabilities As UInt32
        Public Flags        As UInt32
        Public Name(32)     As Byte
    End Structure

    Private g_nodes(64) As MockNodeItem
    Private g_nextNodeId As UInt64 = 1000

    Private testsRun As UInt32 = 0
    Private testsPassed As UInt32 = 0
    Private testsFailed As UInt32 = 0

    ''
    ' @brief Dual-mode printer for stdout output in QEMU userland and microkernel.
    ''
    Private Unsafe Sub DualPrint(ByVal s As String)
        If s = 0 Then Exit Sub
        Dim length As UInt64 = StrLen(s)
        ' PROS Microkernel console write: %rax=1, %rdi=s, %rsi=length
        Asm "movq $1, %%rax; movq %0, %%rdi; movq %1, %%rsi; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rcx", "r11", "memory"
        ' Linux userland stdout write: %rax=1, %rdi=1 (stdout), %rsi=s, %rdx=length
        Asm "movq $1, %%rax; movq $1, %%rdi; movq %0, %%rsi; movq %1, %%rdx; syscall" : : "r"(s), "r"(length) : "rax", "rdi", "rsi", "rdx", "rcx", "r11", "memory"
    End Sub

    Private Unsafe Sub PrintMsg(ByVal s As String)
        DualPrint s
        DualPrint "\r\n"
    End Sub

    Private Unsafe Sub AssertTrue(ByVal cond As Boolean, ByVal testName As String)
        testsRun = testsRun + 1
        Dim nbuf(16) As Byte
        Dim nidx As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @nbuf(0), nidx
        nbuf(nidx) = 0

        If cond Then
            testsPassed = testsPassed + 1
            DualPrint "  [PASS] #"
            DualPrint @nbuf(0)
            DualPrint " - "
            PrintMsg testName
        Else
            testsFailed = testsFailed + 1
            DualPrint "  [FAIL] #"
            DualPrint @nbuf(0)
            DualPrint ": "
            PrintMsg testName
        End If
    End Sub

    Private Unsafe Sub AssertFalse(ByVal cond As Boolean, ByVal testName As String)
        If cond Then
            AssertTrue False, testName
        Else
            AssertTrue True, testName
        End If
    End Sub

    ''
    ' @brief Initialize mock registry matching kernel NodeRegistry.cls semantics.
    ''
    Private Unsafe Sub MockRegistryInit()
        g_nextNodeId = 1000
        Dim i As UInt32 = 0
        While i < TEST_MAX_NODES
            g_nodes(i).NodeId = 0
            g_nodes(i).Flags = 0
            g_nodes(i).Capabilities = 0
            g_nodes(i).OwnerPid = 0
            Dim j As UInt32 = 0
            While j < 32
                g_nodes(i).Name(j) = 0
                j = j + 1
            Wend
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Look up a node name matching kernel NodeRegistry.cls LookupNode exactly.
    ''
    Private Unsafe Function MockLookupNode(ByVal name As String) As UInt64
        If name = 0 Then
            MockLookupNode = 0
            Exit Function
        End If

        Dim pName As Pointer To Byte = CPtr(Pointer To Byte, name)
        Dim i As UInt32 = 0
        While i < TEST_MAX_NODES
            If (g_nodes(i).Flags And 1) <> 0 Then
                Dim isMatch As Boolean = True
                Dim j As UInt32 = 0
                While pName(j) <> 0 And g_nodes(i).Name(j) <> 0
                    If pName(j) <> g_nodes(i).Name(j) Then
                        isMatch = False
                        Exit While
                    End If
                    j = j + 1
                Wend

                If isMatch And pName(j) = 0 And g_nodes(i).Name(j) = 0 Then
                    MockLookupNode = g_nodes(i).NodeId
                    Exit Function
                End If
            End If
            i = i + 1
        Wend

        MockLookupNode = 0
    End Function

    ''
    ' @brief Register a node name matching kernel NodeRegistry.cls RegisterNode exactly.
    ''
    Private Unsafe Function MockRegisterNode(ByVal kind As UInt32, ByVal name As String, ByVal caps As UInt32) As UInt64
        If name = 0 Then
            MockRegisterNode = 0
            Exit Function
        End If

        If MockLookupNode(name) <> 0 Then
            MockRegisterNode = 0
            Exit Function
        End If

        Dim pName As Pointer To Byte = CPtr(Pointer To Byte, name)
        Dim slot As UInt32 = 0
        While slot < TEST_MAX_NODES
            If (g_nodes(slot).Flags And 1) = 0 Then
                Dim assignedId As UInt64 = g_nextNodeId
                g_nextNodeId = g_nextNodeId + 1

                g_nodes(slot).NodeId = assignedId
                g_nodes(slot).Kind = kind
                g_nodes(slot).OwnerPid = 1
                g_nodes(slot).Capabilities = caps
                g_nodes(slot).Flags = 1

                ' Copy name string up to 31 chars
                Dim j As UInt32 = 0
                While j < 31 And pName(j) <> 0
                    g_nodes(slot).Name(j) = pName(j)
                    j = j + 1
                Wend
                g_nodes(slot).Name(j) = 0

                MockRegisterNode = assignedId
                Exit Function
            End If
            slot = slot + 1
        Wend

        MockRegisterNode = 0
    End Function

    Private Unsafe Function ReturnNodeNameLiteral() As String
        ReturnNodeNameLiteral = "srv.returned_from_fn"
    End Function

    ' =========================================================================
    ' SUITE 1: Standard System & Service Node Registration / Lookup
    ' =========================================================================
    Private Unsafe Sub TestStandardServiceNodes()
        PrintMsg "[SUITE 1] Standard System & Userland Service Node Names..."
        MockRegistryInit

        ' 1.1 Register system core nodes
        Dim rootId As UInt64 = MockRegisterNode(NodeKind.Client, "sys.genesis", 7)
        AssertTrue rootId = 1000, "Register 'sys.genesis' returns ID 1000"

        Dim plexusId As UInt64 = MockRegisterNode(NodeKind.Device, "srv.plexus_mgr", 7)
        AssertTrue plexusId = 1001, "Register 'srv.plexus_mgr' returns ID 1001"

        Dim devMgrId As UInt64 = MockRegisterNode(NodeKind.Device, "srv.dev_mgr", 7)
        AssertTrue devMgrId = 1002, "Register 'srv.dev_mgr' returns ID 1002"

        Dim dispId As UInt64 = MockRegisterNode(NodeKind.Device, "srv.display", 7)
        AssertTrue dispId = 1003, "Register 'srv.display' returns ID 1003"

        Dim inputId As UInt64 = MockRegisterNode(NodeKind.Router, "srv.input", 7)
        AssertTrue inputId = 1004, "Register 'srv.input' returns ID 1004"

        Dim compId As UInt64 = MockRegisterNode(NodeKind.Device, "srv.compositor", 7)
        AssertTrue compId = 1005, "Register 'srv.compositor' returns ID 1005"

        Dim wmId As UInt64 = MockRegisterNode(NodeKind.Device, "srv.wm", 7)
        AssertTrue wmId = 1006, "Register 'srv.wm' returns ID 1006"

        Dim vfsId As UInt64 = MockRegisterNode(NodeKind.Storage, "srv.vfs", 7)
        AssertTrue vfsId = 1007, "Register 'srv.vfs' returns ID 1007"

        Dim hwInputId As UInt64 = MockRegisterNode(NodeKind.Device, "hw.input.raw", 3)
        AssertTrue hwInputId = 1008, "Register 'hw.input.raw' returns ID 1008"

        ' 1.2 Lookup all registered nodes
        AssertTrue MockLookupNode("sys.genesis") = 1000, "Lookup 'sys.genesis' matches ID 1000"
        AssertTrue MockLookupNode("srv.plexus_mgr") = 1001, "Lookup 'srv.plexus_mgr' matches ID 1001"
        AssertTrue MockLookupNode("srv.dev_mgr") = 1002, "Lookup 'srv.dev_mgr' matches ID 1002"
        AssertTrue MockLookupNode("srv.display") = 1003, "Lookup 'srv.display' matches ID 1003"
        AssertTrue MockLookupNode("srv.input") = 1004, "Lookup 'srv.input' matches ID 1004"
        AssertTrue MockLookupNode("srv.compositor") = 1005, "Lookup 'srv.compositor' matches ID 1005"
        AssertTrue MockLookupNode("srv.wm") = 1006, "Lookup 'srv.wm' matches ID 1006"
        AssertTrue MockLookupNode("srv.vfs") = 1007, "Lookup 'srv.vfs' matches ID 1007"
        AssertTrue MockLookupNode("hw.input.raw") = 1008, "Lookup 'hw.input.raw' matches ID 1008"

        ' 1.3 Non-existent node lookup returns 0
        AssertTrue MockLookupNode("srv.nonexistent") = 0, "Lookup non-existent node returns 0"
        AssertTrue MockLookupNode("srv.com") = 0, "Lookup prefix substring 'srv.com' returns 0"
        AssertTrue MockLookupNode("srv.compositor.extra") = 0, "Lookup superstring 'srv.compositor.extra' returns 0"
    End Sub

    ' =========================================================================
    ' SUITE 2: Dynamic Client Node Registration & Parameter Formatting
    ' =========================================================================
    Private Unsafe Sub TestDynamicClientNodes()
        PrintMsg "[SUITE 2] Dynamic Client Node Registration & Parameter Formatting..."

        ' 2.1 Format dynamic client name using AppendStr + AppendUInt (matching libpros client pattern)
        Dim cbuf1(32) As Byte
        Dim cidx1 As UInt32 = 0
        AppendStr "client.", @cbuf1(0), cidx1
        AppendUInt 42, @cbuf1(0), cidx1
        cbuf1(cidx1) = 0

        Dim client42Id As UInt64 = MockRegisterNode(NodeKind.Client, @cbuf1(0), 7)
        AssertTrue client42Id = 1009, "Register dynamic client '@cbuf1(0)' ('client.42') returns ID 1009"

        ' Lookup via string literal
        AssertTrue MockLookupNode("client.42") = 1009, "Lookup 'client.42' via string literal matches ID 1009"

        ' Lookup via another dynamically constructed buffer
        Dim cbuf2(32) As Byte
        Dim cidx2 As UInt32 = 0
        AppendStr "client.", @cbuf2(0), cidx2
        AppendUInt 42, @cbuf2(0), cidx2
        cbuf2(cidx2) = 0
        AssertTrue MockLookupNode(@cbuf2(0)) = 1009, "Lookup via dynamically formatted '@cbuf2(0)' matches ID 1009"

        ' 2.2 Dynamic client with large PID
        Dim cbuf3(32) As Byte
        Dim cidx3 As UInt32 = 0
        AppendStr "client.", @cbuf3(0), cidx3
        AppendUInt 999999, @cbuf3(0), cidx3
        cbuf3(cidx3) = 0

        Dim clientBigId As UInt64 = MockRegisterNode(NodeKind.Client, @cbuf3(0), 7)
        AssertTrue clientBigId = 1010, "Register dynamic client 'client.999999' returns ID 1010"
        AssertTrue MockLookupNode("client.999999") = 1010, "Lookup 'client.999999' matches ID 1010"
    End Sub

    ' =========================================================================
    ' SUITE 3: Boundary String Lengths & Truncation Invariants
    ' =========================================================================
    Private Unsafe Sub TestBoundaryLengths()
        PrintMsg "[SUITE 3] Boundary String Lengths & Truncation Invariants..."

        ' 3.1 Single character name
        Dim id1 As UInt64 = MockRegisterNode(NodeKind.Device, "x", 1)
        AssertTrue id1 > 0, "Register 1-character name 'x' succeeds"
        AssertTrue MockLookupNode("x") = id1, "Lookup 1-character name 'x' matches"

        ' 3.2 Exactly 30 characters
        Dim name30 As String = "123456789012345678901234567890"
        AssertTrue StrLen(name30) = 30, "StrLen(name30) == 30"
        Dim id30 As UInt64 = MockRegisterNode(NodeKind.Device, name30, 1)
        AssertTrue id30 > 0, "Register 30-character name succeeds"
        AssertTrue MockLookupNode(name30) = id30, "Lookup 30-character name matches"

        ' 3.3 Exactly 31 characters (maximum fit in 32-byte buffer with null terminator)
        Dim name31 As String = "1234567890123456789012345678901"
        AssertTrue StrLen(name31) = 31, "StrLen(name31) == 31"
        Dim id31 As UInt64 = MockRegisterNode(NodeKind.Device, name31, 1)
        AssertTrue id31 > 0, "Register 31-character name succeeds"
        AssertTrue MockLookupNode(name31) = id31, "Lookup 31-character name matches"

        ' 3.4 32 characters (demonstrates truncation and unreachability behavior)
        ' name32 shares the first 31 chars with name31, but has a 32nd char '2'
        Dim name32 As String = "12345678901234567890123456789012"
        AssertTrue StrLen(name32) = 32, "StrLen(name32) == 32"
        Dim id32 As UInt64 = MockRegisterNode(NodeKind.Device, name32, 1)
        AssertTrue id32 > 0, "Register 32-character name succeeds via truncation"
        ' Lookup by full 32-char name returns 0 because name(31) != 0, exposing the ghost node vulnerability
        AssertTrue MockLookupNode(name32) = 0, "Lookup by full 32-character name returns 0 (unreachable ghost node)"
        ' Lookup by the 31-character truncated prefix returns the first registered node
        AssertTrue MockLookupNode(name31) = id31, "Lookup by 31-char prefix returns original node (shadowing duplicate)"

        ' 3.5 Distinct 32+ character name
        Dim nameLongA As String = "abcdefghijabcdefghijabcdefghijA_extra_bytes"
        Dim nameLongTrunc As String = "abcdefghijabcdefghijabcdefghijA"
        AssertTrue StrLen(nameLongTrunc) = 31, "nameLongTrunc is exactly 31 chars"
        Dim idLongA As UInt64 = MockRegisterNode(NodeKind.Device, nameLongA, 1)
        AssertTrue idLongA > 0, "Register long name (>31 chars) succeeds by truncating to 31 chars"
        AssertTrue MockLookupNode(nameLongTrunc) = idLongA, "Lookup by truncated 31-char prefix matches stored node"
    End Sub

    ' =========================================================================
    ' SUITE 4: Adversarial String Parameters (Null, Empty, Case, Special Chars)
    ' =========================================================================
    Private Unsafe Sub TestAdversarialParameters()
        PrintMsg "[SUITE 4] Adversarial Parameters (Null, Empty, Case, Special Chars)..."

        ' 4.1 Null string parameters
        Dim sNull As String = 0
        AssertTrue MockRegisterNode(NodeKind.Device, sNull, 1) = 0, "Register(sNull) returns 0 safely without crash"
        AssertTrue MockLookupNode(sNull) = 0, "Lookup(sNull) returns 0 safely without crash"

        ' 4.2 Duplicate registration rejection
        Dim dupId1 As UInt64 = MockRegisterNode(NodeKind.Device, "srv.unique_test", 1)
        AssertTrue dupId1 > 0, "Initial registration of 'srv.unique_test' succeeds"
        Dim dupId2 As UInt64 = MockRegisterNode(NodeKind.Device, "srv.unique_test", 1)
        AssertTrue dupId2 = 0, "Duplicate registration of identical name is rejected (returns 0)"
        AssertTrue MockLookupNode("srv.unique_test") = dupId1, "Lookup still returns original node ID"

        ' 4.3 Case sensitivity
        AssertTrue MockLookupNode("SRV.UNIQUE_TEST") = 0, "Lookup with uppercase 'SRV.UNIQUE_TEST' returns 0 (case sensitive)"
        AssertTrue MockLookupNode("Srv.Unique_Test") = 0, "Lookup with mixed case returns 0"

        Dim upperId As UInt64 = MockRegisterNode(NodeKind.Device, "SRV.UNIQUE_TEST", 1)
        AssertTrue upperId > 0, "Registering uppercase 'SRV.UNIQUE_TEST' succeeds as distinct node"
        AssertTrue MockLookupNode("SRV.UNIQUE_TEST") = upperId, "Lookup uppercase matches uppercase ID"
        AssertTrue MockLookupNode("srv.unique_test") = dupId1, "Lookup lowercase matches lowercase ID"
        AssertTrue upperId <> dupId1, "Uppercase and lowercase nodes have distinct Node IDs"

        ' 4.4 Special characters in node name
        Dim specialName As String = "dev.pci_00:02.0/gpu#1"
        Dim specialId As UInt64 = MockRegisterNode(NodeKind.Device, specialName, 7)
        AssertTrue specialId > 0, "Register node with special characters (., :, _, /, #) succeeds"
        AssertTrue MockLookupNode(specialName) = specialId, "Lookup node with special characters matches"
    End Sub

    ' =========================================================================
    ' SUITE 5: Registry Capacity Limit (MAX_NODES = 64)
    ' =========================================================================
    Private Unsafe Sub TestCapacityLimit()
        PrintMsg "[SUITE 5] Registry Capacity Saturation (MAX_NODES = 64)..."
        MockRegistryInit

        ' Fill all 64 slots
        Dim fillIdx As UInt32 = 0
        Dim allSucceeded As Boolean = True
        While fillIdx < TEST_MAX_NODES
            Dim nameBuf(32) As Byte
            Dim nIdx As UInt32 = 0
            AppendStr "node.slot.", @nameBuf(0), nIdx
            AppendUInt CType(UInt64, fillIdx), @nameBuf(0), nIdx
            nameBuf(nIdx) = 0

            Dim assignedId As UInt64 = MockRegisterNode(NodeKind.Client, @nameBuf(0), 1)
            If assignedId = 0 Then
                allSucceeded = False
            End If
            fillIdx = fillIdx + 1
        Wend
        AssertTrue allSucceeded, "Successfully registered 64 distinct nodes filling all slots"

        ' Verify 65th registration is rejected because registry is full
        Dim overflowId As UInt64 = MockRegisterNode(NodeKind.Client, "node.overflow", 1)
        AssertTrue overflowId = 0, "65th node registration rejected with 0 (capacity limit enforced)"

        ' Verify all 64 registered nodes can be looked up
        Dim firstNodeId As UInt64 = MockLookupNode("node.slot.0")
        Dim lastNodeId As UInt64 = MockLookupNode("node.slot.63")
        AssertTrue firstNodeId = 1000, "First slot node 'node.slot.0' lookup matches ID 1000"
        AssertTrue lastNodeId = 1000 + 63, "Last slot node 'node.slot.63' lookup matches ID 1063"
    End Sub

    ' =========================================================================
    ' SUITE 6: String ABI & Variable Interop
    ' =========================================================================
    Private Unsafe Sub TestStringAbiInterop()
        PrintMsg "[SUITE 6] String ABI & Variable Interop..."
        MockRegistryInit

        ' 6.1 Passing string variable initialized with Dim s As String = "..."
        Dim myService As String = "srv.my_daemon"
        Dim myId As UInt64 = MockRegisterNode(NodeKind.Device, myService, 7)
        AssertTrue myId > 0, "Register via 'Dim s As String = ...' succeeds"
        AssertTrue MockLookupNode(myService) = myId, "Lookup via string variable matches"

        ' 6.2 Passing string returned from function
        Dim retName As String = ReturnNodeNameLiteral()
        Dim retId As UInt64 = MockRegisterNode(NodeKind.Device, retName, 7)
        AssertTrue retId > 0, "Register via function return string succeeds"
        AssertTrue MockLookupNode("srv.returned_from_fn") = retId, "Lookup matching function return name matches"

        ' 6.3 Registering using string literal, looking up using variable
        Dim litId As UInt64 = MockRegisterNode(NodeKind.Storage, "srv.storage_vault", 5)
        Dim lookupVar As String = "srv.storage_vault"
        AssertTrue MockLookupNode(lookupVar) = litId, "Register with literal, lookup with variable matches"

        ' 6.4 Registering using variable, looking up using literal
        AssertTrue MockLookupNode("srv.my_daemon") = myId, "Register with variable, lookup with literal matches"
    End Sub

    ' =========================================================================
    ' SUITE 7: Libpros Public ABI Syscall Wrapper Parity
    ' =========================================================================
    Private Unsafe Sub TestLibprosAbiParity()
        PrintMsg "[SUITE 7] Libpros Public ABI Syscall Wrapper Parity..."

        ' Verify that NodeRegister and NodeLookup function pointers can be referenced
        ' and that the signatures accept String parameters cleanly.
        Dim fnRegisterAddr As Pointer To Byte = CPtr(Pointer To Byte, AddressOf NodeRegister)
        Dim fnLookupAddr As Pointer To Byte = CPtr(Pointer To Byte, AddressOf NodeLookup)
        AssertTrue fnRegisterAddr <> 0, "NodeRegister function symbol resolved from libpros.a"
        AssertTrue fnLookupAddr <> 0, "NodeLookup function symbol resolved from libpros.a"

        ' Verify enums and caps
        AssertTrue NodeKind.Client = 1, "NodeKind.Client == 1"
        AssertTrue NodeKind.Device = 2, "NodeKind.Device == 2"
        AssertTrue NodeKind.Storage = 3, "NodeKind.Storage == 3"
        AssertTrue NodeKind.Router = 4, "NodeKind.Router == 4"
        AssertTrue SynapseCapability.Read = 1, "SynapseCapability.Read == 1"
        AssertTrue SynapseCapability.Write = 2, "SynapseCapability.Write == 2"
        AssertTrue SynapseCapability.Notify = 4, "SynapseCapability.Notify == 4"
        AssertTrue SynapseCapability.All = 7, "SynapseCapability.All == 7"
    End Sub

    Public Unsafe Function user_main(ByVal argc As UInt64, ByVal argv As Pointer To Pointer To Byte) As UInt64
        PrintMsg "========================================================"
        PrintMsg "[TEST-NODE-STRESS] Node Registration & Lookup Stress Test"
        PrintMsg "========================================================"

        TestStandardServiceNodes
        TestDynamicClientNodes
        TestBoundaryLengths
        TestAdversarialParameters
        TestCapacityLimit
        TestStringAbiInterop
        TestLibprosAbiParity

        ' Summary Output
        PrintMsg "--------------------------------------------------------"
        Dim rBuf(16) As Byte
        Dim pBuf(16) As Byte
        Dim fBuf(16) As Byte
        Dim idxR As UInt32 = 0
        Dim idxP As UInt32 = 0
        Dim idxF As UInt32 = 0
        AppendUInt CType(UInt64, testsRun), @rBuf(0), idxR
        rBuf(idxR) = 0
        AppendUInt CType(UInt64, testsPassed), @pBuf(0), idxP
        pBuf(idxP) = 0
        AppendUInt CType(UInt64, testsFailed), @fBuf(0), idxF
        fBuf(idxF) = 0

        DualPrint "[TEST-NODE-STRESS] Total Tests Run   : "
        PrintMsg @rBuf(0)
        DualPrint "[TEST-NODE-STRESS] Total Tests Passed: "
        PrintMsg @pBuf(0)
        DualPrint "[TEST-NODE-STRESS] Total Tests Failed: "
        PrintMsg @fBuf(0)
        PrintMsg "--------------------------------------------------------"

        If testsFailed = 0 Then
            PrintMsg "[TEST-NODE-STRESS] ALL NODE STRESS TESTS PASSED EMPIRICALLY!"
            PrintMsg "========================================================"
            user_main = 0
        Else
            PrintMsg "[TEST-NODE-STRESS] NODE STRESS TESTS DETECTED FAILURES!"
            PrintMsg "========================================================"
            user_main = 1
        End If
    End Function

End Module
