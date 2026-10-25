/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: tests/user_app/user_linker.ld
 * Description: Linker script for user applications loading at 0x400000.
 */

ENTRY(_start)

SECTIONS
{
    /* Load user binaries at distinct lower-half virtual address 0x40000000 (1GB) */
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
        *(.note*)
        *(.eh_frame)
    }
}
