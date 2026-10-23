' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Smp.bas
' Summary: SMP bring-up module. Copies AP trampoline to 0x8000, sends INIT-SIPI-SIPI
'          to each enabled AP core discovered by ACPI MADT.
'          Ports PRK kernel/smp.c (smp_init_cores) - AP idle loop without full scheduler.

Module Arch.Smp

    Import Arch.X86_64.PortIO
    Import Arch.Acpi
    Import Arch.X86_64.Apic
    Use Drivers.SerialUart As Serial

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
    ' @brief Send an IPI using LAPIC ICR registers.
    '        Matches PRK lapic_send_ipi() MMIO path (x2APIC handled in Apic.bas).
    ' @param targetApicId Physical APIC ID of the destination core.
    ' @param vectorFlags  ICR command word (delivery mode | vector).
    ''
    Public Unsafe Sub SendIpi(ByVal targetApicId As UInt32, ByVal vectorFlags As UInt32)
        ' Wait for ICR send-pending (bit 12) to clear before writing
        Dim timeout As UInt32 = 100000
        While ((Arch.X86_64.Apic.LapicRead(&H300) And &H1000) <> 0) And timeout > 0
            Asm "pause" : : : "memory"
            timeout = timeout - 1
        Wend

        ' Write destination APIC ID into ICR_HIGH (bits 31:24)
        Arch.X86_64.Apic.LapicWrite &H310, targetApicId LShift 24
        ' Write command into ICR_LOW (triggers send)
        Arch.X86_64.Apic.LapicWrite &H300, vectorFlags
    End Sub

    ''
    ' @brief Initialize all Application Processor cores found in ACPI MADT.
    '        Copies trampoline from its link-time address to physical 0x8000,
    '        patches the CR3 slot, then sends INIT + 2x SIPI to each AP.
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
        ' The linker exposes smp_trampoline_start/end as external labels.
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

        ' smp_cr3_slot offset within trampoline is patched at runtime like PRK does
        Dim cr3SlotLinkAddr As UInt64 = 0
        Asm "movabs $smp_cr3_slot, %0" : "=r"(cr3SlotLinkAddr) : : "memory"
        Dim cr3SlotOffset As UInt64 = cr3SlotLinkAddr - trampolineStart
        Dim cr3SlotPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, TRAMPOLINE_PHYS + cr3SlotOffset)
        cr3SlotPtr(0) = CType(UInt32, cr3Val And &HFFFFFFFF)

        ' Memory fence before sending IPIs
        Asm "mfence" : : : "memory"

        ' Bring up each AP (logical IDs 1..N-1)
        Dim logicalId As UInt32 = 1
        While logicalId < totalCores
            Dim apicId As UInt32 = CType(UInt32, Arch.Acpi.GetApicId(logicalId))

            Serial.PrintF "[SMP] Booting AP Core #%d (APIC ID: %d)...\r\n", logicalId, apicId

            ' Reset handshake flag
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

            ' Wait for AP to acknowledge capture of cpu_id (ap_handshake = 1)
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

            logicalId = logicalId + 1
        Wend

        Serial.PrintF "[SMP] All AP cores initialized. Online: %d/%d\r\n", apJoinCounter, totalCores
    End Sub

    ''
    ' @brief Entry point called by each AP core after long mode entry in the trampoline.
    '        Reads its logical CPU ID from apCurrentId, acknowledges to BSP,
    '        then halts in an idle loop (no scheduler yet).
    ''
    Public Unsafe Sub ApMain()
        ' Capture assigned CPU ID and signal BSP
        Dim cpuId As UInt32 = apCurrentId
        Asm "mfence" : : : "memory"
        apHandshake = 1
        Asm "mfence" : : : "memory"

        ' Enable LAPIC on this AP
        Arch.X86_64.Apic.Initialize

        ' Signal BSP that AP is online
        Asm "lock; addl $1, (%0)" : : "r"(CPtr(Pointer To UInt32, CType(UInt64, CPtr(Pointer To Byte, apJoinCounter)))) : "memory"

        Serial.PrintF "[SMP] AP Core #%d online and idle.\r\n", cpuId

        ' Enable interrupts and idle
        Arch.X86_64.PortIO.Sti
        Do
            Asm "hlt"
        Loop
    End Sub

End Module
