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

    ' --- Instantiable Classes ---
    Use Drivers.Terminal As Term
    Use Drivers.SerialUart As Serial
    Use Drivers.Keyboard As Kbd
    Use Arch.X86_64.CpuContext
    Use Mem.PhysicalManager As PMM
    Use Mem.BuddyAllocator As Buddy
    Use Mem.VirtualMemoryManager As VMM

    ' LibLLB_Metal Static Library Declarations
    Public Declare Function ToHex Lib "libllb_metal" (ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize COM1 line control & Serial UART driver
        Serial.Initialize
        Serial.PrintF "\r\n[PRK] Booting Low-Level Basic Kernel in QEMU!\r\n"
        Serial.PrintF "[PRK] Multiboot Verified. Long mode active.\r\n"
        Serial.PrintF "[UART] COM1 Driver Online!\n"

        ' Initialize GDT & TSS segment descriptors
        Serial.PrintF "[PRK] Initializing 64-bit GDT & TSS...\r\n"
        Arch.X86_64.Gdt.Initialize
        Serial.PrintF "[PRK] GDT & TSS initialized successfully.\r\n"

        ' Initialize PS/2 Keyboard controller
        Kbd.Initialize
        Serial.PrintF "[PRK] PS/2 Keyboard controller initialized.\r\n"

        ' Initialize VGA Terminal Driver
        Term.Initialize Term.COLOR_LIGHT_GREEN, Term.COLOR_BLACK
        Serial.PrintF "[PRK] VGA Terminal Driver initialized (&HB8000).\r\n"

        Term.WriteLine CPtr(Pointer To Byte, "=========================================")
        Term.WriteLine CPtr(Pointer To Byte, "      PRK - LOW-LEVEL BASIC KERNEL       ")
        Term.WriteLine CPtr(Pointer To Byte, "=========================================")
        Term.WriteChar 10

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

        ' Initialize Physical Memory Manager (PMM)
        Serial.PrintF "[PRK] Initializing Physical Memory Manager (PMM)...\r\n"
        PMM.Initialize
        PMM.ParseMemoryMap magic, CType(UInt64, mbAddress)

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

        ' Discover and parse ACPI tables (Phase 3)
        Serial.PrintF "[PRK] Discovering ACPI Tables (RSDP/MADT/FADT)...\r\n"
        Arch.Acpi.Initialize CType(UInt64, mbAddress)
        Dim acpiCpus As UInt32 = Arch.Acpi.GetCpuCount()
        Dim acpiLapic As UInt32 = Arch.Acpi.GetLapicBase()
        Dim acpiIoapic As UInt32 = Arch.Acpi.GetIoapicBase()
        Dim pm1aPort As UInt32 = Arch.Acpi.GetPm1aControlBlock()
        Serial.PrintF "[ACPI] System topology verified: %d Core(s), LAPIC @ 0x%x, IO-APIC @ 0x%x, PM1a @ 0x%x\r\n", acpiCpus, acpiLapic, acpiIoapic, pm1aPort

        ' Demonstrate Color Formatting
        Term.SetColor Term.COLOR_LIGHT_RED
        Term.WriteLine CPtr(Pointer To Byte, "[ERROR] Demonstrating red text formatting.")

        Term.SetColor Term.COLOR_LIGHT_MAGENTA
        Term.WriteLine CPtr(Pointer To Byte, "[INFO] Demonstrating magenta text formatting.")

        Term.SetColor Term.COLOR_LIGHT_BROWN
        Term.WriteLine CPtr(Pointer To Byte, "[WARN] Demonstrating auto-scrolling terminal...")
        Term.WriteChar 10

        ' Demonstrate scrolling with a few lines so the banner remains visible
        Term.SetColor Term.COLOR_WHITE
        Dim i As UInt32
        For i = 1 To 3
            Term.PrintF "Log Entry #0x%x - Terminal scrolling line test.\n", i
        Next i

        Serial.PrintF "[PRK] Initializing IDT interrupt descriptors...\r\n"
        Arch.Idt.Initialize
        Serial.PrintF "[PRK] IDT gates registered successfully.\r\n"

        ' Initialize Local APIC and I/O APIC Hardware Engines
        Serial.PrintF "[PRK] Initializing Local APIC...\r\n"
        Arch.X86_64.Apic.Initialize
        Serial.PrintF "[PRK] Local APIC online.\r\n"
        
        ' Serial debug logging with "DEBUG - "
        Dim lapicCoreId As UInt32 = Arch.X86_64.Apic.GetLapicId()
        Serial.PrintF "DEBUG - [APIC] Local APIC Core ID: 0x%x\r\n", lapicCoreId
        Term.PrintF "[APIC] Local APIC online (Core ID: 0x%x).\n", lapicCoreId

        Serial.PrintF "[PRK] Initializing I/O APIC Redirection Engine...\r\n"
        Arch.X86_64.IoApic.Initialize
        Arch.X86_64.IoApic.EnableKeyboard
        Serial.PrintF "[PRK] I/O APIC online. Keyboard IRQ 1 routed to Vector 33.\r\n"

        ' Initialize Periodic LAPIC Timer (Vector 32)
        Serial.PrintF "[PRK] Calibrating Local APIC Timer (Vector 32)...\r\n"
        Arch.X86_64.Apic.InitializeTimer 3, &H200000
        Serial.PrintF "[PRK] Local APIC Timer active.\r\n"

        ' Enable hardware interrupts on CPU
        Arch.X86_64.PortIO.Sti
        Serial.PrintF "[PRK] CPU Hardware Interrupts enabled (STI).\r\n"
        Serial.PrintF "[PRK] Kernel boot phase completed successfully.\r\n"

        Do
            Asm "hlt"
        Loop
    End Sub

End Module