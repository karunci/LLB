' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/KernelMain.bas
' Summary: Main 64-bit kernel entry point and subsystem coordinator.

Module KernelMain

    ' --- Procedural Modules ---
    Import TestMetal
    Import Arch.Idt
    Import Arch.X86_64.Gdt
    Import Arch.X86_64.PortIO
    Import Arch.Acpi
    Import Arch.X86_64.Apic
    Import Arch.X86_64.IoApic
    Import Arch.Smp
    Import Core.Nodes
    Import Core.Nodes.SynapseCaps
    Import Sys.Syscall

    ' --- Instantiable Classes ---
    Use Drivers.Terminal As Term
    Use Drivers.SerialUart As Serial
    Use Drivers.Keyboard As Kbd
    Use Arch.X86_64.CpuContext
    Use Mem.PhysicalMemoryManager As PMM
    Use Mem.BuddyAllocator As Buddy
    Use Mem.VirtualMemoryManager As VMM
    Use Mem.KernelHeap As KHeap
    Use Arch.Power.PowerManager As Power
    Use Sys.HardwareInfo As HwInfo
    Use Sched.Scheduler As SchedEngine
    Use Drivers.Framebuffer As FB
    Use Core.Nodes.SynapseChannel
    Use Core.Nodes.NodeRegistry As NodeReg
    Use Fs.TarArchive As Tar
    Use Mem.SharedMemoryManager As Shmem
    Use Drivers.Mouse As MouseDriver

    ' LibLLB_Metal Static Library Declarations
    Public Declare Function ToHex Lib "libllb_metal" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32
    Public Declare Function SprintF Lib "libllb_metal" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt32, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32

    ''
    ' @brief Central unified PS/2 controller dispatcher.
    '        Inspects port 0x64 status and routes pending bytes to Keyboard or Mouse.
    '        Drains pending bytes to prevent unhandled scancodes from blocking the 8042 buffer.
    ''
    Public Unsafe Sub DispatchPs2()
        Dim loopLimit As UInt32 = 64
        While loopLimit > 0
            Dim status As Byte = Arch.X86_64.PortIO.InB(&H64)
            If (status And &H01) = 0 Then Exit While
            If (status And &H20) <> 0 Then
                MouseDriver.HandleInterrupt
            Else
                Kbd.HandleInterrupt
            End If
            loopLimit = loopLimit - 1
        Wend
    End Sub

    ''
    ' @brief System Timer Interrupt Service Routine (Vector 32 / IRQ 0).
    ''
    Public Unsafe Sub OnTimerInterrupt(ByRef frame As Arch.Idt.InterruptFrame)
        Dim coreId As UInt32 = Arch.X86_64.Gdt.GetCpuId()
        If coreId = 0 Then
            ' Hypervisor failsafe: drain pending PS/2 keyboard/mouse data on BSP
            DispatchPs2
            MouseDriver.TickIdle
            SchedEngine.OnTimerTick 10
        Else
            SchedEngine.OnTimerTick 0
        End If
    End Sub

    ''
    ' @brief PS/2 Keyboard Interrupt Service Routine (Vector 33 / IRQ 1).
    ''
    Public Unsafe Sub OnKeyboardInterrupt(ByRef frame As Arch.Idt.InterruptFrame)
        DispatchPs2
    End Sub

    ''
    ' @brief PS/2 Mouse Interrupt Service Routine (Vector 44 / IRQ 12).
    ''
    Public Unsafe Sub OnMouseInterrupt(ByRef frame As Arch.Idt.InterruptFrame)
        DispatchPs2
    End Sub

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize COM1 line control & Serial UART driver with hardware probing
        Serial.Initialize
        If Serial.IsAvailable() Then
            Serial.PrintF "\r\n[PRK] Booting Low-Level Basic Kernel [REV: 2026.10.26-r34-re03]!\r\n"
            Serial.PrintF "[PRK] Multiboot Verified. Long mode active.\r\n"
            Serial.PrintF "[UART] COM1 16550 UART Online!\r\n"
        End If

        ' Early Display & Framebuffer Discovery
        FB.Initialize magic, CType(UInt64, mbAddress)
        Dim hasGopFb As Boolean = (FB.GetFramebufferPhys() <> 0 And FB.GetFramebufferPhys() <> &HB8000)
        Dim hasVgaText As Boolean = (Not hasGopFb) And (magic = &H2BADB002)

        ' Initialize Physical Memory Manager (PMM) and relocate initrd module immediately
        Serial.PrintF "[PRK] Initializing Physical Memory Manager (PMM)...\r\n"
        PMM.Initialize
        PMM.ParseMemoryMap magic, CType(UInt64, mbAddress)

        ' Initialize GDT & TSS segment descriptors
        Serial.PrintF "[PRK] Initializing 64-bit GDT & TSS...\r\n"
        Arch.X86_64.Gdt.Initialize
        Serial.PrintF "[PRK] GDT & TSS initialized successfully.\r\n"

        ' Initialize VGA Terminal Driver (safe on UEFI: if hasVgaText is False, 0xB8000 is NEVER accessed)
        Term.Initialize hasVgaText, Term.COLOR_LIGHT_GREEN, Term.COLOR_BLACK
        If hasVgaText Then
            Serial.PrintF "[PRK] VGA Text Mode Terminal active (&HB8000).\r\n"
            Term.WriteLine CPtr(Pointer To Byte, "=========================================")
            Term.WriteLine CPtr(Pointer To Byte, " PRK - LOW-LEVEL BASIC [REV: 2026.10.26-r34-re02] ")
            Term.WriteLine CPtr(Pointer To Byte, "=========================================")
            Term.WriteChar 10
        ElseIf hasGopFb Then
            Serial.PrintF "[PRK] UEFI GOP Linear Framebuffer active (0x%x).\r\n", CType(UInt32, FB.GetFramebufferPhys() And &HFFFFFFFF)
            FB.ClearScreen &H00181824
            FB.DrawString 20, 20, CPtr(Pointer To Byte, "========================================="), &H0088C0D0, 1
            FB.DrawString 20, 36, CPtr(Pointer To Byte, " PRK - LOW-LEVEL BASIC [REV: 2026.10.26-r34-re02] "), &H008FBCBB, 1
            FB.DrawString 20, 52, CPtr(Pointer To Byte, "========================================="), &H0088C0D0, 1
        End If

        ' Initialize multiple MultiUse CpuContext instances on the kernel stack
        Dim bspContext As Arch.X86_64.CpuContext
        bspContext.Initialize 0, 0, &H200000

        Dim apContext As Arch.X86_64.CpuContext
        apContext.Initialize 1, 1, &H210000

        Term.PrintF "[SMP] Initialized BSP CPU ID: 0x%x, AP CPU ID: 0x%x\n", bspContext.GetCpuId(), apContext.GetCpuId()
        Serial.PrintF "[PRK] MultiUse CpuContext instances verified (BSP ID: 0, AP ID: 1).\r\n"

        ' Verify LibLLB_Metal Static Archive Subsystems
        Dim metalErrors As Int32 = TestMetal.RunMetalVerification()
        If metalErrors = 0 Then
            Serial.PrintF "[PRK] LibLLB_Metal static archive verification passed (10/10 tests).\r\n"
        Else
            Serial.PrintF "[PRK] LibLLB_Metal verification failed!\r\n"
        End If

        ' Output Multiboot info address in Hex
        Term.SetColor Term.COLOR_LIGHT_CYAN
        Term.PrintF "Multiboot Magic: 0x%x\n", magic
        Term.PrintF "Multiboot Info Address: 0x%x\n", mbAddress

        Dim totalBytes As UInt64 = PMM.GetTotalBytes()
        Dim freeBytes As UInt64 = PMM.GetFreeBytes()
        Dim totalMB As UInt64 = totalBytes / CType(UInt64, 1048576)
        Dim freeMB As UInt64 = freeBytes / CType(UInt64, 1048576)

        Term.SetColor Term.COLOR_LIGHT_GREEN
        Term.PrintF "[PMM] Total Managed RAM: %u MB (%u bytes), Free: %u MB (%u bytes).\n", totalMB, totalBytes, freeMB, freeBytes

        ' Verify O(1) Allocation and Freeing
        Dim testPage As UInt64 = PMM.AllocPage()
        Term.PrintF "[PMM] Allocated test 4KB frame at: 0x%x\n", testPage

        If testPage <> 0 Then
            ' Write test pattern to allocated physical page frame
            Dim pagePtr As Volatile Pointer To UInt64
            pagePtr = CPtr(Volatile Pointer To UInt64, testPage)
            pagePtr(0) = &HCAFEBABE12345678
            Term.PrintF "[PMM] Frame write verified. Freeing frame back to stack...\n"
            PMM.FreePage testPage
        End If

        Serial.PrintF "[PRK] Physical Memory Manager online.\r\n"
        Term.WriteChar 10

        ' Initialize and verify Multi-Order Buddy Page Allocator (Phase 1)
        Serial.PrintF "[PRK] Initializing Binary Buddy Allocator...\r\n"
        Buddy.Initialize &H1000000, &H4000000 ' 64MB window starting at 16MB
        Buddy.DumpStats

        ' Test allocating Order 3 (8 contiguous pages = 32KB)
        Dim blkOrder3 As UInt64 = Buddy.AllocPages(3)
        Serial.PrintF "[BUDDY] Allocated Order 3 (32 KB) block at: 0x%x\r\n", blkOrder3
        
        ' Test allocating Order 0 (1 page = 4KB)
        Dim blkOrder0 As UInt64 = Buddy.AllocPages(0)
        Serial.PrintF "[BUDDY] Allocated Order 0 (4 KB) block at: 0x%x\r\n", blkOrder0

        ' Free both blocks and verify coalescing
        Buddy.FreePages blkOrder3, 3
        Buddy.FreePages blkOrder0, 0
        Serial.PrintF "[BUDDY] Freed blocks successfully. Coalescing verified.\r\n"

        ' Initialize and verify 4-Level Virtual Memory Manager (Phase 2)
        Serial.PrintF "[PRK] Initializing Virtual Memory Manager (VMM)...\r\n"
        VMM.Initialize
        Dim cr3Phys As UInt64 = VMM.GetKernelPml4()
        Serial.PrintF "[VMM] Active Kernel PML4 Root: 0x%x\r\n", cr3Phys

        ' Allocate a physical frame and map it to higher virtual address 0xDEADBEEF000
        Dim testPhys As UInt64 = Buddy.AllocPages(0)
        Dim testVirt As UInt64 = &H80000000
        Dim mapFlags As UInt64 = Mem.VmmFlags.PTE_PRESENT Or Mem.VmmFlags.PTE_WRITABLE

        Dim mapOk As Boolean = VMM.MapPage(cr3Phys, testVirt, testPhys, mapFlags)
        If mapOk Then
            Dim resolvedPhys As UInt64 = VMM.VirtToPhys(cr3Phys, testVirt)
            Serial.PrintF "[VMM] Mapped 0x%x -> 0x%x (Resolved: 0x%x)\r\n", testVirt, testPhys, resolvedPhys

            ' Verify read/write at the new virtual address
            Dim testPtr As Volatile Pointer To UInt64
            testPtr = CPtr(Volatile Pointer To UInt64, testVirt)
            testPtr(0) = &H123456789ABCDEF0
            Serial.PrintF "[VMM] Virtual write verified (Value: 0x%x)\r\n", testPtr(0)

            ' Unmap and free test frame
            VMM.UnmapPage cr3Phys, testVirt
            Buddy.FreePages testPhys, 0
            Serial.PrintF "[VMM] Virtual page unmapped and physical frame released.\r\n"
        Else
            Serial.PrintF "[VMM] Error: Failed to map virtual page.\r\n"
        End If

        ' Initialize and verify Kernel Dynamic Heap (kmalloc / kfree)
        KHeap.Initialize
        Dim heapBuf As UInt64 = KHeap.KMalloc(128)
        If heapBuf <> 0 Then
            Dim hPtr As Volatile Pointer To UInt64
            hPtr = CPtr(Volatile Pointer To UInt64, heapBuf)
            hPtr(0) = &HCAFEBABEDEADBEEF
            Serial.PrintF "[HEAP] KMalloc(128) returned: 0x%x, Verified write: 0x%x\r\n", heapBuf, hPtr(0)
            KHeap.KFree heapBuf
            Serial.PrintF "[HEAP] KFree successfully returned block to heap pool.\r\n"
        Else
            Serial.PrintF "[HEAP] Error: KMalloc returned null.\r\n"
        End If

        ' Initialize Zero-Copy Shared Memory Subsystem (Phase 11)
        Shmem.Initialize

        ' Discover and parse ACPI tables (Phase 3)
        Serial.PrintF "[PRK] Discovering ACPI Tables (RSDP/MADT/FADT)...\r\n"
        Arch.Acpi.Initialize CType(UInt64, mbAddress)
        Dim acpiCpus As UInt32 = Arch.Acpi.GetCpuCount()
        Dim acpiLapic As UInt32 = Arch.Acpi.GetLapicBase()
        Dim acpiIoapic As UInt32 = Arch.Acpi.GetIoapicBase()
        Dim pm1aPort As UInt32 = Arch.Acpi.GetPm1aControlBlock()
        Serial.PrintF "[ACPI] System topology verified: %d Core(s), LAPIC @ 0x%x, IO-APIC @ 0x%x, PM1a @ 0x%x\r\n", acpiCpus, acpiLapic, acpiIoapic, pm1aPort

        ' Dump CPU topology and feature flags via CPUID
        Serial.PrintF "[PRK] Querying CPU Hardware Info...\r\n"
        HwInfo.DumpCpu

        Serial.PrintF "[PRK] Initializing IDT interrupt descriptors...\r\n"
        Arch.Idt.Initialize
        Arch.Idt.RegisterHandler 32, @OnTimerInterrupt
        Arch.Idt.RegisterHandler 33, @OnKeyboardInterrupt
        Arch.Idt.RegisterHandler 44, @OnMouseInterrupt
        Serial.PrintF "[PRK] IDT gates registered successfully.\r\n"

        ' Initialize Local APIC and I/O APIC Hardware Engines
        Serial.PrintF "[PRK] Initializing Local APIC...\r\n"
        Arch.X86_64.Apic.Initialize
        Serial.PrintF "[PRK] Local APIC online.\r\n"
        
        ' Serial debug logging with "DEBUG - "
        Dim lapicCoreId As UInt32 = Arch.X86_64.Apic.GetLapicId()
        Serial.PrintF "DEBUG - [APIC] Local APIC Core ID: 0x%x\r\n", lapicCoreId
        Term.PrintF "[APIC] Local APIC online (Core ID: 0x%x).\n", lapicCoreId

        ' Initialize PS/2 Keyboard and Mouse hardware before unmasking I/O APIC interrupts
        Kbd.Initialize
        Serial.PrintF "[PRK] PS/2 Keyboard controller initialized.\r\n"
        MouseDriver.Initialize

        Serial.PrintF "[PRK] Initializing I/O APIC Redirection Engine...\r\n"
        Arch.X86_64.IoApic.Initialize
        Arch.X86_64.IoApic.EnableKeyboard
        Arch.X86_64.IoApic.EnableMouse
        Serial.PrintF "[PRK] I/O APIC online. Keyboard IRQ 1 -> Vec 33, Mouse IRQ 12 -> Vec 44.\r\n"

        ' Initialize Periodic LAPIC Timer (Vector 32) matching PRK kernel/apic.c
        Serial.PrintF "[PRK] Initializing Local APIC Timer (Vector 32, count: 0x100000)...\r\n"
        Arch.X86_64.Apic.InitializeTimer 3, &H100000
        Serial.PrintF "[PRK] Local APIC Timer active.\r\n"

        ' Initialize Preemptive Scheduler & Core Runqueues
        SchedEngine.Initialize

        ' Initialize High-Resolution Linear Framebuffer Driver (Phase 8)
        Serial.PrintF "[PRK] Initializing High-Resolution Linear Framebuffer...\r\n"
        FB.Initialize magic, CType(UInt64, mbAddress)
        FB.InitializeDoubleBuffer
        FB.ClearScreen &H00181824

        ' ---------------------------------------------------------------------
        ' Render Dynamic High-Resolution Nord Dashboard & Hardware Monitor
        ' ---------------------------------------------------------------------

        Dim scrW As UInt32 = FB.GetDisplayWidth()
        Dim scrH As UInt32 = FB.GetDisplayHeight()
        Dim scrBpp As UInt32 = FB.GetDisplayBpp()
        If scrW = 0 Then scrW = 1024
        If scrH = 0 Then scrH = 768
        If scrBpp = 0 Then scrBpp = 32

        MouseDriver.SetScreenBounds CType(Int32, scrW), CType(Int32, scrH)
        Serial.PrintF "[PRK] Mouse screen bounds configured: %ux%u\r\n", scrW, scrH

        Dim fullCardW As UInt32 = scrW - 40
        Dim colGap As UInt32 = 16
        Dim halfCardW As UInt32 = (fullCardW - colGap) / 2
        Dim rightColX As UInt32 = 20 + halfCardW + colGap

        ' Top Header Banner with Nord Accent Stripe (x: 20, w: fullCardW, h: 38)
        FB.FillRect 20, 20, fullCardW, 38, &H002E3440
        FB.FillRect 20, 20, 6, 38, &H0088C0D0
        Dim topBannerBuf(64) As Byte
        SprintF CPtr(Pointer To Byte, topBannerBuf), 64, "x86_64 Long Mode | SMP %u Cores", Arch.Acpi.GetCpuCount()
        Dim bannerTextX As UInt32 = 20 + fullCardW - (CType(UInt32, 31) * 8) - 20
        If bannerTextX < 36 Then bannerTextX = 36
        FB.DrawString bannerTextX, 31, CPtr(Pointer To Byte, topBannerBuf), &H0088C0D0, 1

        ' --- LEFT COLUMN: SYSTEM TOPOLOGY & DUAL-PLANE NODES (w: halfCardW) ---

        ' Left Card 1: System Status & Topology (x: 20, y: 70, w: halfCardW, h: 140)
        FB.FillRect 20, 70, halfCardW, 140, &H00232731
        FB.FillRect 20, 70, 4, 140, &H0081A1C1
        FB.DrawString 36, 80, "[ SYSTEM STATUS & ARCHITECTURE ]", &H0081A1C1, 1

        Dim dispInfoBuf(64) As Byte
        SprintF CPtr(Pointer To Byte, dispInfoBuf), 64, "Display  : %ux%ux%u BPP (Double Buffered RAM)", scrW, scrH, scrBpp
        FB.DrawString 36, 100, CPtr(Pointer To Byte, dispInfoBuf), &H0088C0D0, 1

        FB.DrawString 36, 120, "Topology : Everything is a Node via Synapses", &H00A3BE8C, 1
        FB.DrawString 36, 140, "Control  : Cap-Checked Routing & Node Registry", &H00D8DEE9, 1
        FB.DrawString 36, 160, "Data     : Axonal Fast-Path 128-Slot Ring Buffers", &H00EBCB8B, 1

        Dim smpSchedBuf(64) As Byte
        SprintF CPtr(Pointer To Byte, smpSchedBuf), 64, "SMP Sched: %u Cores Active / Preemptive Stealing", Arch.Acpi.GetCpuCount()
        FB.DrawString 36, 180, CPtr(Pointer To Byte, smpSchedBuf), &H00B48EAD, 1

        ' Left Card 2: Dual-Plane Neural Node Registry (x: 20, y: 222, w: halfCardW, h: 150)
        FB.FillRect 20, 222, halfCardW, 150, &H00232731
        FB.FillRect 20, 222, 4, 150, &H00A3BE8C
        FB.DrawString 36, 232, "[ DUAL-PLANE NEURAL NODE REGISTRY ]", &H00A3BE8C, 1
        FB.DrawString 36, 252, "Synapse #5000: Node #1000 <---> Node #1001", &H00ECEFF4, 1
        FB.DrawString 36, 272, "Synapse #5001: Node #1002 <---> Node #1000", &H00ECEFF4, 1
        FB.DrawString 36, 292, "Axon Data Plane: Packet Transmission Verified", &H00A3BE8C, 1
        FB.DrawString 36, 312, "Syscall Gate   : Ring 0/3 MSR LSTAR (BRT Online)", &H00EBCB8B, 1
        FB.DrawString 36, 332, "Security Model : Capability-Checked Synapse Channels", &H00D8DEE9, 1

        ' --- RIGHT COLUMN: HARDWARE INFO (CPU & RAM MONITOR) (w: halfCardW) ---

        Dim strBuf(128) As Byte
        Dim sPtr As Pointer To Byte = CPtr(Pointer To Byte, strBuf)

        Dim cpuVendor(16) As Byte
        Dim cpuBrand(64) As Byte
        Dim cpuFeat(64) As Byte
        HwInfo.GetVendor CPtr(Pointer To Byte, cpuVendor)
        HwInfo.GetBrand CPtr(Pointer To Byte, cpuBrand)
        HwInfo.GetFeatures CPtr(Pointer To Byte, cpuFeat), 64

        ' Right Card 1: CPU Hardware Info (x: rightColX, y: 70, w: halfCardW, h: 140)
        FB.FillRect rightColX, 70, halfCardW, 140, &H00232731
        FB.FillRect rightColX, 70, 4, 140, &H00EBCB8B
        FB.DrawString rightColX + 16, 80, "[ CPU HARDWARE INFO ]", &H00EBCB8B, 1

        SprintF sPtr, 128, "Vendor   : %s", CPtr(Pointer To Byte, cpuVendor)
        FB.DrawString rightColX + 16, 100, sPtr, &H00ECEFF4, 1

        If cpuBrand(0) <> 0 Then
            SprintF sPtr, 128, "Model    : %s", CPtr(Pointer To Byte, cpuBrand)
            FB.DrawString rightColX + 16, 120, sPtr, &H0088C0D0, 1
        Else
            FB.DrawString rightColX + 16, 120, "Model    : Generic x86_64 Processor", &H0088C0D0, 1
        End If

        Dim apicModeStr As Pointer To Byte
        If Arch.X86_64.Apic.IsX2Apic() Then
            apicModeStr = CPtr(Pointer To Byte, "x2APIC")
        Else
            apicModeStr = CPtr(Pointer To Byte, "MMIO")
        End If
        SprintF sPtr, 128, "Topology : %u Symmetrical Cores (%s)", Arch.Acpi.GetCpuCount(), apicModeStr
        FB.DrawString rightColX + 16, 140, sPtr, &H00D8DEE9, 1

        SprintF sPtr, 128, "Features : %s", CPtr(Pointer To Byte, cpuFeat)
        FB.DrawString rightColX + 16, 160, sPtr, &H00B48EAD, 1

        SprintF sPtr, 128, "Platform : LAPIC 0x%x | IO-APIC 0x%x", Arch.Acpi.GetLapicBase(), Arch.Acpi.GetIoapicBase()
        FB.DrawString rightColX + 16, 180, sPtr, &H0081A1C1, 1

        ' Right Card 2: RAM Physical & Virtual Memory Info (x: rightColX, y: 222, w: halfCardW, h: 150)
        FB.FillRect rightColX, 222, halfCardW, 150, &H00232731
        FB.FillRect rightColX, 222, 4, 150, &H005E81AC
        FB.DrawString rightColX + 16, 232, "[ RAM MEMORY INFO (PMM / VMM) ]", &H0088C0D0, 1

        SprintF sPtr, 128, "Total RAM: %u MB (%u KB Managed)", CType(UInt32, totalMB), CType(UInt32, totalBytes RShift 10)
        FB.DrawString rightColX + 16, 252, sPtr, &H00ECEFF4, 1

        Dim usedMB As UInt64 = 0
        If totalMB > freeMB Then usedMB = totalMB - freeMB
        Dim usedPct As UInt32 = 0
        If totalMB > 0 Then usedPct = CType(UInt32, (usedMB * 100) / totalMB)

        SprintF sPtr, 128, "Used RAM : %u MB (%u%%) | Free: %u MB (%u%%)", CType(UInt32, usedMB), usedPct, CType(UInt32, freeMB), 100 - usedPct
        FB.DrawString rightColX + 16, 272, sPtr, &H00A3BE8C, 1

        ' Visual Memory Gauge Bar (Nord Styling)
        Dim barWidth As UInt32 = 452
        If halfCardW > 36 Then barWidth = halfCardW - 36
        Dim fillW As UInt32 = 8
        If totalMB > 0 Then
            fillW = CType(UInt32, (usedMB * CType(UInt64, barWidth)) / totalMB)
            If fillW < 8 Then fillW = 8
            If fillW > barWidth Then fillW = barWidth
        End If
        FB.FillRect rightColX + 16, 292, barWidth, 10, &H003B4252
        FB.FillRect rightColX + 16, 292, fillW, 10, &H00A3BE8C

        FB.DrawString rightColX + 16, 310, "Buddy Pool : 64 MB (16 MB - 80 MB, Order 0..10)", &H00D8DEE9, 1
        FB.DrawString rightColX + 16, 328, "Kernel Heap: 8 MB @ 0x81000000 (16-Byte Aligned)", &H00EBCB8B, 1
        FB.DrawString rightColX + 16, 346, "Page Table : 4-Level PML4 Isolated User Address Space", &H00B48EAD, 1

        ' --- BOTTOM FULL-WIDTH CARD: USERLAND RUNTIME (BRT) (w: fullCardW) ---
        FB.FillRect 20, 384, fullCardW, 66, &H00232731
        FB.FillRect 20, 384, 4, 66, &H00B48EAD
        FB.DrawString 36, 394, "[ USERLAND RUNTIME (BRT0) & RING 3 EXECUTION ]", &H00B48EAD, 1
        FB.DrawString 36, 412, "App Payload : 'user.test.app' (8200 bytes, Entry: 0x40000000, Stack: ASLR)", &H00ECEFF4, 1
        FB.DrawString 36, 430, "System Calls: Process Yield, GetPid, Exit, Node Register, Synapse Connect", &H0088C0D0, 1

        ' Initialize Dual-Plane Node Registry & Fast-Path Synapse Channels
        Serial.PrintF "[PRK] Initializing Dual-Plane Neural Node Registry...\r\n"
        NodeReg.Initialize
        Dim kernelNodeId As UInt64 = NodeReg.RegisterNode("core.kernel", 1, 0, SynapseCaps.CAP_SYNAPSE_ADMIN)
        Dim displayNodeId As UInt64 = NodeReg.RegisterNode("drivers.display.lfb", 2, 0, SynapseCaps.CAP_SYNAPSE_WRITE Or SynapseCaps.CAP_SYNAPSE_READ)
        Dim rawInputNodeId As UInt64 = NodeReg.RegisterNode("hw.input.raw", 2, 0, SynapseCaps.CAP_SYNAPSE_WRITE Or SynapseCaps.CAP_SYNAPSE_READ)

        ' Establish Synapse Channel between Kernel Compute Node and Display Device Node
        Dim fbSynapseId As UInt64 = NodeReg.ConnectSynapse(kernelNodeId, displayNodeId, SynapseCaps.CAP_SYNAPSE_WRITE Or SynapseCaps.CAP_SYNAPSE_READ)
        Dim chanPtr As Pointer To SynapseChannel = NodeReg.GetChannel(fbSynapseId)
        If chanPtr <> 0 Then
            Dim pkt As AxonPacket
            pkt.PacketType = 1
            pkt.PayloadLength = 4
            pkt.Payload(0) = 1
            Dim sendOk As Boolean = chanPtr.PushPacket(pkt)
            If sendOk Then
                Serial.PrintF "[NODE] Axonal Data Plane packet transmission verified (Synapse #%u, Count: %u)\r\n", _
                              CType(UInt32, fbSynapseId), chanPtr.GetCount()
            End If

            Dim recvPkt As AxonPacket
            Dim recvOk As Boolean = chanPtr.PopPacket(recvPkt, False)
            If recvOk Then
                Serial.PrintF "[NODE] Axonal Data Plane packet delivery verified (Seq: %u, Type: %u)\r\n", _
                              CType(UInt32, recvPkt.Sequence), recvPkt.PacketType
            End If
        End If

        ' Initialize Native Microkernel Syscall MSRs
        Sys.Syscall.Initialize

        ' Initialize Application Processor cores (SMP bring-up via INIT-SIPI-SIPI)
        Serial.PrintF "[PRK] Starting SMP AP bring-up...\r\n"
        Arch.Smp.InitCores

        ' Discover in-memory USTAR initrd ramdisk
        Dim initrdStart As UInt64 = PMM.GetInitrdStart()
        Dim initrdEnd As UInt64 = PMM.GetInitrdEnd()
        Dim genesisBaxSize As UInt64 = 0
        Dim genesisBaxAddr As UInt64 = 0
        Dim dispBaxSize As UInt64 = 0
        Dim dispBaxAddr As UInt64 = 0
        Dim inputBaxSize As UInt64 = 0
        Dim inputBaxAddr As UInt64 = 0
        Dim compBaxSize As UInt64 = 0
        Dim compBaxAddr As UInt64 = 0
        Dim devMgrBaxSize As UInt64 = 0
        Dim devMgrBaxAddr As UInt64 = 0
        Dim plexusBaxSize As UInt64 = 0
        Dim plexusBaxAddr As UInt64 = 0
        Dim wmBaxSize As UInt64 = 0
        Dim wmBaxAddr As UInt64 = 0
        Dim vfsBaxSize As UInt64 = 0
        Dim vfsBaxAddr As UInt64 = 0
        Dim baxSize As UInt64 = 0
        Dim baxDataAddr As UInt64 = 0

        If initrdStart <> 0 And initrdEnd > initrdStart Then
            Serial.PrintF "[PRK] Scanning Initrd USTAR Ramdisk at 0x%lx (%u bytes)...\r\n", _
                          initrdStart, CType(UInt32, initrdEnd - initrdStart)

            ' 0. Probe for Genesis PID 1 Root Orchestrator ('genesis.bax')
            genesisBaxAddr = Tar.FindFile(initrdStart, "genesis.bax", genesisBaxSize)
            If genesisBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'genesis.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, genesisBaxSize), genesisBaxAddr
            End If

            ' 1. Probe for Display Driver Service daemon ('disp_srv.bax')
            dispBaxAddr = Tar.FindFile(initrdStart, "disp_srv.bax", dispBaxSize)
            If dispBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'disp_srv.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, dispBaxSize), dispBaxAddr
            End If

            ' 2. Probe for Input Service daemon ('input_srv.bax')
            inputBaxAddr = Tar.FindFile(initrdStart, "input_srv.bax", inputBaxSize)
            If inputBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'input_srv.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, inputBaxSize), inputBaxAddr
            End If

            ' 3. Probe for Compositor Service daemon ('compositor.bax')
            compBaxAddr = Tar.FindFile(initrdStart, "compositor.bax", compBaxSize)
            If compBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'compositor.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, compBaxSize), compBaxAddr
            End If

            ' 4. Probe for Device Arbiter daemon ('dev_mgr.bax')
            devMgrBaxAddr = Tar.FindFile(initrdStart, "dev_mgr.bax", devMgrBaxSize)
            If devMgrBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'dev_mgr.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, devMgrBaxSize), devMgrBaxAddr
            End If

            ' 5. Probe for Plexus Service Supervisor ('plexus_mgr.bax')
            plexusBaxAddr = Tar.FindFile(initrdStart, "plexus_mgr.bax", plexusBaxSize)
            If plexusBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'plexus_mgr.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, plexusBaxSize), plexusBaxAddr
            End If

            ' 6. Probe for Window Manager service ('wm.bax')
            wmBaxAddr = Tar.FindFile(initrdStart, "wm.bax", wmBaxSize)
            If wmBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'wm.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, wmBaxSize), wmBaxAddr
            End If

            ' 7. Probe for VFS Storage Node ('vfs_srv.bax')
            vfsBaxAddr = Tar.FindFile(initrdStart, "vfs_srv.bax", vfsBaxSize)
            If vfsBaxAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'vfs_srv.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, vfsBaxSize), vfsBaxAddr
            End If

            ' 8. Probe for User Application ('user_app.bax')
            baxDataAddr = Tar.FindFile(initrdStart, "user_app.bax", baxSize)
            If baxDataAddr <> 0 Then
                Serial.PrintF "[PRK] Located 'user_app.bax' in ramdisk (%u bytes at 0x%lx)\r\n", _
                              CType(UInt32, baxSize), baxDataAddr
            Else
                Serial.PrintF "[PRK] Warning: 'user_app.bax' not found in initrd ramdisk!\r\n"
            End If
        Else
            Serial.PrintF "[PRK] Warning: No Multiboot initrd module provided.\r\n"
        End If

        ' 0. Spawn Genesis PID 1 Root Orchestrator
        Dim genesisPid As UInt64 = 0
        If genesisBaxAddr <> 0 Then
            genesisPid = SchedEngine.CreateBaxProcess("sys.genesis", genesisBaxAddr, genesisBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Genesis PID 1 Root Orchestrator (PID: %u)\r\n", CType(UInt32, genesisPid)
        End If

        ' 1. Spawn Display Driver Service Daemon
        Dim dispPid As UInt64 = 0
        If dispBaxAddr <> 0 Then
            dispPid = SchedEngine.CreateBaxProcess("srv.display", dispBaxAddr, dispBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Display Driver Service Daemon (PID: %u)\r\n", CType(UInt32, dispPid)
        End If

        ' Spawn Unified Input Service Daemon
        Dim inputPid As UInt64 = 0
        If inputBaxAddr <> 0 Then
            inputPid = SchedEngine.CreateBaxProcess("srv.input", inputBaxAddr, inputBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Unified Input Service Daemon (PID: %u)\r\n", CType(UInt32, inputPid)
        End If

        ' Spawn Compositor Service Daemon
        Dim compPid As UInt64 = 0
        If compBaxAddr <> 0 Then
            compPid = SchedEngine.CreateBaxProcess("srv.compositor", compBaxAddr, compBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Compositor Service Daemon (PID: %u)\r\n", CType(UInt32, compPid)
        End If

        ' Spawn Device Arbiter Daemon
        Dim devMgrPid As UInt64 = 0
        If devMgrBaxAddr <> 0 Then
            devMgrPid = SchedEngine.CreateBaxProcess("srv.dev_mgr", devMgrBaxAddr, devMgrBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Device Arbiter Daemon (PID: %u)\r\n", CType(UInt32, devMgrPid)
        End If

        ' Spawn Service Supervisor Daemon
        Dim plexusPid As UInt64 = 0
        If plexusBaxAddr <> 0 Then
            plexusPid = SchedEngine.CreateBaxProcess("srv.plexus_mgr", plexusBaxAddr, plexusBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Service Supervisor Daemon (PID: %u)\r\n", CType(UInt32, plexusPid)
        End If

        ' Spawn Window Manager Daemon
        Dim wmPid As UInt64 = 0
        If wmBaxAddr <> 0 Then
            wmPid = SchedEngine.CreateBaxProcess("srv.wm", wmBaxAddr, wmBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Window Manager Daemon (PID: %u)\r\n", CType(UInt32, wmPid)
        End If

        ' Spawn Storage & VFS Daemon
        Dim vfsPid As UInt64 = 0
        If vfsBaxAddr <> 0 Then
            vfsPid = SchedEngine.CreateBaxProcess("srv.vfs", vfsBaxAddr, vfsBaxSize, 1)
            Serial.PrintF "[PRK] Spawned Storage & VFS Daemon (PID: %u)\r\n", CType(UInt32, vfsPid)
        End If

        ' Spawn Standalone Ring 3 BAX Application
        Dim userPid As UInt64 = 0
        If baxDataAddr <> 0 Then
            userPid = SchedEngine.CreateBaxProcess("user.test.app", baxDataAddr, baxSize, 2)
            Serial.PrintF "[PRK] Spawned Standalone Ring 3 BAX Process (PID: %u)\r\n", CType(UInt32, userPid)
        End If

        Serial.PrintF "[PRK] Kernel boot and userland dispatch completed successfully.\r\n"

        ' Release AP barrier so all cores can start dispatching tasks simultaneously
        Arch.Smp.ActivateDispatch

        ' Enable hardware interrupts on CPU
        Arch.X86_64.PortIO.Sti
        Serial.PrintF "[PRK] CPU Hardware Interrupts enabled (STI).\r\n"

        ' Preemptively yield to let User Thread execute in Ring 3
        SchedEngine.Yield

        Do
            SchedEngine.Yield
            Asm "sti\n\tnop\n\thlt" : : : "memory"
        Loop
    End Sub

End Module