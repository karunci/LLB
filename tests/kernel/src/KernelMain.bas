' Project: Low-Level Basic Compiler (llbc)
' Copyright (c) 2026 karunci. All rights reserved.
'
' Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
' See LICENSE.md for full terms and artificial intelligence training prohibitions.

Module KernelMain

    Import Drivers.Terminal

    ' Helper to send a character to COM1 serial port (0x3F8)
    Private Unsafe Sub WriteSerial(ByVal ch As Byte)
        Dim port As UInt16 = &H3F8
        Asm
            "mov %1, %dx; mov %0, %al; outb %al, %dx"
            :
            : "r"(ch), "r"(port)
        End Asm
    End Sub

    Private Unsafe Sub WriteSerialString(ByVal str As Pointer To Byte)
        Dim i As Int32 = 0
        Do While str(i) <> 0
            WriteSerial str(i)
            i = i + 1
        Loop
    End Sub

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Initialize COM1 line control
        WriteSerialString CPtr(Pointer To Byte, "\r\n[PRK-OS KERNEL] Booting Low-Level Basic Kernel in QEMU!\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Multiboot Verified. Long mode active.\r\n")

        ' Declare Terminal instance
        Dim term As Terminal
        term.Initialize Terminal.COLOR_LIGHT_GREEN, Terminal.COLOR_BLACK
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] VGA Terminal Driver initialized (&HB8000).\r\n")

        term.WriteLine CPtr(Pointer To Byte, "=========================================")
        term.WriteLine CPtr(Pointer To Byte, "      PRK-OS LOW-LEVEL BASIC KERNEL      ")
        term.WriteLine CPtr(Pointer To Byte, "=========================================")
        term.WriteChar 10

        ' Output Multiboot info address in Hex
        term.SetColor Terminal.COLOR_LIGHT_CYAN
        term.WriteString CPtr(Pointer To Byte, "Multiboot Magic: ")
        term.WriteHex CType(UInt64, magic)
        term.WriteChar 10

        term.WriteString CPtr(Pointer To Byte, "Multiboot Info Address: ")
        term.WriteHex CType(UInt64, mbAddress)
        term.WriteChar 10
        term.WriteChar 10

        ' Demonstrate Color Formatting
        term.SetColor Terminal.COLOR_LIGHT_RED
        term.WriteLine CPtr(Pointer To Byte, "[ERROR] Demonstrating red text formatting.")

        term.SetColor Terminal.COLOR_LIGHT_MAGENTA
        term.WriteLine CPtr(Pointer To Byte, "[INFO] Demonstrating magenta text formatting.")

        term.SetColor Terminal.COLOR_YELLOW
        term.WriteLine CPtr(Pointer To Byte, "[WARN] Demonstrating auto-scrolling terminal...")
        term.WriteChar 10

        ' Force screen scrolling by printing multiple lines
        term.SetColor Terminal.COLOR_WHITE
        Dim i As UInt32
        For i = 1 To 30
            term.WriteString CPtr(Pointer To Byte, "Log Entry #")
            term.WriteHex CType(UInt64, i)
            term.WriteLine CPtr(Pointer To Byte, " - Terminal scrolling line test.")
        Next i

        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Initializing IDT interrupt descriptors...\r\n")
        Arch.Idt.Initialize
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] IDT gates registered successfully.\r\n")
        WriteSerialString CPtr(Pointer To Byte, "[PRK-OS KERNEL] Kernel execution completed successfully. Halting CPU.\r\n")

        Do
            Asm "hlt"
        Loop
    End Sub

End Module