' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Smp.bas
' Summary: SMP bring-up module. Copies AP trampoline to 0x8000, patches CR3 and stack slots,
'          sends INIT-SIPI-SIPI to AP cores, initializes per-core GDT/TSS, LAPIC, and enters scheduler.
'          Ports PRK kernel/smp.c (smp_init_cores & ap_main).

Import Arch.X86_64.PortIO
Import Arch.Acpi
Import Arch.X86_64.Apic
Import Arch.X86_64.Gdt
Import Arch.Idt
Import Sched
Use Drivers.SerialUart As Serial
Use Mem.KernelHeap As KHeap
Use Sched.Scheduler As SchedEngine

Module Arch.Smp

    ' Physical address where the AP 16-bit trampoline is placed at runtime.
    ' Must reside in the first 1MB (SIPI vector = physical address >> 12, must be < 0x100).
    Public Const TRAMPOLINE_PHYS As UInt64 = &H8000

    ' Maximum AP cores supported
    Public Const MAX_CPUS As UInt32 = 16

    ' Volatile atomic counters for BSP<->AP handshake (placed in BSS, zeroed at boot)
    Public apJoinCounter As UInt32 = 1   ' BSP starts at 1; each AP increments on join
    Public apHandshake   As UInt32 = 0   ' AP sets to 1 when it has captured its cpu_id
    Public apCurrentId   As UInt32 = 0   ' BSP writes logical id; AP reads before ack

    ''
    ' @brief Spin with a simple delay loop (approximate microsecond-scale wait).
    ' @param iterations Approximate busy-wait count.
    ''
    Private Unsafe Sub BusyWait(ByVal iterations As UInt32)
        Dim i As UInt32 = 0
        While i < iterations
            Asm "pause" : : : "memory"
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Send an IPI using LAPIC ICR registers (delegates to Apic.SendIpi).
    ' @param targetApicId Physical APIC ID of the destination core.
    ' @param vectorFlags  ICR command word (delivery mode | vector).
    ''
    Public Unsafe Sub SendIpi(ByVal targetApicId As UInt32, ByVal vectorFlags As UInt32)
        Arch.X86_64.Apic.SendIpi targetApicId, vectorFlags
    End Sub

    ''
    ' @brief Initialize all Application Processor cores found in ACPI MADT.
    '        Copies trampoline from its link-time address to physical 0x8000,
    '        patches the CR3 and stack slots, then sends INIT + 2x SIPI to each AP.
    '        Mirrors PRK smp_init_cores().
    ''
    Public Unsafe Sub InitCores()
        Dim totalCores As UInt32 = Arch.Acpi.GetCpuCount()
        If totalCores <= 1 Then
            Serial.PrintF "[SMP] Single-core system detected. Skipping AP bring-up.\r\n"
            Exit Sub
        End If
        If totalCores > MAX_CPUS Then totalCores = MAX_CPUS

        Serial.PrintF "[SMP] Preparing AP trampoline at 0x8000 (%d cores total)...\r\n", totalCores

        ' Copy trampoline blob (symbols exported from boot.S) to physical 0x8000
        Dim trampolineStart As UInt64 = 0
        Dim trampolineEnd   As UInt64 = 0
        Asm "movabs $smp_trampoline_start, %0" : "=r"(trampolineStart) : : "memory"
        Asm "movabs $smp_trampoline_end,   %0" : "=r"(trampolineEnd)   : : "memory"

        Dim trampolineSize As UInt32 = CType(UInt32, trampolineEnd - trampolineStart)
        Dim src As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, trampolineStart)
        Dim dst As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, TRAMPOLINE_PHYS)
        Dim bi As UInt32 = 0
        While bi < trampolineSize
            dst(bi) = src(bi)
            bi = bi + 1
        Wend

        ' Patch the CR3 slot inside the trampoline with the current kernel page table root
        Dim cr3Val As UInt64 = 0
        Asm "mov %%cr3, %0" : "=r"(cr3Val) : : "memory"

        Dim cr3SlotLinkAddr As UInt64 = 0
        Asm "movabs $smp_cr3_slot, %0" : "=r"(cr3SlotLinkAddr) : : "memory"
        Dim cr3SlotOffset As UInt64 = cr3SlotLinkAddr - trampolineStart
        Dim cr3SlotPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, TRAMPOLINE_PHYS + cr3SlotOffset)
        cr3SlotPtr(0) = CType(UInt32, cr3Val And &HFFFFFFFF)

        ' Find stack slot offset inside the trampoline
        Dim stackSlotLinkAddr As UInt64 = 0
        Asm "movabs $smp_stack_slot, %0" : "=r"(stackSlotLinkAddr) : : "memory"
        Dim stackSlotOffset As UInt64 = stackSlotLinkAddr - trampolineStart
        Dim stackSlotPtr As Volatile Pointer To UInt64 = CPtr(Volatile Pointer To UInt64, TRAMPOLINE_PHYS + stackSlotOffset)

        ' Memory fence before sending IPIs
        Asm "mfence" : : : "memory"

        ' Bring up each AP (logical IDs 1..totalCores-1)
        Dim logicalId As UInt32 = 1
        While logicalId < totalCores
            Dim apicId As UInt32 = CType(UInt32, Arch.Acpi.GetApicId(logicalId))

            Serial.PrintF "[SMP] Booting AP Core #%d (APIC ID: %d)...\r\n", logicalId, apicId

            ' Allocate bootstrap stack for this AP (16KB)
            Dim apBootStack As UInt64 = KHeap.KMalloc(16384)
            If apBootStack = 0 Then
                Serial.PrintF "[SMP] Error: Failed to allocate bootstrap stack for AP core #%d\r\n", logicalId
            Else
                ' 16-byte aligned top of stack
                Dim stackTop As UInt64 = (apBootStack + 16384 - 16) And (Not CType(UInt64, 15))
                stackSlotPtr(0) = stackTop

                ' Reset handshake flag and publish target logical CPU ID
                apHandshake = 0
                apCurrentId = logicalId
                Asm "mfence" : : : "memory"

                Dim initialCounter As UInt32 = apJoinCounter

                ' INIT IPI: Delivery mode 5 (INIT), level assert (bit 14)
                SendIpi apicId, &H00004500
                BusyWait 1000000  ' ~10ms delay

                ' SIPI x2: Vector = 0x08 (trampoline at 0x8000 = 0x08 << 12)
                SendIpi apicId, &H00004608
                BusyWait 100000
                SendIpi apicId, &H00004608

                ' Wait for AP to acknowledge capture of cpu_id (apHandshake = 1)
                Dim waitCount As UInt64 = 50000000
                While apHandshake = 0 And waitCount > 0
                    Asm "pause" : : : "memory"
                    waitCount = waitCount - 1
                Wend

                ' Wait for AP to complete initialization (apJoinCounter incremented)
                waitCount = 50000000
                While apJoinCounter = initialCounter And waitCount > 0
                    Asm "pause" : : : "memory"
                    waitCount = waitCount - 1
                Wend

                If apJoinCounter = initialCounter Then
                    Serial.PrintF "[SMP] WARNING: AP Core #%d (APIC ID: %d) did not respond.\r\n", logicalId, apicId
                End If
            End If

            logicalId = logicalId + 1
        Wend

        Serial.PrintF "[SMP] All AP cores initialized. Online: %d/%d\r\n", apJoinCounter, totalCores
    End Sub

    ''
    ' @brief Entry point called by each AP core after long mode entry in the trampoline.
    '        Mirrors PRK kernel/smp.c ap_main().
    ''
    Public Unsafe Sub ApMain()
        ' 1. Capture assigned CPU ID and signal BSP
        Dim cpuId As UInt32 = apCurrentId
        Asm "mfence" : : : "memory"
        apHandshake = 1
        Asm "mfence" : : : "memory"

        ' 2. Enable LAPIC on this AP
        Arch.X86_64.Apic.Initialize

        ' 3. Reload IDT on this AP
        Arch.Idt.ReloadIdt

        ' 4. Initialize per-core GDT, TSS, and GS scratchpad
        Arch.X86_64.Gdt.InitializeCore cpuId

        ' 5. Initialize Local APIC periodic preemption timer on this AP
        Arch.X86_64.Apic.InitializeTimer 3, &H200000

        ' 6. Signal BSP that this AP is fully online and initialized
        Dim joinCounterPtr As Pointer To UInt32 = AddressOf apJoinCounter
        Asm "lock; addl $1, (%0)" : : "r"(joinCounterPtr) : "memory"

        Serial.PrintF "[SMP] AP Core #%d online: GDT/TSS/LAPIC/Timer ready. Entering scheduler...\r\n", cpuId

        ' 7. Enter AP scheduler loop (never returns)
        SchedEngine.ApEnter cpuId
    End Sub

End Module
