' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/KernelMain.bas
' Summary: Main 64-bit kernel entry point and subsystem coordinator.

Module KernelMain

    ' --- Procedural Modules ---
    Import Arch.Idt
    Import Arch.X86_64.Gdt
    Import Arch.X86_64.PortIO
    Import Arch.X86_64.Apic
    Import Arch.X86_64.IoApic

    ' --- Instantiable Classes ---
    Use Drivers.Terminal As Term
    Use Drivers.SerialUart As Serial
    Use Drivers.Keyboard As Kbd
    Use Arch.X86_64.CpuContext
    Use Mem.PhysicalManager As PMM

    ' Helper to send a character to COM1 serial port (0x3F8)
    Private Unsafe Sub WriteSerial(ByVal ch As Byte)
        Dim port As UInt16 = &H3F8
        Arch.X86_64.PortIO.OutB port, ch
    End Sub

    Private Unsafe Sub WriteSerialString(ByVal str As Pointer To Byte)
        Dim i As Int32 = 0
        Do While str(i) <> 0
            WriteSerial str(i)
            i = i + 1
        Loop
    End Sub

    Private Unsafe Sub WriteSerialHex(ByVal value As UInt64)
        WriteSerialString CPtr(Pointer To Byte, "0x")
        If value = 0 Then
            WriteSerialString CPtr(Pointer To Byte, "0")
            Exit Sub
        End If

        Dim digits As Pointer To Byte
        digits = CPtr(Pointer To Byte, "0123456789ABCDEF")

        Dim buffer(16) As Byte
        Dim pos As Int32 = 0

        Do While value > 0
            buffer(pos) = digits(CType(Byte, value And CType(UInt64, 15)))
            value = value RShift 4
            pos = pos + 1
        Loop

        Dim i As Int32
        For i = pos - 1 To 0 Step -1
            WriteSerial buffer(i)
        Next i
    End Sub

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize COM1 line control
        WriteSerialString CPtr(Pointer To Byte, "\r\n[PRK] Booting Low-Level Basic Kernel in QEMU!\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Multiboot Verified. Long mode active.\r\n")

        ' Initialize Serial UART COM1 driver
        Serial.Initialize
        Serial.WriteString CPtr(Pointer To Byte, "[UART] COM1 Driver Online!\n")

        ' Initialize GDT & TSS segment descriptors
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing 64-bit GDT & TSS...\r\n")
        Arch.X86_64.Gdt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] GDT & TSS initialized successfully.\r\n")

        ' Initialize PS/2 Keyboard controller
        Kbd.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] PS/2 Keyboard controller initialized.\r\n")

        ' Initialize VGA Terminal Driver
        Term.Initialize Term.COLOR_LIGHT_GREEN, Term.COLOR_BLACK
        WriteSerialString CPtr(Pointer To Byte, "[PRK] VGA Terminal Driver initialized (&HB8000).\r\n")

        Term.WriteLine CPtr(Pointer To Byte, "=========================================")
        Term.WriteLine CPtr(Pointer To Byte, "      PRK - LOW-LEVEL BASIC KERNEL       ")
        Term.WriteLine CPtr(Pointer To Byte, "=========================================")
        Term.WriteChar 10

        ' Initialize multiple MultiUse CpuContext instances on the kernel stack
        Dim bspContext As Arch.X86_64.CpuContext
        bspContext.Initialize 0, 0, &H200000

        Dim apContext As Arch.X86_64.CpuContext
        apContext.Initialize 1, 1, &H210000

        Term.WriteString CPtr(Pointer To Byte, "[SMP] Initialized BSP CPU ID: ")
        Term.WriteHex CType(UInt64, bspContext.GetCpuId())
        Term.WriteString CPtr(Pointer To Byte, ", AP CPU ID: ")
        Term.WriteHex CType(UInt64, apContext.GetCpuId())
        Term.WriteChar 10
        WriteSerialString CPtr(Pointer To Byte, "[PRK] MultiUse CpuContext instances verified (BSP ID: 0, AP ID: 1).\r\n")

        ' Output Multiboot info address in Hex
        Term.SetColor Term.COLOR_LIGHT_CYAN
        Term.WriteString CPtr(Pointer To Byte, "Multiboot Magic: ")
        Term.WriteHex CType(UInt64, magic)
        Term.WriteChar 10

        Term.WriteString CPtr(Pointer To Byte, "Multiboot Info Address: ")
        Term.WriteHex CType(UInt64, mbAddress)
        Term.WriteChar 10

        ' Initialize Physical Memory Manager (PMM)
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing Physical Memory Manager (PMM)...\r\n")
        PMM.Initialize
        PMM.ParseMemoryMap magic, CType(UInt64, mbAddress)

        Dim totalBytes As UInt64 = PMM.GetTotalBytes()
        Dim freeBytes As UInt64 = PMM.GetFreeBytes()
        Dim totalMB As UInt64 = totalBytes / CType(UInt64, 1048576)
        Dim freeMB As UInt64 = freeBytes / CType(UInt64, 1048576)

        Term.SetColor Term.COLOR_LIGHT_GREEN
        Term.WriteString CPtr(Pointer To Byte, "[PMM] Total Managed RAM: ")
        Term.WriteUInt totalMB
        Term.WriteString CPtr(Pointer To Byte, " MB (")
        Term.WriteUInt totalBytes
        Term.WriteString CPtr(Pointer To Byte, " bytes), Free: ")
        Term.WriteUInt freeMB
        Term.WriteString CPtr(Pointer To Byte, " MB (")
        Term.WriteUInt freeBytes
        Term.WriteLine CPtr(Pointer To Byte, " bytes).")

        ' Verify O(1) Allocation and Freeing
        Dim testPage As UInt64 = PMM.AllocPage()
        Term.WriteString CPtr(Pointer To Byte, "[PMM] Allocated test 4KB frame at: ")
        Term.WriteHex testPage
        Term.WriteChar 10

        If testPage <> 0 Then
            ' Write test pattern to allocated physical page frame
            Dim pagePtr As Volatile Pointer To UInt64
            pagePtr = CPtr(Volatile Pointer To UInt64, testPage)
            pagePtr(0) = &HCAFEBABE12345678
            Term.WriteString CPtr(Pointer To Byte, "[PMM] Frame write verified. Freeing frame back to stack...\n")
            PMM.FreePage testPage
        End If

        WriteSerialString CPtr(Pointer To Byte, "[PRK] Physical Memory Manager online.\r\n")
        Term.WriteChar 10

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
            Term.WriteString CPtr(Pointer To Byte, "Log Entry #")
            Term.WriteHex CType(UInt64, i)
            Term.WriteLine CPtr(Pointer To Byte, " - Terminal scrolling line test.")
        Next i

        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing IDT interrupt descriptors...\r\n")
        Arch.Idt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] IDT gates registered successfully.\r\n")

        ' Initialize Local APIC and I/O APIC Hardware Engines
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing Local APIC...\r\n")
        Arch.X86_64.Apic.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Local APIC online.\r\n")
        
        ' Serial debug logging with "DEBUG - "
        Dim lapicCoreId As UInt32 = Arch.X86_64.Apic.GetLapicId()
        WriteSerialString CPtr(Pointer To Byte, "DEBUG - [APIC] Local APIC Core ID: ")
        WriteSerialHex CType(UInt64, lapicCoreId)
        WriteSerialString CPtr(Pointer To Byte, "\r\n")

        Term.WriteString CPtr(Pointer To Byte, "[APIC] Local APIC online (Core ID: ")
        Term.WriteHex CType(UInt64, lapicCoreId)
        Term.WriteLine CPtr(Pointer To Byte, ").")

        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing I/O APIC Redirection Engine...\r\n")
        Arch.X86_64.IoApic.Initialize
        Arch.X86_64.IoApic.EnableKeyboard
        WriteSerialString CPtr(Pointer To Byte, "[PRK] I/O APIC online. Keyboard IRQ 1 routed to Vector 33.\r\n")

        ' Initialize Periodic LAPIC Timer (Vector 32)
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Calibrating Local APIC Timer (Vector 32)...\r\n")
        Arch.X86_64.Apic.InitializeTimer 3, &H200000
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Local APIC Timer active.\r\n")

        ' Enable hardware interrupts on CPU
        Arch.X86_64.PortIO.Sti
        WriteSerialString CPtr(Pointer To Byte, "[PRK] CPU Hardware Interrupts enabled (STI).\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Kernel boot phase completed successfully.\r\n")

        Do
            Asm "hlt"
        Loop
    End Sub

End Module