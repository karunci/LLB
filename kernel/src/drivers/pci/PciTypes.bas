' Project Name: Personal Research Operating System / Low-Level Basic
' Filename: kernel/src/drivers/pci/PciTypes.bas
' Summary: PCI configuration space constants, register offsets, class codes, and device descriptors.

Namespace Drivers.Pci

    ' PCI Configuration Space I/O Ports
    Public Const PCI_CONFIG_ADDRESS    As UInt16 = &H0CF8
    Public Const PCI_CONFIG_DATA       As UInt16 = &H0CFC
    Public Const PCI_ENABLE_BIT        As UInt32 = &H80000000

    ' Standard Configuration Register Byte Offsets
    Public Const PCI_REG_VENDOR_ID     As UInt8 = &H00
    Public Const PCI_REG_DEVICE_ID     As UInt8 = &H02
    Public Const PCI_REG_COMMAND       As UInt8 = &H04
    Public Const PCI_REG_STATUS        As UInt8 = &H06
    Public Const PCI_REG_REVISION_ID   As UInt8 = &H08
    Public Const PCI_REG_PROG_IF       As UInt8 = &H09
    Public Const PCI_REG_SUBCLASS      As UInt8 = &H0A
    Public Const PCI_REG_CLASS         As UInt8 = &H0B
    Public Const PCI_REG_CACHE_LINE    As UInt8 = &H0C
    Public Const PCI_REG_LATENCY_TIMER As UInt8 = &H0D
    Public Const PCI_REG_HEADER_TYPE   As UInt8 = &H0E
    Public Const PCI_REG_BIST          As UInt8 = &H0F
    Public Const PCI_REG_BAR0          As UInt8 = &H10
    Public Const PCI_REG_BAR1          As UInt8 = &H14
    Public Const PCI_REG_BAR2          As UInt8 = &H18
    Public Const PCI_REG_BAR3          As UInt8 = &H1C
    Public Const PCI_REG_BAR4          As UInt8 = &H20
    Public Const PCI_REG_BAR5          As UInt8 = &H24
    Public Const PCI_REG_INTERRUPT_LINE As UInt8 = &H3C
    Public Const PCI_REG_INTERRUPT_PIN As UInt8 = &H3D

    ' Command Register Bits
    Public Const PCI_CMD_IO_SPACE      As UInt16 = &H0001
    Public Const PCI_CMD_MEMORY_SPACE  As UInt16 = &H0002
    Public Const PCI_CMD_BUS_MASTER    As UInt16 = &H0004

    ' Base Class Codes
    Public Const PCI_CLASS_STORAGE     As UInt8 = &H01
    Public Const PCI_CLASS_NETWORK     As UInt8 = &H02
    Public Const PCI_CLASS_DISPLAY     As UInt8 = &H03
    Public Const PCI_CLASS_MULTIMEDIA  As UInt8 = &H04
    Public Const PCI_CLASS_BRIDGE      As UInt8 = &H06

    ' Multimedia Subclass Codes
    Public Const PCI_SUBCLASS_AUDIO_OTHER As UInt8 = &H01
    Public Const PCI_SUBCLASS_AUDIO_HDA   As UInt8 = &H03

    ' Display Subclass Codes
    Public Const PCI_SUBCLASS_VGA      As UInt8 = &H00
    Public Const PCI_SUBCLASS_OTHER    As UInt8 = &H80

    ' Known Audio Device IDs
    Public Const PCI_DEVICE_INTEL_HDA    As UInt16 = &H2668

    ' Known Display Vendor / Device IDs
    Public Const PCI_VENDOR_VMWARE       As UInt16 = &H15AD
    Public Const PCI_DEVICE_VMWARE_SVGA2 As UInt16 = &H0405

    Public Const PCI_VENDOR_VIRTIO       As UInt16 = &H1AF4
    Public Const PCI_DEVICE_VIRTIO_GPU   As UInt16 = &H1050

    Public Const PCI_VENDOR_INTEL        As UInt16 = &H8086
    Public Const PCI_VENDOR_QEMU_STDVGA  As UInt16 = &H1234
    Public Const PCI_DEVICE_QEMU_STDVGA  As UInt16 = &H1111

    ' Maximum tracked PCI devices in kernel table
    Public Const MAX_PCI_DEVICES       As UInt32 = 32

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
        Public Bus         As UInt8
        Public Slot        As UInt8
        Public Func        As UInt8
        Public Active      As Boolean
        Public VendorId    As UInt16
        Public DeviceId    As UInt16
        Public ClassCode   As UInt8
        Public SubClass    As UInt8
        Public ProgIf      As UInt8
        Public HeaderType  As UInt8
        Public IrqLine     As UInt8
        Public BarCount    As UInt8
        Public Bar0        As PciBarInfo
        Public Bar1        As PciBarInfo
        Public Bar2        As PciBarInfo
        Public Bar3        As PciBarInfo
        Public Bar4        As PciBarInfo
        Public Bar5        As PciBarInfo
    End Structure

End Namespace

