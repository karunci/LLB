/*
 * Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * Filename: tests/kernel/linker.ld
 * Summary: Bare-metal x86_64 linker script positioning Multiboot header and kernel code.
 */

ENTRY(_start)

SECTIONS
{
    /* Load Kernel at physical memory address 1MB */
    . = 1M;

    .text : ALIGN(4K)
    {
        /* Ensure Multiboot header is placed first */
        KEEP(*(.multiboot_header))
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