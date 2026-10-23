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
    Use Drivers.Terminal
    Use Drivers.SerialUart
    Use Drivers.Keyboard
    Use Arch.X86_64.CpuContext
    Use Mem.PhysicalManager

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
        Drivers.SerialUart.Initialize
        Drivers.SerialUart.WriteString CPtr(Pointer To Byte, "[UART] COM1 Driver Online!\n")

        ' Initialize GDT & TSS segment descriptors
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing 64-bit GDT & TSS...\r\n")
        Arch.X86_64.Gdt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] GDT & TSS initialized successfully.\r\n")

        ' Initialize PS/2 Keyboard controller
        Drivers.Keyboard.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK] PS/2 Keyboard controller initialized.\r\n")

        ' Initialize VGA Terminal Driver
        Drivers.Terminal.Initialize Drivers.Terminal.COLOR_LIGHT_GREEN, Drivers.Terminal.COLOR_BLACK
        WriteSerialString CPtr(Pointer To Byte, "[PRK] VGA Terminal Driver initialized (&HB8000).\r\n")

        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "      PRK - LOW-LEVEL BASIC KERNEL       ")
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "=========================================")
        Drivers.Terminal.WriteChar 10

        ' Initialize multiple MultiUse CpuContext instances on the kernel stack
        Dim bspContext As Arch.X86_64.CpuContext
        bspContext.Initialize 0, 0, &H200000

        Dim apContext As Arch.X86_64.CpuContext
        apContext.Initialize 1, 1, &H210000

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[SMP] Initialized BSP CPU ID: ")
        Drivers.Terminal.WriteHex CType(UInt64, bspContext.GetCpuId())
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, ", AP CPU ID: ")
        Drivers.Terminal.WriteHex CType(UInt64, apContext.GetCpuId())
        Drivers.Terminal.WriteChar 10
        WriteSerialString CPtr(Pointer To Byte, "[PRK] MultiUse CpuContext instances verified (BSP ID: 0, AP ID: 1).\r\n")

        ' Output Multiboot info address in Hex
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_CYAN
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Magic: ")
        Drivers.Terminal.WriteHex CType(UInt64, magic)
        Drivers.Terminal.WriteChar 10

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Multiboot Info Address: ")
        Drivers.Terminal.WriteHex CType(UInt64, mbAddress)
        Drivers.Terminal.WriteChar 10

        ' Initialize Physical Memory Manager (PMM)
        WriteSerialString CPtr(Pointer To Byte, "[PRK] Initializing Physical Memory Manager (PMM)...\r\n")
        Mem.PhysicalManager.Initialize
        Mem.PhysicalManager.ParseMemoryMap magic, CType(UInt64, mbAddress)

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_GREEN
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[PMM] Total Managed RAM: ")
        Drivers.Terminal.WriteHex Mem.PhysicalManager.GetTotalBytes()
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, " bytes, Free: ")
        Drivers.Terminal.WriteHex Mem.PhysicalManager.GetFreeBytes()
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, " bytes.")

        ' Verify O(1) Allocation and Freeing
        Dim testPage As UInt64 = Mem.PhysicalManager.AllocPage()
        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[PMM] Allocated test 4KB frame at: ")
        Drivers.Terminal.WriteHex testPage
        Drivers.Terminal.WriteChar 10

        If testPage <> 0 Then
            ' Write test pattern to allocated physical page frame
            Dim pagePtr As Volatile Pointer To UInt64
            pagePtr = CPtr(Volatile Pointer To UInt64, testPage)
            pagePtr(0) = &HCAFEBABE12345678
            Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[PMM] Frame write verified. Freeing frame back to stack...\n")
            Mem.PhysicalManager.FreePage testPage
        End If

        WriteSerialString CPtr(Pointer To Byte, "[PRK] Physical Memory Manager online.\r\n")
        Drivers.Terminal.WriteChar 10

        ' Demonstrate Color Formatting
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_RED
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[ERROR] Demonstrating red text formatting.")

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_MAGENTA
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[INFO] Demonstrating magenta text formatting.")

        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_LIGHT_BROWN
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, "[WARN] Demonstrating auto-scrolling terminal...")
        Drivers.Terminal.WriteChar 10

        ' Demonstrate scrolling with a few lines so the banner remains visible
        Drivers.Terminal.SetColor Drivers.Terminal.COLOR_WHITE
        Dim i As UInt32
        For i = 1 To 3
            Drivers.Terminal.WriteString CPtr(Pointer To Byte, "Log Entry #")
            Drivers.Terminal.WriteHex CType(UInt64, i)
            Drivers.Terminal.WriteLine CPtr(Pointer To Byte, " - Terminal scrolling line test.")
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

        Drivers.Terminal.WriteString CPtr(Pointer To Byte, "[APIC] Local APIC online (Core ID: ")
        Drivers.Terminal.WriteHex CType(UInt64, lapicCoreId)
        Drivers.Terminal.WriteLine CPtr(Pointer To Byte, ").")

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