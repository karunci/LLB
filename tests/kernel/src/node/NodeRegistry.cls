' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/node/NodeRegistry.cls
' Summary: Control Plane Node Registry managing neural topology, capabilities, and synapses.

Import Sync
Import Core.Nodes.SynapseCaps
Use Drivers.SerialUart As Serial
Use Core.Nodes.SynapseChannel
Use Sched.Scheduler As SchedEngine

Namespace Core.Nodes

    <Instancing(SingleUse)>
    Public Class NodeRegistry

        Private nodes(64) As NodeDescriptor
        Private channels(64) As SynapseChannel
        Private channelAllocated(64) As Boolean

        Private nextNodeId As UInt64
        Private nextChannelId As UInt64
        Private registryLock As Sync.Spinlock

        ''
        ' @brief Initialize the Control Plane Node Registry.
        ''
        Public Sub Initialize()
            nextNodeId = 1000
            nextChannelId = 5000

            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                nodes(i).NodeId = 0
                nodes(i).Flags = 0
                nodes(i).Capabilities = 0
                nodes(i).OwnerPid = 0
                channelAllocated(i) = False
                i = i + 1
            Wend

            Serial.PrintF "[NODE] Dual-Plane Neural Node Registry Online (Max: %u Nodes)\r\n", SynapseCaps.MAX_NODES
        End Sub

        ''
        ' @brief Register a new Kernel Node in the Control Plane topology.
        ' @param name Pointer to null-terminated node name string (e.g. "drivers.display.lfb").
        ' @param kind Node category (COMPUTE, DEVICE, MEMORY, ROUTER).
        ' @param ownerPid Owning Process/Task ID.
        ' @param caps Initial capability permission mask.
        ' @return Unique Node ID (>0) or 0 on failure.
        ''
        Public Unsafe Function RegisterNode(ByVal name As Pointer To Byte, ByVal kind As UInt32, ByVal ownerPid As UInt64, ByVal caps As UInt32) As UInt64
            If name = 0 Then
                RegisterNode = 0
                Exit Function
            End If

            ' Verify name uniqueness
            If LookupNode(name) <> 0 Then
                Serial.PrintF "[NODE] Error: Node with this name already registered.\r\n"
                RegisterNode = 0
                Exit Function
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)

            Dim slot As UInt32 = 0
            While slot < SynapseCaps.MAX_NODES
                If (nodes(slot).Flags And SynapseCaps.NODE_FLAG_ACTIVE) = 0 Then
                    Dim assignedId As UInt64 = nextNodeId
                    nextNodeId = nextNodeId + 1

                    nodes(slot).NodeId = assignedId
                    nodes(slot).Kind = kind
                    nodes(slot).OwnerPid = ownerPid
                    nodes(slot).Capabilities = caps
                    nodes(slot).Flags = SynapseCaps.NODE_FLAG_ACTIVE
                    nodes(slot).WaitingPid = 0

                    ' Copy name string up to 31 chars
                    Dim j As UInt32 = 0
                    While j < 31 And name(j) <> 0
                        nodes(slot).Name(j) = name(j)
                        j = j + 1
                    Wend
                    nodes(slot).Name(j) = 0

                    Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
                    Serial.PrintF "[NODE] Registered Node #%u (Kind: %u, Owner PID: %u)\r\n", _
                                  CType(UInt32, assignedId), kind, CType(UInt32, ownerPid)
                    RegisterNode = assignedId
                    Exit Function
                End If
                slot = slot + 1
            Wend

            Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
            RegisterNode = 0
        End Function

        ''
        ' @brief Look up an existing Kernel Node by name.
        ' @param name Pointer to string to search for.
        ' @return Node ID if found, 0 otherwise.
        ''
        Public Unsafe Function LookupNode(ByVal name As Pointer To Byte) As UInt64
            If name = 0 Then
                LookupNode = 0
                Exit Function
            End If

            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                If (nodes(i).Flags And SynapseCaps.NODE_FLAG_ACTIVE) <> 0 Then
                    Dim isMatch As Boolean = True
                    Dim j As UInt32 = 0
                    While name(j) <> 0 And nodes(i).Name(j) <> 0
                        If name(j) <> nodes(i).Name(j) Then
                            isMatch = False
                            Exit While
                        End If
                        j = j + 1
                    Wend

                    If isMatch And name(j) = 0 And nodes(i).Name(j) = 0 Then
                        LookupNode = nodes(i).NodeId
                        Exit Function
                    End If
                End If
                i = i + 1
            Wend

            LookupNode = 0
        End Function

        ''
        ' @brief Establish a directed Synapse fast-path channel between two nodes.
        ' @param srcNodeId Source node ID.
        ' @param tgtNodeId Target node ID.
        ' @param requestedCaps Requested capability flags (READ/WRITE/NOTIFY/DMA).
        ' @return Synapse Channel ID (>0) or 0 if rejected.
        ''
        Public Unsafe Function ConnectSynapse(ByVal srcNodeId As UInt64, ByVal tgtNodeId As UInt64, ByVal requestedCaps As UInt32) As UInt64
            If srcNodeId = 0 Or tgtNodeId = 0 Then
                ConnectSynapse = 0
                Exit Function
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)

            ' Check if an existing channel connects srcNodeId -> tgtNodeId
            Dim existIdx As UInt32 = 0
            While existIdx < SynapseCaps.MAX_NODES
                If channelAllocated(existIdx) Then
                    If channels(existIdx).GetSourceNode() = srcNodeId And channels(existIdx).GetTargetNode() = tgtNodeId Then
                        Dim existCid As UInt64 = channels(existIdx).GetChannelId()
                        Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
                        ConnectSynapse = existCid
                        Exit Function
                    End If
                End If
                existIdx = existIdx + 1
            Wend

            ' Find an available synapse channel slot
            Dim slot As UInt32 = 0
            While slot < SynapseCaps.MAX_NODES
                If Not channelAllocated(slot) Then
                    Dim cid As UInt64 = nextChannelId
                    nextChannelId = nextChannelId + 1

                    channels(slot).Initialize cid, srcNodeId, tgtNodeId, requestedCaps
                    channelAllocated(slot) = True

                    Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
                    Serial.PrintF "[NODE] Established Synapse Channel #%u: Node #%u -> Node #%u (Caps: 0x%x)\r\n", _
                                  CType(UInt32, cid), CType(UInt32, srcNodeId), CType(UInt32, tgtNodeId), requestedCaps
                    ConnectSynapse = cid
                    Exit Function
                End If
                slot = slot + 1
            Wend

            Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
            ConnectSynapse = 0
        End Function

        ''
        ' @brief Retrieve the channel instance by channel ID.
        ' @param cid Channel ID.
        ' @return SynapseChannel pointer or 0 if invalid.
        ''
        Public Unsafe Function GetChannel(ByVal cid As UInt64) As Pointer To SynapseChannel
            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                If channelAllocated(i) Then
                    If channels(i).GetChannelId() = cid Then
                        GetChannel = AddressOf channels(i)
                        Exit Function
                    End If
                End If
                i = i + 1
            Wend
            GetChannel = 0
        End Function

        ''
        ' @brief Find an active channel targeting the given node that has pending packets.
        ' @param targetNodeId Destination node ID.
        ' @return Pointer to channel or 0 if none have pending packets.
        ''
        Public Unsafe Function GetInboundChannel(ByVal targetNodeId As UInt64) As Pointer To SynapseChannel
            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                If channelAllocated(i) Then
                    If channels(i).GetTargetNode() = targetNodeId And channels(i).GetCount() > 0 Then
                        GetInboundChannel = AddressOf channels(i)
                        Exit Function
                    End If
                End If
                i = i + 1
            Wend
            GetInboundChannel = 0
        End Function

        ''
        ' @brief Wake any task waiting on a specific node.
        ' @param targetNodeId Destination node ID.
        ''
        Public Unsafe Sub WakeNodeWaiter(ByVal targetNodeId As UInt64)
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                If (nodes(i).Flags And SynapseCaps.NODE_FLAG_ACTIVE) <> 0 And nodes(i).NodeId = targetNodeId Then
                    Dim wPid As UInt64 = nodes(i).WaitingPid
                    nodes(i).WaitingPid = 0
                    Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
                    If wPid <> 0 Then
                        SchedEngine.WakeTask wPid
                    End If
                    Exit Sub
                End If
                i = i + 1
            Wend
            Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
        End Sub

        ''
        ' @brief Set waiting PID for a specific node.
        ' @param targetNodeId Destination node ID.
        ' @param pid Task ID waiting for incoming messages.
        ''
        Public Unsafe Sub SetNodeWaitingPid(ByVal targetNodeId As UInt64, ByVal pid As UInt64)
            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(registryLock)
            Dim i As UInt32 = 0
            While i < SynapseCaps.MAX_NODES
                If (nodes(i).Flags And SynapseCaps.NODE_FLAG_ACTIVE) <> 0 And nodes(i).NodeId = targetNodeId Then
                    nodes(i).WaitingPid = pid
                    Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
                    Exit Sub
                End If
                i = i + 1
            Wend
            Sync.SpinlockOps.ReleaseIrqRestore registryLock, flags
        End Sub

    End Class

End Namespace
