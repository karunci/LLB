' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: kernel/src/drivers/pci/PciBus.cls
' Summary: High-performance PCI bus driver, device enumeration, BAR size probing,
'          and command space configuration via legacy I/O ports 0xCF8/0xCFC.

Import Arch.X86_64.PortIO
Import Drivers.Pci
Use Drivers.SerialUart As Serial

Namespace Drivers.Pci

<Instancing(SingleUse)>
Public Class PciBus

    Private devices(32) As PciDevice
    Private deviceCount As UInt32 = 0

    ''
    ' @brief Build standard 32-bit PCI CONFIG_ADDRESS register value.
    ' @param bus Bus index (0..255).
    ' @param slot Slot/device index (0..31).
    ' @param func Function index (0..7).
    ' @param offset Register byte offset (0..255).
    ' @return 32-bit address formatted for I/O port 0xCF8.
    ''
    Public Function MakeAddress(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8) As UInt32
        Dim addr As UInt32 = PCI_ENABLE_BIT
        addr = addr Or (UInt32(bus) LShift 16)
        addr = addr Or (UInt32(slot) LShift 11)
        addr = addr Or (UInt32(func) LShift 8)
        addr = addr Or (UInt32(offset) And &HFC)
        MakeAddress = addr
    End Function

    ''
    ' @brief Read a 32-bit DWORD from PCI configuration space.
    ''
    Public Unsafe Function ReadDword(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8) As UInt32
        Dim addr As UInt32 = MakeAddress(bus, slot, func, offset)
        Arch.X86_64.PortIO.OutL PCI_CONFIG_ADDRESS, addr
        ReadDword = Arch.X86_64.PortIO.InL(PCI_CONFIG_DATA)
    End Function

    ''
    ' @brief Write a 32-bit DWORD to PCI configuration space.
    ''
    Public Unsafe Sub WriteDword(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8, ByVal val As UInt32)
        Dim addr As UInt32 = MakeAddress(bus, slot, func, offset)
        Arch.X86_64.PortIO.OutL PCI_CONFIG_ADDRESS, addr
        Arch.X86_64.PortIO.OutL PCI_CONFIG_DATA, val
    End Sub

    ''
    ' @brief Read a 16-bit WORD from PCI configuration space.
    ''
    Public Unsafe Function ReadWord(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8) As UInt16
        Dim dw As UInt32 = ReadDword(bus, slot, func, offset)
        Dim shift As UInt32 = (UInt32(offset) And 2) * 8
        ReadWord = UInt16((dw RShift shift) And &HFFFF)
    End Function

    ''
    ' @brief Write a 16-bit WORD to PCI configuration space.
    ''
    Public Unsafe Sub WriteWord(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8, ByVal val As UInt16)
        Dim dw As UInt32 = ReadDword(bus, slot, func, offset)
        Dim shift As UInt32 = (UInt32(offset) And 2) * 8
        Dim mask As UInt32 = Not (UInt32(&HFFFF) LShift shift)
        dw = (dw And mask) Or (UInt32(val) LShift shift)
        WriteDword bus, slot, func, offset, dw
    End Sub

    ''
    ' @brief Read an 8-bit BYTE from PCI configuration space.
    ''
    Public Unsafe Function ReadByte(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, ByVal offset As UInt8) As UInt8
        Dim dw As UInt32 = ReadDword(bus, slot, func, offset)
        Dim shift As UInt32 = (UInt32(offset) And 3) * 8
        ReadByte = UInt8((dw RShift shift) And &HFF)
    End Function

    ''
    ' @brief Enable Memory Space, I/O Space, and Bus Mastering on a PCI device.
    ''
    Public Unsafe Sub EnableDevice(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8)
        Dim cmd As UInt16 = ReadWord(bus, slot, func, PCI_REG_COMMAND)
        cmd = cmd Or PCI_CMD_IO_SPACE Or PCI_CMD_MEMORY_SPACE Or PCI_CMD_BUS_MASTER
        WriteWord bus, slot, func, PCI_REG_COMMAND, cmd
    End Sub

    ''
    ' @brief Probe a Base Address Register (BAR) to detect base address and memory size.
    ' @param bus Bus index.
    ' @param slot Slot index.
    ' @param func Function index.
    ' @param barIdx BAR index (0..5).
    ' @param outBar Output PciBarInfo structure.
    ' @return Number of BAR slots consumed (1 for 32-bit/IO, 2 for 64-bit).
    ''
    Public Unsafe Function ProbeBar(ByVal bus As UInt8, ByVal slot As UInt8, ByVal func As UInt8, _
                                   ByVal barIdx As UInt8, ByVal pBar As Pointer To PciBarInfo) As UInt8
        If pBar = 0 Then
            ProbeBar = 1
            Exit Function
        End If

        pBar.PhysBase = 0
        pBar.SizeBytes = 0
        pBar.IsIo = False
        pBar.IsPrefetch = False
        pBar.Is64Bit = False

        If barIdx > 5 Then
            ProbeBar = 1
            Exit Function
        End If

        Dim regOffset As UInt8 = PCI_REG_BAR0 + (barIdx * 4)
        Dim origBar As UInt32 = ReadDword(bus, slot, func, regOffset)

        ' Probe BAR size by writing all 1s
        WriteDword bus, slot, func, regOffset, &HFFFFFFFF
        Dim mask As UInt32 = ReadDword(bus, slot, func, regOffset)
        WriteDword bus, slot, func, regOffset, origBar

        If origBar <> 0 Or mask <> 0 Then
            Serial.PrintF "[PCI-BAR] [%02x:%02x.%d] BAR%d: orig=0x%08x, mask=0x%08x\r\n", bus, slot, func, UInt32(barIdx), origBar, mask
        End If

        If mask = 0 Or mask = &HFFFFFFFF Then
            ' Unimplemented BAR
            ProbeBar = 1
            Exit Function
        End If

        ' Bit 0: 1 = I/O Space, 0 = Memory Space
        If (mask And 1) <> 0 Then
            pBar.IsIo = True
            pBar.PhysBase = UInt64(origBar And &HFFFFFFFC)

            Dim sizeMask As UInt32 = (mask And &HFFFFFFFC)
            If sizeMask <> 0 Then
                pBar.SizeBytes = UInt64((Not sizeMask) + 1) And &HFFFF
            End If
            ProbeBar = 1
        Else
            pBar.IsIo = False
            Dim barType As UInt32 = (origBar RShift 1) And 3
            pBar.IsPrefetch = ((origBar RShift 3) And 1) <> 0

            If barType = 2 Then
                ' 64-bit Memory Space: consumes two 32-bit BAR registers
                pBar.Is64Bit = True
                Dim origBarHigh As UInt32 = 0
                If barIdx < 5 Then
                    origBarHigh = ReadDword(bus, slot, func, regOffset + 4)
                End If

                pBar.PhysBase = (UInt64(origBarHigh) LShift 32) Or UInt64(origBar And &HFFFFFFF0)

                Dim maskHigh As UInt32 = &HFFFFFFFF
                If barIdx < 5 Then
                    WriteDword bus, slot, func, regOffset + 4, &HFFFFFFFF
                    maskHigh = ReadDword(bus, slot, func, regOffset + 4)
                    WriteDword bus, slot, func, regOffset + 4, origBarHigh
                End If

                Dim fullMask As UInt64 = (UInt64(maskHigh) LShift 32) Or UInt64(mask And &HFFFFFFF0)
                If fullMask <> 0 Then
                    pBar.SizeBytes = (Not fullMask) + 1
                End If
                ProbeBar = 2
            Else
                ' 32-bit Memory Space
                pBar.Is64Bit = False
                pBar.PhysBase = UInt64(origBar And &HFFFFFFF0)

                Dim sizeMask2 As UInt32 = mask And &HFFFFFFF0
                If sizeMask2 <> 0 Then
                    pBar.SizeBytes = UInt64((Not sizeMask2) + 1)
                End If
                ProbeBar = 1
            End If
        End If
    End Function

    ''
    ' @brief Scan PCI configuration space and populate kernel device table.
    ''
    Public Unsafe Sub ScanBus()
        Serial.PrintF "[PCI] Scanning PCI Configuration Space (Ports 0xCF8/0xCFC)...\r\n"
        deviceCount = 0

        Dim b As UInt32 = 0
        While b < 16 ' Scan first 16 PCI buses (covers all standard QEMU/VirtualBox/PC topology)
            Dim s As UInt32 = 0
            While s < 32
                Dim vId0 As UInt16 = ReadWord(UInt8(b), UInt8(s), 0, PCI_REG_VENDOR_ID)
                If vId0 <> &HFFFF Then
                    Dim hType As UInt8 = ReadByte(UInt8(b), UInt8(s), 0, PCI_REG_HEADER_TYPE)
                    Dim maxFunc As UInt32 = 0
                    If (hType And &H80) <> 0 Then maxFunc = 7

                    Dim f As UInt32 = 0
                    While f <= maxFunc
                        Dim vId As UInt16 = ReadWord(UInt8(b), UInt8(s), UInt8(f), PCI_REG_VENDOR_ID)
                        If vId <> &HFFFF And deviceCount < MAX_PCI_DEVICES Then
                            Dim dId As UInt16 = ReadWord(UInt8(b), UInt8(s), UInt8(f), PCI_REG_DEVICE_ID)
                            Dim classCode As UInt8 = ReadByte(UInt8(b), UInt8(s), UInt8(f), PCI_REG_CLASS)
                            Dim subClass As UInt8 = ReadByte(UInt8(b), UInt8(s), UInt8(f), PCI_REG_SUBCLASS)
                            Dim progIf As UInt8 = ReadByte(UInt8(b), UInt8(s), UInt8(f), PCI_REG_PROG_IF)
                            Dim irqLine As UInt8 = ReadByte(UInt8(b), UInt8(s), UInt8(f), PCI_REG_INTERRUPT_LINE)

                            Dim devPtr As Pointer To PciDevice = AddressOf devices(deviceCount)
                            devPtr.Bus = UInt8(b)
                            devPtr.Slot = UInt8(s)
                            devPtr.Func = UInt8(f)
                            devPtr.Active = True
                            devPtr.VendorId = vId
                            devPtr.DeviceId = dId
                            devPtr.ClassCode = classCode
                            devPtr.SubClass = subClass
                            devPtr.ProgIf = progIf
                            devPtr.HeaderType = hType
                            devPtr.IrqLine = irqLine

                            ' Probe standard Base Address Registers (BAR0..BAR5)
                            Dim bIdx As UInt8 = 0
                            While bIdx < 6
                                Dim consumed As UInt8 = 1
                                If bIdx = 0 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 0, AddressOf devPtr.Bar0)
                                If bIdx = 1 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 1, AddressOf devPtr.Bar1)
                                If bIdx = 2 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 2, AddressOf devPtr.Bar2)
                                If bIdx = 3 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 3, AddressOf devPtr.Bar3)
                                If bIdx = 4 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 4, AddressOf devPtr.Bar4)
                                If bIdx = 5 Then consumed = ProbeBar(UInt8(b), UInt8(s), UInt8(f), 5, AddressOf devPtr.Bar5)
                                bIdx = bIdx + consumed
                            Wend
                            devPtr.BarCount = bIdx

                            Serial.PrintF "[PCI] [%02x:%02x.%d] ID: %04x:%04x | Class: 0x%02x (Sub: 0x%02x, IF: 0x%02x) | IRQ: %d\r\n", _
                                          b, s, f, UInt32(vId), UInt32(dId), UInt32(classCode), UInt32(subClass), UInt32(progIf), UInt32(irqLine)

                            If classCode = PCI_CLASS_DISPLAY Then
                                EnableDevice UInt8(b), UInt8(s), UInt8(f)
                                Serial.PrintF "[PCI]   >>> Display Controller Detected! BAR0: 0x%lx (Size: %u KB, IO: %d)\r\n", _
                                              devPtr.Bar0.PhysBase, CType(UInt32, devPtr.Bar0.SizeBytes / 1024), devPtr.Bar0.IsIo
                                If devPtr.Bar1.PhysBase <> 0 Then
                                    Serial.PrintF "[PCI]   >>> Display BAR1: 0x%lx (Size: %u KB, IO: %d)\r\n", _
                                                  devPtr.Bar1.PhysBase, CType(UInt32, devPtr.Bar1.SizeBytes / 1024), devPtr.Bar1.IsIo
                                End If
                                If vId = PCI_VENDOR_VMWARE And dId = PCI_DEVICE_VMWARE_SVGA2 Then
                                    Serial.PrintF "[PCI]   >>> VMware SVGA-II Hardware Accelerated Controller Active!\r\n"
                                ElseIf vId = PCI_VENDOR_VIRTIO And dId = PCI_DEVICE_VIRTIO_GPU Then
                                    Serial.PrintF "[PCI]   >>> VirtIO-GPU Hardware Accelerated Controller Active!\r\n"
                                ElseIf vId = PCI_VENDOR_INTEL Then
                                    Serial.PrintF "[PCI]   >>> Intel HD/UHD Integrated Graphics Controller Active!\r\n"
                                End If
                            ElseIf classCode = PCI_CLASS_MULTIMEDIA Then
                                EnableDevice UInt8(b), UInt8(s), UInt8(f)
                                Serial.PrintF "[PCI]   >>> Multimedia/Audio Controller Detected! BAR0: 0x%lx (Size: %u KB, IO: %d)\r\n", _
                                              devPtr.Bar0.PhysBase, CType(UInt32, devPtr.Bar0.SizeBytes / 1024), devPtr.Bar0.IsIo
                                If vId = PCI_VENDOR_INTEL And dId = PCI_DEVICE_INTEL_HDA Then
                                    Serial.PrintF "[PCI]   >>> Intel High Definition Audio (ICH6 HDA) Controller Active!\r\n"
                                End If
                            End If

                            deviceCount = deviceCount + 1
                        End If
                        f = f + 1
                    Wend
                End If
                s = s + 1
            Wend
            b = b + 1
        Wend

        Serial.PrintF "[PCI] Bus scan completed. %u active PCI device(s) registered.\r\n", deviceCount
    End Sub

    ''
    ' @brief Get the count of detected PCI devices.
    ''
    Public Function GetDeviceCount() As UInt32
        GetDeviceCount = deviceCount
    End Function

    ''
    ' @brief Get pointer to a detected PCI device descriptor.
    ''
    Public Unsafe Function GetDevice(ByVal index As UInt32) As Pointer To PciDevice
        If index < deviceCount Then
            GetDevice = AddressOf devices(index)
        Else
            GetDevice = 0
        End If
    End Function

    ''
    ' @brief Find a PCI device by Vendor and Device ID.
    ''
    Public Unsafe Function FindDevice(ByVal vendorId As UInt16, ByVal deviceId As UInt16) As Pointer To PciDevice
        Dim i As UInt32 = 0
        While i < deviceCount
            If devices(i).VendorId = vendorId And devices(i).DeviceId = deviceId Then
                FindDevice = AddressOf devices(i)
                Exit Function
            End If
            i = i + 1
        Wend
        FindDevice = 0
    End Function

    ''
    ' @brief Find first display controller on PCI bus.
    ''
    Public Unsafe Function FindDisplayDevice() As Pointer To PciDevice
        Dim i As UInt32 = 0
        While i < deviceCount
            If devices(i).ClassCode = PCI_CLASS_DISPLAY Then
                FindDisplayDevice = AddressOf devices(i)
                Exit Function
            End If
            i = i + 1
        Wend
        FindDisplayDevice = 0
    End Function

End Class

End Namespace
