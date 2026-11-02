' Project Name: LibPROS / Low-Level Basic
' Filename: lib/pros/src/Pci.bas
' Summary: Userland PCI device discovery and BAR aperture mapping APIs.

Import Pros.Sys
Import Pros.Sys.RawSyscall

Namespace Pros.Driver

    <Packed>
    Public Structure PciBarInfo
        Public PhysBase   As UInt64
        Public SizeBytes  As UInt64
        Public IsIo       As Boolean
        Public IsPrefetch As Boolean
        Public Is64Bit    As Boolean
    End Structure

    <Packed>
    Public Structure PciDevice
        Public Bus         As Byte
        Public Slot        As Byte
        Public Func        As Byte
        Public Active      As Boolean
        Public VendorId    As UInt16
        Public DeviceId    As UInt16
        Public ClassCode   As Byte
        Public SubClass    As Byte
        Public ProgIf      As Byte
        Public HeaderType  As Byte
        Public IrqLine     As Byte
        Public BarCount    As Byte
        Public Bar0        As PciBarInfo
        Public Bar1        As PciBarInfo
        Public Bar2        As PciBarInfo
        Public Bar3        As PciBarInfo
        Public Bar4        As PciBarInfo
        Public Bar5        As PciBarInfo
    End Structure

    Public Module Pci

        ''
        ' @brief Query total number of detected PCI devices on system bus.
        ' @return Number of active devices in kernel table.
        ''
        Public Unsafe Function GetDeviceCount() As UInt32
            Dim count As UInt64 = Pros.Sys.RawSyscall.Call0(SYS_PCI_GET_DEVICE_COUNT)
            GetDeviceCount = CType(UInt32, count)
        End Function

        ''
        ' @brief Fetch PCI device descriptor by table index.
        ' @param index Table index (0..GetDeviceCount - 1).
        ' @param outDev Output PciDevice structure.
        ' @return True if device descriptor was copied successfully.
        ''
        Public Unsafe Function GetDevice(ByVal index As UInt32, ByRef outDev As PciDevice) As Boolean
            Dim devPtr As UInt64 = UInt64(AddressOf outDev)
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call2(SYS_PCI_GET_DEVICE, UInt64(index), devPtr)
            GetDevice = (res = 1)
        End Function

        ''
        ' @brief Map a PCI device's Base Address Register memory aperture into calling process.
        ' @param devIdx Device index in kernel table.
        ' @param barIdx BAR index (0..5).
        ' @param targetVaddr Desired virtual address in userspace.
        ' @param writeCombining True to configure Write-Combining PAT, False for Uncacheable.
        ' @return Pointer to mapped virtual address, or 0 on failure.
        ''
        Public Unsafe Function MapBar(ByVal devIdx As UInt32, ByVal barIdx As UInt32, ByVal targetVaddr As UInt64, ByVal writeCombining As Boolean) As Pointer To UInt32
            Dim wcFlag As UInt64 = 0
            If writeCombining Then wcFlag = 1
            Dim res As UInt64 = Pros.Sys.RawSyscall.Call4(SYS_PCI_MAP_BAR, UInt64(devIdx), UInt64(barIdx), targetVaddr, wcFlag)
            If res <> 0 Then
                MapBar = Pointer To UInt32(targetVaddr)
            Else
                MapBar = Nothing
            End If
        End Function

    End Module

End Namespace

