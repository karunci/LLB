' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/node/SynapseChannel.cls
' Summary: Data Plane Axonal Fast-Path Channel with lock-free circular ring buffers.

Import Sync
Use Sched.Scheduler As SchedEngine
Use Drivers.SerialUart As Serial

Namespace Core.Nodes

    <Instancing(MultiUse)>
    Public Class SynapseChannel

        Private channelId As UInt64
        Private sourceNodeId As UInt64
        Private targetNodeId As UInt64
        Private permissions As UInt32
        Private active As Boolean

        ' Synapse spinlock for thread safety
        Private channelLock As Sync.Spinlock

        ' Circular packet ring buffer (128 packets)
        Private ring(128) As AxonPacket
        Private head As UInt32
        Private tail As UInt32
        Private count As UInt32

        ' Task waiting for packets on this channel
        Private waitingPid As UInt64

        ' Packet sequence generator
        Private sequenceCounter As UInt64

        ''
        ' @brief Initialize a Synapse Channel connecting two nodes.
        ' @param id Channel identification number.
        ' @param src Source Node ID.
        ' @param tgt Destination Node ID.
        ' @param perms Capability permission bitmask (READ/WRITE/NOTIFY/DMA).
        ''
        Public Sub Initialize(ByVal id As UInt64, ByVal src As UInt64, ByVal tgt As UInt64, ByVal perms As UInt32)
            channelId = id
            sourceNodeId = src
            targetNodeId = tgt
            permissions = perms
            active = True
            head = 0
            tail = 0
            count = 0
            waitingPid = 0
            sequenceCounter = 1
        End Sub

        ''
        ' @brief Push a packet onto the Data Plane fast-path ring buffer.
        ' @param pkt Reference to packet structure to copy into the ring.
        ' @return True if enqueued successfully, False if buffer is full or write disallowed.
        ''
        Public Unsafe Function PushPacket(ByRef pkt As AxonPacket) As Boolean
            If Not active Then
                PushPacket = False
                Exit Function
            End If

            ' Enforce Write capability
            If (permissions And SynapseCaps.CAP_SYNAPSE_WRITE) = 0 Then
                PushPacket = False
                Exit Function
            End If

            Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(channelLock)

            If count >= SynapseCaps.RING_BUFFER_SIZE Then
                Sync.SpinlockOps.ReleaseIrqRestore channelLock, flags
                PushPacket = False
                Exit Function
            End If

            ' Copy packet to ring buffer slot
            Dim dest As Pointer To AxonPacket = AddressOf ring(tail)
            dest.Sequence = sequenceCounter
            sequenceCounter = sequenceCounter + 1
            dest.PacketType = pkt.PacketType
            dest.PayloadLength = pkt.PayloadLength
            dest.SourceNode = sourceNodeId
            dest.TargetNode = targetNodeId

            Dim i As UInt32 = 0
            Dim copyLen As UInt32 = pkt.PayloadLength
            If copyLen > SynapseCaps.MAX_PAYLOAD_SIZE Then copyLen = SynapseCaps.MAX_PAYLOAD_SIZE

            While i < copyLen
                dest.Payload(i) = pkt.Payload(i)
                i = i + 1
            Wend

            tail = (tail + 1) Mod SynapseCaps.RING_BUFFER_SIZE
            count = count + 1

            Dim targetWakePid As UInt64 = waitingPid
            waitingPid = 0

            Sync.SpinlockOps.ReleaseIrqRestore channelLock, flags

            ' Wake up waiting consumer thread if one was blocked
            If targetWakePid <> 0 Then
                SchedEngine.WakeTask targetWakePid
            End If

            PushPacket = True
        End Function

        ''
        ' @brief Pop a packet from the Data Plane fast-path ring buffer.
        ' @param outPkt Destination packet buffer to receive data.
        ' @param block  If True, blocks calling thread until data arrives.
        ' @return True if a packet was retrieved, False if empty/permission error.
        ''
        Public Unsafe Function PopPacket(ByRef outPkt As AxonPacket, ByVal block As Boolean) As Boolean
            If Not active Then
                PopPacket = False
                Exit Function
            End If

            ' Enforce Read capability
            If (permissions And SynapseCaps.CAP_SYNAPSE_READ) = 0 Then
                PopPacket = False
                Exit Function
            End If

            Do
                Dim flags As UInt64 = Sync.SpinlockOps.AcquireIrqSave(channelLock)

                If count > 0 Then
                    Dim src As Pointer To AxonPacket = AddressOf ring(head)
                    outPkt.Sequence = src.Sequence
                    outPkt.PacketType = src.PacketType
                    outPkt.PayloadLength = src.PayloadLength
                    outPkt.SourceNode = src.SourceNode
                    outPkt.TargetNode = src.TargetNode

                    Dim i As UInt32 = 0
                    Dim copyLen As UInt32 = src.PayloadLength
                    If copyLen > SynapseCaps.MAX_PAYLOAD_SIZE Then copyLen = SynapseCaps.MAX_PAYLOAD_SIZE

                    While i < copyLen
                        outPkt.Payload(i) = src.Payload(i)
                        i = i + 1
                    Wend

                    head = (head + 1) Mod SynapseCaps.RING_BUFFER_SIZE
                    count = count - 1

                    Sync.SpinlockOps.ReleaseIrqRestore channelLock, flags
                    PopPacket = True
                    Exit Function
                End If

                If Not block Then
                    Sync.SpinlockOps.ReleaseIrqRestore channelLock, flags
                    PopPacket = False
                    Exit Function
                End If

                ' Block calling thread on this synapse
                waitingPid = SchedEngine.GetCurrentPid()
                Sync.SpinlockOps.ReleaseIrqRestore channelLock, flags

                ' Yield CPU to scheduler until packet producer wakes us
                SchedEngine.BlockCurrentTask
            Loop
        End Function

        ' Channel Metric Queries
        Public Function GetCount() As UInt32
            GetCount = count
        End Function

        Public Function GetChannelId() As UInt64
            GetChannelId = channelId
        End Function

        Public Function GetSourceNode() As UInt64
            GetSourceNode = sourceNodeId
        End Function

        Public Function GetTargetNode() As UInt64
            GetTargetNode = targetNodeId
        End Function

    End Class

End Namespace
