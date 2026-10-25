/*
 * Project: PROS Display Compositor Service
 * File: services/compositor/user_linker.ld
 * Description: Bare-metal Ring 3 linker script placing executable code at 0x40000000.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x40000000;

    .text : ALIGN(4K)
    {
        *(.text._start)
        *(.text*)
    }

    .rodata : ALIGN(4K)
    {
        *(.rodata*)
    }

    .data : ALIGN(4K)
    {
        *(.data*)
    }

    .bss : ALIGN(4K)
    {
        *(COMMON)
        *(.bss*)
    }
}
