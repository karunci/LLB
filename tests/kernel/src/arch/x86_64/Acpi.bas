' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/x86_64/Acpi.bas
' Summary: ACPI Parser - reads RSDP from Multiboot2 tag (type 14/15), then parses
'          RSDT/XSDT to extract MADT (CPU topology, LAPIC, IO-APIC) and FADT (power).

Module Arch.Acpi

    Import Sync
    Import Arch.X86_64.PortIO
    Use Drivers.SerialUart

    ' -------------------------------------------------------------------------
    ' Packed ACPI Structures
    ' -------------------------------------------------------------------------

    <Packed>
    Public Structure RsdpDescriptor
        Public Signature As UInt64        ' "RSD PTR " (8 bytes)
        Public Checksum As Byte
        Public OemId(5) As Byte
        Public Revision As Byte           ' 0 = ACPI 1.0, 2 = ACPI 2.0+
        Public RsdtAddress As UInt32      ' Physical address of RSDT
        Public Length As UInt32
        Public XsdtAddress As UInt64      ' Physical address of XSDT (64-bit)
        Public ExtendedChecksum As Byte
        Public Reserved(2) As Byte
    End Structure

    <Packed>
    Public Structure AcpiHeader
        Public Signature As UInt32        ' 4-byte ASCII signature
        Public Length As UInt32
        Public Revision As Byte
        Public Checksum As Byte
        Public OemId(5) As Byte
        Public OemTableId As UInt64
        Public OemRevision As UInt32
        Public CreatorId As UInt32
        Public CreatorRevision As UInt32
    End Structure

    ' Multiboot2 tag header (type + size)
    <Packed>
    Private Structure Mb2TagHeader
        Public TagType As UInt32
        Public TagSize As UInt32
    End Structure

    ' -------------------------------------------------------------------------
    ' Module-level state
    ' -------------------------------------------------------------------------
    Private rsdpPhys    As UInt64 = 0
    Private rsdtPhys    As UInt32 = 0
    Private xsdtPhys    As UInt64 = 0
    Private madtPhys    As UInt64 = 0
    Private fadtPhys    As UInt64 = 0
    Private acpiVersion As Byte   = 0

    ' MADT-extracted topology
    Private lapicAddress  As UInt32 = &HFEE00000
    Private ioapicAddress As UInt32 = &HFEC00000
    Private cpuCount      As UInt32 = 0

    ' FADT power registers
    Private pm1aControlBlock As UInt32 = 0
    Private pm1bControlBlock As UInt32 = 0
    Private slpTypA          As UInt16 = 0
    Private resetRegister    As UInt32 = 0
    Private resetValue       As Byte   = 0
    Private hasResetReg      As Boolean = False

    Private acpiLock As Sync.Spinlock

    ' -------------------------------------------------------------------------

    ''
    ' @brief Verify 8-bit ACPI checksum over a memory buffer.
    ' @param baseAddr Physical start address.
    ' @param length   Table length in bytes.
    ' @return True if byte sum mod 256 is zero.
    ''
    Public Unsafe Function VerifyChecksum(ByVal baseAddr As UInt64, ByVal length As UInt32) As Boolean
        Dim ptr As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, baseAddr)
        Dim sum As Byte = 0
        Dim i As UInt32 = 0
        While i < length
            sum = sum + ptr(i)
            i = i + 1
        Wend
        VerifyChecksum = (sum = 0)
    End Function

    ''
    ' @brief Scan Multiboot2 tag list for RSDP (tag type 14 = RSDPv1, 15 = RSDPv2).
    '        Mirrors PRK acpi_init() MBI tag walk.
    ' @param mbAddress Physical address of the Multiboot2 info structure.
    ' @return True if a valid RSDP tag was found.
    ''
    Private Unsafe Function LocateRsdpFromMbi(ByVal mbAddress As UInt64) As Boolean
        If mbAddress = 0 Then
            LocateRsdpFromMbi = False
            Exit Function
        End If

        ' MBI starts with a 32-bit total_size, followed by 4 bytes reserved, then tags at +8
        Dim tagPtr As UInt64 = mbAddress + 8
        Dim totalSize As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, mbAddress)
        Dim endPtr As UInt64 = mbAddress + CType(UInt64, totalSize(0))

        While tagPtr < endPtr
            Dim tagHdr As Volatile Pointer To Mb2TagHeader = CPtr(Volatile Pointer To Mb2TagHeader, tagPtr)
            Dim tagType As UInt32 = tagHdr.TagType
            Dim tagSize As UInt32 = tagHdr.TagSize

            If tagType = 0 Then Exit While ' End tag

            ' Tag 14 = ACPI 1.0 RSDP, Tag 15 = ACPI 2.0 RSDP
            If tagType = 14 Or tagType = 15 Then
                rsdpPhys = tagPtr + 8  ' RSDP data begins 8 bytes into the tag
                LocateRsdpFromMbi = True
                Exit Function
            End If

            ' Advance to next tag, 8-byte aligned
            Dim nextOffset As UInt32 = tagSize
            If nextOffset Mod 8 <> 0 Then
                nextOffset = ((nextOffset + 7) / 8) * 8
            End If
            tagPtr = tagPtr + CType(UInt64, nextOffset)
        Wend

        LocateRsdpFromMbi = False
    End Function

    ''
    ' @brief Initialize ACPI: find RSDP via MBI tags, parse RSDT/XSDT, extract MADT and FADT.
    ' @param mbAddress Physical address of the Multiboot2 info structure passed by bootloader.
    ''
    Public Unsafe Sub Initialize(ByVal mbAddress As UInt64)
        Sync.SpinlockOps.Init acpiLock

        If Not LocateRsdpFromMbi(mbAddress) Then
            Drivers.SerialUart.PrintF "[ACPI] Warning: RSDP not found in MBI tags.\r\n"
            Exit Sub
        End If

        Dim rsdp As Volatile Pointer To RsdpDescriptor = CPtr(Volatile Pointer To RsdpDescriptor, rsdpPhys)
        acpiVersion = rsdp.Revision
        rsdtPhys    = rsdp.RsdtAddress
        xsdtPhys    = rsdp.XsdtAddress

        Drivers.SerialUart.PrintF "[ACPI] RSDP @ 0x%x | Rev: %d | RSDT: 0x%x | XSDT: 0x%x\r\n", _
            rsdpPhys, CType(UInt32, acpiVersion), CType(UInt64, rsdtPhys), xsdtPhys

        If acpiVersion >= 2 And xsdtPhys <> 0 Then
            ParseXsdt xsdtPhys
        ElseIf rsdtPhys <> 0 Then
            ParseRsdt rsdtPhys
        End If

        If madtPhys <> 0 Then ParseMadt madtPhys
        If fadtPhys <> 0 Then ParseFadt fadtPhys
    End Sub

    ''
    ' @brief Parse 32-bit RSDT entries to locate MADT ('APIC') and FADT ('FACP').
    ' @param base Physical address of the RSDT.
    ''
    Private Unsafe Sub ParseRsdt(ByVal base As UInt32)
        Dim hdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, CType(UInt64, base))
        If Not VerifyChecksum(CType(UInt64, base), hdr.Length) Then
            Drivers.SerialUart.PrintF "[ACPI] Error: RSDT checksum failure.\r\n"
            Exit Sub
        End If

        Dim count As UInt32 = (hdr.Length - 36) / 4
        Dim entriesPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, CType(UInt64, base) + 36)

        Dim i As UInt32 = 0
        While i < count
            Dim tblPhys As UInt32 = entriesPtr(i)
            If tblPhys <> 0 Then
                Dim tblHdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, CType(UInt64, tblPhys))
                ' 'APIC' = 0x43495041, 'FACP' = 0x50434146
                If tblHdr.Signature = &H43495041 Then
                    madtPhys = CType(UInt64, tblPhys)
                ElseIf tblHdr.Signature = &H50434146 Then
                    fadtPhys = CType(UInt64, tblPhys)
                End If
            End If
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Parse 64-bit XSDT entries to locate MADT ('APIC') and FADT ('FACP').
    ' @param base Physical address of the XSDT.
    ''
    Private Unsafe Sub ParseXsdt(ByVal base As UInt64)
        Dim hdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, base)
        If Not VerifyChecksum(base, hdr.Length) Then
            Drivers.SerialUart.PrintF "[ACPI] Error: XSDT checksum failure.\r\n"
            Exit Sub
        End If

        Dim count As UInt32 = (hdr.Length - 36) / 8
        Dim entriesPtr As Volatile Pointer To UInt64 = CPtr(Volatile Pointer To UInt64, base + 36)

        Dim i As UInt32 = 0
        While i < count
            Dim tblPhys As UInt64 = entriesPtr(i)
            If tblPhys <> 0 Then
                Dim tblHdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, tblPhys)
                If tblHdr.Signature = &H43495041 Then
                    madtPhys = tblPhys
                ElseIf tblHdr.Signature = &H50434146 Then
                    fadtPhys = tblPhys
                End If
            End If
            i = i + 1
        Wend
    End Sub

    ''
    ' @brief Parse MADT to extract LAPIC base, IO-APIC base, and enabled CPU count.
    '        Only counts cores with Flags Bit 0 set (Enabled). Mirrors PRK MADT logic.
    ' @param base Physical address of the MADT table.
    ''
    Private Unsafe Sub ParseMadt(ByVal base As UInt64)
        Dim hdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, base)
        If Not VerifyChecksum(base, hdr.Length) Then
            Drivers.SerialUart.PrintF "[ACPI] Error: MADT checksum failure.\r\n"
            Exit Sub
        End If

        ' LAPIC address is at MADT offset 36 (after 36-byte ACPI header)
        Dim lapicPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, base + 36)
        lapicAddress = lapicPtr(0)
        cpuCount = 0

        ' MADT records start at offset 44 (after header + 4-byte LAPIC addr + 4-byte flags)
        Dim offset As UInt64 = base + 44
        Dim limit  As UInt64 = base + CType(UInt64, hdr.Length)

        While offset < limit
            Dim entryPtr As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, offset)
            Dim entryType As Byte = entryPtr(0)
            Dim entryLen  As Byte = entryPtr(1)

            If entryLen = 0 Then Exit While

            If entryType = 0 Then
                ' Type 0: Processor Local APIC
                ' Byte 4 = Flags; Bit 0 = Enabled. Only count Bit 0, not Bit 1 (Online Capable).
                Dim flags As Byte = entryPtr(4)
                If (flags And 1) <> 0 Then
                    cpuCount = cpuCount + 1
                    Dim apicId As Byte = entryPtr(3)
                    Drivers.SerialUart.PrintF "[SMP] Core #%d | APIC ID: %d\r\n", cpuCount - 1, CType(UInt32, apicId)
                End If
            ElseIf entryType = 1 Then
                ' Type 1: I/O APIC - MMIO address at byte offset 4
                Dim ioapicPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, offset + 4)
                ioapicAddress = ioapicPtr(0)
            End If

            offset = offset + CType(UInt64, entryLen)
        Wend

        If cpuCount = 0 Then cpuCount = 1

        Drivers.SerialUart.PrintF "[ACPI] MADT: %d core(s), LAPIC @ 0x%x, IO-APIC @ 0x%x\r\n", _
            cpuCount, lapicAddress, ioapicAddress
    End Sub

    ''
    ' @brief Parse FADT for PM1a/b control block I/O ports and ACPI reset register.
    ' @param base Physical address of the FADT table.
    ''
    Private Unsafe Sub ParseFadt(ByVal base As UInt64)
        Dim hdr As Volatile Pointer To AcpiHeader = CPtr(Volatile Pointer To AcpiHeader, base)
        If Not VerifyChecksum(base, hdr.Length) Then
            Drivers.SerialUart.PrintF "[ACPI] Error: FADT checksum failure.\r\n"
            Exit Sub
        End If

        ' PM1a_CNT_BLK at FADT offset 64, PM1b_CNT_BLK at offset 68
        Dim pm1aPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, base + 64)
        pm1aControlBlock = pm1aPtr(0)
        Dim pm1bPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, base + 68)
        pm1bControlBlock = pm1bPtr(0)

        slpTypA = &H1400   ' Standard QEMU ACPI S5 SLP_TYPa

        ' ACPI 2.0+ Reset Register (FADT offset 116+4 = 120, value at 128)
        If hdr.Length >= 129 Then
            Dim rstPtr As Volatile Pointer To UInt32 = CPtr(Volatile Pointer To UInt32, base + 120)
            resetRegister = rstPtr(0)
            Dim valPtr As Volatile Pointer To Byte = CPtr(Volatile Pointer To Byte, base + 128)
            resetValue = valPtr(0)
            hasResetReg = (resetRegister <> 0)
        End If

        Drivers.SerialUart.PrintF "[ACPI] FADT: PM1a_CNT_BLK = 0x%x, ResetReg = 0x%x\r\n", _
            pm1aControlBlock, resetRegister
    End Sub

    ' -------------------------------------------------------------------------
    ' Public Accessors
    ' -------------------------------------------------------------------------

    Public Function GetCpuCount() As UInt32
        GetCpuCount = cpuCount
    End Function

    Public Function GetLapicBase() As UInt32
        GetLapicBase = lapicAddress
    End Function

    Public Function GetIoapicBase() As UInt32
        GetIoapicBase = ioapicAddress
    End Function

    Public Function GetPm1aControlBlock() As UInt32
        GetPm1aControlBlock = pm1aControlBlock
    End Function

    ''
    ' @brief ACPI S5 soft power-off via PM1a control register.
    ''
    Public Unsafe Sub PowerOff()
        If pm1aControlBlock <> 0 Then
            Drivers.SerialUart.PrintF "[ACPI] Sending S5 Power Off...\r\n"
            Dim val As UInt16 = slpTypA Or &H2000  ' SLP_EN bit 13
            Arch.X86_64.PortIO.OutW CType(UInt16, pm1aControlBlock), val
        End If
    End Sub

    ''
    ' @brief Hardware reboot via ACPI reset register or PS/2 keyboard controller fallback.
    ''
    Public Unsafe Sub Reboot()
        If hasResetReg And resetRegister <> 0 Then
            Arch.X86_64.PortIO.OutB CType(UInt16, resetRegister), resetValue
        End If
        Arch.X86_64.PortIO.OutB &H64, &HFE  ' PS/2 pulse CPU reset line
    End Sub

End Module
