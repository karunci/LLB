/*
 * Project: Personal Research Operating System / Low-Level Basic
 * File: drivers/disp/svga/user_linker.ld
 * Description: Linker script for SVGA driver daemon loading at 0x40000000.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x40000000;

    .text : ALIGN(4K) {
        *(.text.entry)
        *(.text*)
    }

    .rodata : ALIGN(4K) {
        *(.rodata*)
    }

    .data : ALIGN(4K) {
        *(.data*)
    }

    .bss : ALIGN(4K) {
        *(COMMON)
        *(.bss*)
    }

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame)
        *(.note*)
    }
}

