' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/drivers/ICharDevice.cls
' Summary: Abstract character output device interface.

Namespace Drivers

    Public Interface ICharDevice
        Unsafe Sub WriteChar(ByVal ch As Byte)
        Unsafe Sub WriteString(ByVal str As Pointer To Byte)
    End Interface

End Namespace
