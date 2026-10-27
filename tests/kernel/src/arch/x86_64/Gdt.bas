' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Gdt.bas
' Summary: 64-bit Global Descriptor Table (GDT) and TSS per-core installation and reload.
'          Ports PRK kernel/gdt.c and kernel/tss.c for SMP multi-core execution.

Import Arch.X86_64

Module Arch.X86_64.Gdt

    Public Const MAX_GDT_CPUS As UInt32 = 16

    Private gdtTables(16) As GdtTable
    Private gdtPointers(16) As GdtPtr
    Private tssTables(16) As TssEntry
    Private cpuScratchpads(16) As CpuScratch

    ''
    ' @brief Helper to construct standard 8-byte code/data descriptors.
    ' @param entry Reference to target GdtEntry structure.
    ' @param limit Segment limit (16-bit).
    ' @param access Access byte defining segment type and privilege level.
    ' @param gran Granularity and mode flags.
    ''
    Private Sub SetGdtEntry(ByRef entry As GdtEntry, ByVal limit As UInt16, ByVal access As Byte, ByVal gran As Byte)
        entry.LimitLow = limit
        entry.BaseLow = 0
        entry.BaseMiddle = 0
        entry.Access = access
        entry.Granularity = gran
        entry.BaseHigh = 0
    End Sub

    ''
    ' @brief Query the logical CPU ID of the calling processor from %gs:24.
    '        Mirrors PRK get_cpu_id().
    ' @return Logical CPU ID (0..MAX_CPUS-1).
    ''
    Public Unsafe Function GetCpuId() As UInt32
        Dim id As UInt32 = 0
        Asm "movl %%gs:24, %0" : "=r"(id) : : "memory"
        If id >= MAX_GDT_CPUS Then
            GetCpuId = 0
        Else
            GetCpuId = id
        End If
    End Function

    ''
    ' @brief Initialize and activate GDT, TSS, and GS scratchpad for a specific CPU core.
    '        Mirrors PRK gdt_init_core(logical_cpu_id).
    ' @param cpuId Logical ID of the target CPU core (0..MAX_GDT_CPUS-1).
    ''
    Public Unsafe Sub InitializeCore(ByVal cpuId As UInt32)
        If cpuId >= MAX_GDT_CPUS Then Exit Sub

        Dim gdtPtr As Pointer To GdtTable = AddressOf gdtTables(cpuId)
        Dim gdtP_ptr As Pointer To GdtPtr = AddressOf gdtPointers(cpuId)
        Dim tssPtr As Pointer To TssEntry = AddressOf tssTables(cpuId)
        Dim scratchPtr As Pointer To CpuScratch = AddressOf cpuScratchpads(cpuId)

        ' 1. Clear descriptors for this core
        Memory.ZeroMemory CPtr(Pointer To Byte, CType(UInt64, gdtPtr)), SizeOf(GdtTable)
        Memory.ZeroMemory CPtr(Pointer To Byte, CType(UInt64, tssPtr)), SizeOf(TssEntry)
        Memory.ZeroMemory CPtr(Pointer To Byte, CType(UInt64, scratchPtr)), SizeOf(CpuScratch)

        ' 2. Construct GDT segment descriptors
        ' Null Descriptor (&H00)
        SetGdtEntry gdtPtr.NullDesc, 0, 0, 0

        ' Kernel Code Segment (&H08): Present, Ring 0, Exec/Read, 64-bit Long Mode (L=1, D=0)
        SetGdtEntry gdtPtr.KernelCode, &HFFFF, &H9A, &HAF

        ' Kernel Data Segment (&H10): Present, Ring 0, Read/Write
        SetGdtEntry gdtPtr.KernelData, &HFFFF, &H92, &HCF

        ' User Data Segment (&H18): Present, Ring 3, Read/Write
        SetGdtEntry gdtPtr.UserData, &HFFFF, &HF2, &HCF

        ' User Code Segment (&H20): Present, Ring 3, Exec/Read, 64-bit Long Mode
        SetGdtEntry gdtPtr.UserCode, &HFFFF, &HFA, &HAF

        ' 3. Configure 64-bit Task State Segment (TSS)
        Dim tssAddress As UInt64 = CType(UInt64, tssPtr)
        Dim tssLimit As UInt32 = CType(UInt32, SizeOf(TssEntry) - 1)

        tssPtr.IoMapBase = CType(UInt16, SizeOf(TssEntry))

        gdtPtr.TssDesc.LimitLow = CType(UInt16, tssLimit And &HFFFF)
        gdtPtr.TssDesc.BaseLow = CType(UInt16, tssAddress And &HFFFF)
        gdtPtr.TssDesc.BaseMidLow = CType(Byte, (tssAddress RShift 16) And &HFF)
        gdtPtr.TssDesc.Access = &H89 ' Present, 64-bit TSS (Available)
        gdtPtr.TssDesc.Granularity = CType(Byte, (tssLimit RShift 16) And &H0F)
        gdtPtr.TssDesc.BaseMidHigh = CType(Byte, (tssAddress RShift 24) And &HFF)
        gdtPtr.TssDesc.BaseHigh = CType(UInt32, (tssAddress RShift 32) And &HFFFFFFFF)
        gdtPtr.TssDesc.Reserved = 0

        ' 4. Prepare GDTR pointer structure
        gdtP_ptr.Limit = CType(UInt16, SizeOf(GdtTable) - 1)
        gdtP_ptr.Base = CType(UInt64, gdtPtr)

        ' 5. Reload GDTR, reload segment registers with far return (lretq), and load TR (0x28)
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
            "xor %%ax, %%ax\n\t" _
            "mov %%ax, %%gs\n\t" _
            "mov $0x10, %%ax\n\t" _
            "mov %%ax, %%ss\n\t" _
            "mov $0x28, %%ax\n\t" _
            "ltr %%ax\n\t" : : "r"(gdtP_ptr) : "rax", "memory"

        ' 6. Configure Per-CPU GS Scratchpad
        scratchPtr.CoreId = cpuId
        scratchPtr.UserRsp = 0
        scratchPtr.KernelStack = 0

        Dim scratchAddr As UInt64 = CType(UInt64, scratchPtr)
        Dim lowDword As UInt32 = CType(UInt32, scratchAddr And &HFFFFFFFF)
        Dim highDword As UInt32 = CType(UInt32, (scratchAddr RShift 32) And &HFFFFFFFF)

        ' Write IA32_GS_BASE MSR (&HC0000101)
        Asm "wrmsr" : : "c"(&HC0000101), "a"(lowDword), "d"(highDword) : "memory"

        ' Write IA32_KERNEL_GS_BASE MSR (&HC0000102) = 0 for clean swapgs
        Asm "wrmsr" : : "c"(&HC0000102), "a"(0), "d"(0) : "memory"
    End Sub

    ''
    ' @brief Initialize and activate GDT and TSS for the primary BSP core (Core 0).
    ''
    Public Unsafe Sub Initialize()
        InitializeCore 0
    End Sub

    ''
    ' @brief Update TSS RSP0 privilege stack for the current calling core.
    ' @param kstackTop Top of kernel stack for the active task.
    ''
    Public Unsafe Sub SetKernelStack(ByVal kstackTop As UInt64)
        Dim cpuId As UInt32 = GetCpuId()
        SetKernelStackForCore cpuId, kstackTop
    End Sub

    ''
    ' @brief Update TSS RSP0 privilege stack for a specific CPU core.
    ' @param cpuId Target core logical ID.
    ' @param kstackTop Top of kernel stack for the active task.
    ''
    Public Sub SetKernelStackForCore(ByVal cpuId As UInt32, ByVal kstackTop As UInt64)
        If cpuId >= MAX_GDT_CPUS Then Exit Sub
        tssTables(cpuId).Rsp0 = kstackTop
        cpuScratchpads(cpuId).KernelStack = kstackTop
    End Sub

End Module
