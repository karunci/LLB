' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/GdtTypes.bas
' Summary: 64-bit Global Descriptor Table (GDT) and Task State Segment (TSS) data structures.

Namespace Arch.X86_64

    ' Standard 8-byte x86_64 segment descriptor
    <Packed>
    Public Structure GdtEntry
        Public LimitLow As UInt16
        Public BaseLow As UInt16
        Public BaseMiddle As Byte
        Public Access As Byte
        Public Granularity As Byte
        Public BaseHigh As Byte
    End Structure
    #Assert SizeOf(GdtEntry) = 8, "GdtEntry must be exactly 8 bytes"

    ' 16-byte x86_64 System / TSS segment descriptor
    <Packed>
    Public Structure TssDescriptor
        Public LimitLow As UInt16
        Public BaseLow As UInt16
        Public BaseMidLow As Byte
        Public Access As Byte
        Public Granularity As Byte
        Public BaseMidHigh As Byte
        Public BaseHigh As UInt32
        Public Reserved As UInt32
    End Structure
    #Assert SizeOf(TssDescriptor) = 16, "TssDescriptor must be exactly 16 bytes"

    ' 10-byte pointer operand for the LGDT instruction
    <Packed>
    Public Structure GdtPtr
        Public Limit As UInt16
        Public Base As UInt64
    End Structure
    #Assert SizeOf(GdtPtr) = 10, "GdtPtr must be exactly 10 bytes"

    ' 104-byte 64-bit Task State Segment (TSS) hardware layout
    <Packed>
    Public Structure TssEntry
        Public Reserved0 As UInt32
        Public Rsp0 As UInt64
        Public Rsp1 As UInt64
        Public Rsp2 As UInt64
        Public Reserved1 As UInt64
        Public Ist1 As UInt64
        Public Ist2 As UInt64
        Public Ist3 As UInt64
        Public Ist4 As UInt64
        Public Ist5 As UInt64
        Public Ist6 As UInt64
        Public Ist7 As UInt64
        Public Reserved2 As UInt64
        Public Reserved3 As UInt16
        Public IoMapBase As UInt16
    End Structure
    #Assert SizeOf(TssEntry) = 104, "TssEntry must be exactly 104 bytes"

    ' Complete per-core GDT layout: Null, Kernel Code, Kernel Data, User Data, User Code, TSS
    <Packed>
    Public Structure GdtTable
        Public NullDesc As GdtEntry     ' Selector &H00
        Public KernelCode As GdtEntry   ' Selector &H08
        Public KernelData As GdtEntry   ' Selector &H10
        Public UserData As GdtEntry     ' Selector &H18
        Public UserCode As GdtEntry     ' Selector &H20
        Public TssDesc As TssDescriptor  ' Selector &H28 (16-byte descriptor)
    End Structure
    #Assert SizeOf(GdtTable) = 56, "GdtTable must be exactly 56 bytes (5*8 + 16)"

    ' Per-CPU GS scratchpad layout
    <Packed>
    Public Structure CpuScratch
        Public UserRsp As UInt64
        Public KernelStack As UInt64
        Public ScratchRax As UInt64
        Public CoreId As UInt32
        Public Reserved As UInt32
    End Structure
    #Assert SizeOf(CpuScratch) = 32, "CpuScratch must be 32 bytes"

End Namespace
