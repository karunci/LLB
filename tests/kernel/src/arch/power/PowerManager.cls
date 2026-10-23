' Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
' Filename: tests/kernel/src/arch/power/PowerManager.cls
' Summary: System power management class providing soft reboot and ACPI S5 shutdown.
'          Ports PRK kernel_reboot() and ACPI power-off primitives.

Import Arch.Acpi
Use Drivers.SerialUart As Serial

Namespace Arch.Power

<Instancing(SingleUse)>
Public Class PowerManager

    ''
    ' @brief Soft reboot the system via ACPI reset register or PS/2 8042 controller pulse.
    '        Mirrors PRK kernel_reboot().
    ''
    Public Unsafe Sub Reboot()
        Serial.PrintF "[POWER] System reboot initiated...\r\n"
        Arch.Acpi.Reboot
    End Sub

    ''
    ' @brief Cleanly power off the machine using ACPI S5 sleep state.
    '        Mirrors PRK acpi_poweroff().
    ''
    Public Unsafe Sub PowerOff()
        Serial.PrintF "[POWER] System power-off initiated (ACPI S5)...\r\n"
        Arch.Acpi.PowerOff
    End Sub

End Class

End Namespace
