/*
 * Project: PRK-OS / Low-Level Basic (LLB)
 * File: apps/cli/coreutils/ls/user_linker.ld
 * Description: Linker script for userland application binaries loading at 0x40000000.
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

    . = ALIGN(4K);
    _end = .;
}

