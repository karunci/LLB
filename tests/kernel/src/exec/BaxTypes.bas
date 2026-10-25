' Project Name: PRK-LLB (Personal Research Kernel) / Low-Level Basic
' Filename: tests/kernel/src/exec/BaxTypes.bas
' Summary: Native NEO/PE-BAX executable file structures and format constants.

Namespace Exec

    ' Format Constants
    Public Const BAX_MAGIC_VAL         As UInt64 = &H005841422F4F454E ' "NEO/BAX\0"
    Public Const BAX_VERSION_1         As UInt16 = 1
    Public Const BAX_ARCH_X86_64       As UInt16 = 1

    ' Subsystem Categories
    Public Const BAX_SUBSYS_CONSOLE    As UInt16 = 1
    Public Const BAX_SUBSYS_GUI        As UInt16 = 2
    Public Const BAX_SUBSYS_NODE       As UInt16 = 3

    ' Resource Categories
    Public Const BAX_ASSET_MANIFEST    As UInt32 = 1
    Public Const BAX_ASSET_ICON        As UInt32 = 2
    Public Const BAX_ASSET_IMAGE       As UInt32 = 3
    Public Const BAX_ASSET_FONT        As UInt32 = 4
    Public Const BAX_ASSET_CUSTOM      As UInt32 = 5

    ' Default Memory-Mapped Resource Table Virtual Address
    Public Const BAX_DEFAULT_RES_VADDR As UInt64 = &H50000000

    ''
    ' @brief Main 64-byte NEO/PE-BAX executable header.
    ''
    <Packed>
    Public Structure BaxHeader
        Public Magic            As UInt64    ' ASCII "NEO/BAX\0" (0x005841422F4F454E)
        Public FormatVersion    As UInt16    ' Format revision (1)
        Public TargetArch       As UInt16    ' 1 = x86_64, 2 = AArch64, 3 = RISC-V 64
        Public Subsystem        As UInt16    ' 1 = Console, 2 = GUI, 3 = Neural Node
        Public Flags            As UInt16    ' Bit 0: ASLR Compatible
        Public EntryPoint       As UInt64    ' Virtual address of application entry point
        Public ImageBase        As UInt64    ' Preferred base virtual address (e.g. 0x40000000)
        Public ImageSize        As UInt64    ' Total virtual address span in memory
        Public SegmentsOffset   As UInt32    ' File offset to Segment Table
        Public SegmentCount     As UInt16    ' Number of loadable segments
        Public ResourceCount    As UInt16    ' Number of embedded assets (0 for pure CLI)
        Public ResourceOffset   As UInt32    ' File offset to Resource Directory (0 if none)
        Public ResourceVirtAddr As UInt64    ' Virtual address where resource table is mapped (e.g. 0x50000000)
        Public Reserved         As UInt32    ' Reserved for alignment (must be 0)
    End Structure

    #Assert SizeOf(BaxHeader) = 64, "BaxHeader must be exactly 64 bytes"

    ''
    ' @brief Loadable segment descriptor (48 bytes).
    ''
    <Packed>
    Public Structure BaxSegment
        Public Name(8)      As Byte      ' Null-padded section name (8 bytes, e.g., ".text\0\0\0")
        Public FileOffset   As UInt64    ' File offset where initialized data begins
        Public FileSize     As UInt64    ' Initialized data size in file
        Public VirtAddr     As UInt64    ' Target virtual address in User PML4
        Public MemSize      As UInt64    ' Span in virtual memory (MemSize >= FileSize)
        Public Flags        As UInt32    ' Bit 0: Read (1), Bit 1: Write (2), Bit 2: Execute (4)
        Public Reserved     As UInt32    ' Must be 0
    End Structure

    #Assert SizeOf(BaxSegment) = 48, "BaxSegment must be exactly 48 bytes"

    ''
    ' @brief Embedded resource/asset directory entry (48 bytes).
    ''
    <Packed>
    Public Structure BaxResourceEntry
        Public AssetType    As UInt32    ' Asset category (1..5)
        Public AssetId      As UInt32    ' Numeric asset identifier (e.g., 100)
        Public Name(16)     As Byte      ' Null-terminated ASCII name (16 bytes, e.g., "manifest.json\0")
        Public FileOffset   As UInt64    ' Offset from start of .bax file to raw asset bytes
        Public ByteLength   As UInt64    ' Length of asset in bytes
        Public VirtAddr     As UInt64    ' Virtual address where asset is mapped in user space
    End Structure

    #Assert SizeOf(BaxResourceEntry) = 48, "BaxResourceEntry must be exactly 48 bytes"

End Namespace
