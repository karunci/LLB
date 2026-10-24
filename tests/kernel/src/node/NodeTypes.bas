' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/node/NodeTypes.bas
' Summary: Dual-Plane Neural Node data structures, capability masks, and fast packets.

Namespace Core.Nodes

    ' Node Classification Categories
    Public Enum NodeKind
        NODE_COMPUTE = 1  ' Execution threads, workers, userspace tasks
        NODE_DEVICE  = 2  ' Hardware devices (UART, Framebuffer, Keyboard, Storage)
        NODE_MEMORY  = 3  ' Shared memory regions, VRAM windows, DMA buffers
        NODE_ROUTER  = 4  ' Multiplexing event brokers, compositors, routers
    End Enum

    ' Synaptic Capability Permissions
    Public Module SynapseCaps
        Public Const CAP_SYNAPSE_READ   As UInt32 = &H01  ' Permission to pull packets
        Public Const CAP_SYNAPSE_WRITE  As UInt32 = &H02  ' Permission to push packets
        Public Const CAP_SYNAPSE_NOTIFY As UInt32 = &H04  ' Permission to receive state signals
        Public Const CAP_SYNAPSE_DMA    As UInt32 = &H08  ' Direct physical memory access
        Public Const CAP_SYNAPSE_ADMIN  As UInt32 = &H80  ' Topology modification authority

        Public Const NODE_FLAG_ACTIVE   As UInt32 = &H01
        Public Const MAX_NODES          As UInt32 = 64
        Public Const RING_BUFFER_SIZE   As UInt32 = 128
        Public Const MAX_PAYLOAD_SIZE   As UInt32 = 256
    End Module

    ' Axonal Fast-Path Data Plane Packet (32-byte header + 256 bytes payload)
    <Packed>
    Public Structure AxonPacket
        Public Sequence As UInt64
        Public PacketType As UInt32
        Public PayloadLength As UInt32
        Public SourceNode As UInt64
        Public TargetNode As UInt64
        Public Payload(255) As Byte
    End Structure

    ' Control Plane Node Entity Descriptor
    <Packed>
    Public Structure NodeDescriptor
        Public NodeId As UInt64
        Public Kind As UInt32
        Public OwnerPid As UInt64
        Public Capabilities As UInt32
        Public Flags As UInt32
        Public WaitingPid As UInt64
        Public Name(31) As Byte
    End Structure

End Namespace
