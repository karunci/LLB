' Project Name: PROS (Personal Research Operating System)
' Filename: lib/pros/src/Node.bas
' Summary: Dual-Plane Neural Node and Synapse IPC library.

Import Pros.Sys.RawSyscall

Namespace Pros.Nodes

    Public Const NODE_KIND_CLIENT   As UInt32 = 1
    Public Const NODE_KIND_DEVICE   As UInt32 = 2
    Public Const NODE_KIND_STORAGE  As UInt32 = 3
    Public Const NODE_KIND_ROUTER   As UInt32 = 4

    Public Const CAP_SYNAPSE_READ   As UInt32 = 1
    Public Const CAP_SYNAPSE_WRITE  As UInt32 = 2
    Public Const CAP_SYNAPSE_NOTIFY As UInt32 = 4

    <Packed>
    Public Structure AxonPacket
        Public Sequence      As UInt64
        Public PacketType    As UInt32
        Public PayloadLength As UInt32
        Public SourceNode    As UInt64
        Public TargetNode    As UInt64
        Public Payload(255)  As Byte
    End Structure

    Public Module NodeRegistry

        ''
        ' @brief Register a new Neural Node in the system registry.
        ' @param kind Node functional kind (Client, Device, Storage, Router).
        ' @param namePtr Null-terminated node name string.
        ' @param caps Initial capability bitmask.
        ' @return Assigned Node ID, or 0 on failure.
        ''
        Public Unsafe Function Register(ByVal kind As UInt32, ByVal name As String, ByVal caps As UInt32) As UInt64
            Register = Pros.Sys.RawSyscall.Call3(Pros.Sys.SYS_NODE_REGISTER, CType(UInt64, kind), CType(UInt64, name), CType(UInt64, caps))
        End Function

        ''
        ' @brief Look up an existing Neural Node by name.
        ' @param name Null-terminated node name string.
        ' @return Node ID if found, or 0.
        ''
        Public Unsafe Function Lookup(ByVal name As String) As UInt64
            Lookup = Pros.Sys.RawSyscall.Call1(Pros.Sys.SYS_NODE_LOOKUP, CType(UInt64, name))
        End Function

        ''
        ' @brief Establish a Synapse channel between two Nodes.
        ' @param srcNodeId Source node identifier.
        ' @param targetNodeId Target node identifier.
        ' @param caps Requested channel capability bitmask.
        ' @return Assigned Synapse Channel ID, or 0 on failure.
        ''
        Public Unsafe Function Connect(ByVal srcNodeId As UInt64, ByVal targetNodeId As UInt64, ByVal caps As UInt32) As UInt64
            Connect = Pros.Sys.RawSyscall.Call3(Pros.Sys.SYS_SYNAPSE_CONNECT, srcNodeId, targetNodeId, CType(UInt64, caps))
        End Function

        ''
        ' @brief Transmit an Axonal Data Plane packet through a Synapse channel.
        ' @param synId Active synapse channel handle.
        ' @param pkt Reference to packet structure to send.
        ' @return True if transmitted successfully, False if full.
        ''
        Public Unsafe Function Push(ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean
            Dim ret As UInt64 = Pros.Sys.RawSyscall.Call2(Pros.Sys.SYS_SYNAPSE_PUSH, synId, CType(UInt64, AddressOf pkt))
            Push = (ret = 1)
        End Function

        ''
        ' @brief Receive an Axonal Data Plane packet from a Synapse channel.
        ' @param synId Active synapse channel handle.
        ' @param pkt Reference to packet structure to populate.
        ' @return True if packet received, False if empty.
        ''
        Public Unsafe Function Pop(ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean
            Dim ret As UInt64 = Pros.Sys.RawSyscall.Call3(Pros.Sys.SYS_SYNAPSE_POP, synId, CType(UInt64, AddressOf pkt), 0)
            Pop = (ret = 1)
        End Function

        ''
        ' @brief Block and receive an Axonal Data Plane packet from a Synapse channel or Node.
        ' @param synId Active synapse channel handle or node ID.
        ' @param pkt Reference to packet structure to populate.
        ' @return True if packet received.
        ''
        Public Unsafe Function PopWait(ByVal synId As UInt64, ByRef pkt As AxonPacket) As Boolean
            Dim ret As UInt64 = Pros.Sys.RawSyscall.Call3(Pros.Sys.SYS_SYNAPSE_POP, synId, CType(UInt64, AddressOf pkt), 1)
            PopWait = (ret = 1)
        End Function

    End Module

End Namespace
