' Project Name: PRK-OS
' Filename: src/KernelMain.bas
' Summary: Low-Level Basic Kernel demonstrating Terminal class usage with colors and scrolling.

Module KernelMain

    Import Drivers.Terminal

    Public Unsafe Sub KernelEntry(ByVal magic As UInt32, ByVal mbAddress As Pointer To Byte)
        ' Declare Terminal instance
        Dim term As Terminal
        term.Initialize Terminal.COLOR_LIGHT_GREEN, Terminal.COLOR_BLACK

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

        Do
            Asm "hlt"
        Loop
    End Sub

End Module