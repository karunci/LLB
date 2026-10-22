' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Gdt.bas
' Summary: 64-bit Global Descriptor Table (GDT) and TSS installation and reload.

Import Arch.X86_64

Module Arch.X86_64.Gdt

    Private gdtTable As GdtTable
    Private gdtPointer As GdtPtr
    Private tssTable As TssEntry
    Private cpuScratchpad As CpuScratch

    ' Helper to construct standard 8-byte code/data descriptors
    Private Sub SetGdtEntry(ByRef entry As GdtEntry, ByVal limit As UInt16, ByVal access As Byte, ByVal gran As Byte)
        entry.LimitLow = limit
        entry.BaseLow = 0
        entry.BaseMiddle = 0
        entry.Access = access
        entry.Granularity = gran
        entry.BaseHigh = 0
    End Sub

    ' Initialize and activate GDT and TSS for the primary BSP CPU core
    Public Unsafe Sub Initialize()
        ' 1. Clear descriptors
        Memory.ZeroMemory AddressOf gdtTable, SizeOf(GdtTable)
        Memory.ZeroMemory AddressOf tssTable, SizeOf(TssEntry)
        Memory.ZeroMemory AddressOf cpuScratchpad, SizeOf(CpuScratch)

        ' 2. Construct GDT segment descriptors
        ' Null Descriptor (&H00)
        SetGdtEntry gdtTable.NullDesc, 0, 0, 0

        ' Kernel Code Segment (&H08): Present, Ring 0, Exec/Read, 64-bit Long Mode (L=1, D=0)
        SetGdtEntry gdtTable.KernelCode, &HFFFF, &H9A, &HAF

        ' Kernel Data Segment (&H10): Present, Ring 0, Read/Write
        SetGdtEntry gdtTable.KernelData, &HFFFF, &H92, &HCF

        ' User Data Segment (&H18): Present, Ring 3, Read/Write
        SetGdtEntry gdtTable.UserData, &HFFFF, &HF2, &HCF

        ' User Code Segment (&H20): Present, Ring 3, Exec/Read, 64-bit Long Mode
        SetGdtEntry gdtTable.UserCode, &HFFFF, &HFA, &HAF

        ' 3. Configure 64-bit Task State Segment (TSS)
        Dim tssAddress As UInt64 = CType(UInt64, AddressOf tssTable)
        Dim tssLimit As UInt32 = CType(UInt32, SizeOf(TssEntry) - 1)

        tssTable.IoMapBase = CType(UInt16, SizeOf(TssEntry))

        gdtTable.TssDesc.LimitLow = CType(UInt16, tssLimit And &HFFFF)
        gdtTable.TssDesc.BaseLow = CType(UInt16, tssAddress And &HFFFF)
        gdtTable.TssDesc.BaseMidLow = CType(Byte, (tssAddress RShift 16) And &HFF)
        gdtTable.TssDesc.Access = &H89 ' Present, 64-bit TSS (Available)
        gdtTable.TssDesc.Granularity = CType(Byte, (tssLimit RShift 16) And &H0F)
        gdtTable.TssDesc.BaseMidHigh = CType(Byte, (tssAddress RShift 24) And &HFF)
        gdtTable.TssDesc.BaseHigh = CType(UInt32, (tssAddress RShift 32) And &HFFFFFFFF)
        gdtTable.TssDesc.Reserved = 0

        ' 4. Prepare GDTR pointer structure
        gdtPointer.Limit = CType(UInt16, SizeOf(GdtTable) - 1)
        gdtPointer.Base = CType(UInt64, AddressOf gdtTable)

        ' 5. Reload GDTR, reload segment registers with far return (lretq), and load TR
        Dim gdtPtrAddress As Pointer To GdtPtr = AddressOf gdtPointer
        Asm "lgdt (%0)\n\t" _
            "pushq $0x08\n\t" _
            "lea 1f(%%rip), %%rax\n\t" _
            "pushq %%rax\n\t" _
            "lretq\n\t" _
            "1:\n\t" _
            "mov $0x10, %%ax\n\t" _
            "mov %%ax, %%ds\n\t" _
            "mov %%ax, %%es\n\t" _
            "mov %%ax, %%fs\n\t" _
            "mov %%ax, %%gs\n\t" _
            "mov %%ax, %%ss\n\t" _
            "mov $0x28, %%ax\n\t" _
            "ltr %%ax\n\t" : : "r"(gdtPtrAddress) : "rax", "memory"

        ' 6. Configure Per-CPU GS Scratchpad
        cpuScratchpad.CoreId = 0
        cpuScratchpad.UserRsp = 0
        cpuScratchpad.KernelStack = 0

        Dim scratchAddr As UInt64 = CType(UInt64, AddressOf cpuScratchpad)
        Dim lowDword As UInt32 = CType(UInt32, scratchAddr And &HFFFFFFFF)
        Dim highDword As UInt32 = CType(UInt32, (scratchAddr RShift 32) And &HFFFFFFFF)
        Dim msrGsBase As UInt32 = &HC0000101

        ' Write IA32_GS_BASE MSR (&HC0000101)
        Asm "wrmsr" : : "c"(msrGsBase), "a"(lowDword), "d"(highDword) : "memory"
    End Sub

    ' Update TSS RSP0 privilege stack for task switching
    Public Sub SetKernelStack(ByVal kstackTop As UInt64)
        tssTable.Rsp0 = kstackTop
        cpuScratchpad.KernelStack = kstackTop
    End Sub

End Module
