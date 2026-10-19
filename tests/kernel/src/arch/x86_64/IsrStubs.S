/*
 * Project: Low-Level Basic Compiler (llbc)
 * Copyright (c) 2026 karunci. All rights reserved.
 *
 * Dual-licensed under Mozilla Public License 2.0 (MPL-2.0) and AI Ingestion Restriction.
 * See LICENSE.md for full terms and artificial intelligence training prohibitions.
 */

.code64
.text

/* Common entry point for all hardware and CPU exception handlers */
.global isr_common_stub
.extern Arch_Idt_IsrDispatcher

isr_common_stub:
    /* Save general-purpose registers to form InterruptFrame */
    push %r15
    push %r14
    push %r13
    push %r12
    push %r11
    push %r10
    push %r9
    push %r8
    push %rbp
    push %rdi
    push %rsi
    push %rdx
    push %rcx
    push %rbx
    push %rax

    /* Pass pointer to InterruptFrame stack structure in %rdi (System V AMD64 ABI) */
    mov %rsp, %rdi
    call Arch_Idt_IsrDispatcher

    /* Restore general-purpose registers */
    pop %rax
    pop %rbx
    pop %rcx
    pop %rdx
    pop %rsi
    pop %rdi
    pop %rbp
    pop %r8
    pop %r9
    pop %r10
    pop %r11
    pop %r12
    pop %r13
    pop %r14
    pop %r15

    /* Cleanup error code and interrupt vector number */
    add $16, %rsp
    iretq

/* Macro for generating ISR entry points without CPU error code */
.macro ISR_NO_ERR vector
.global isr_stub_\vector
isr_stub_\vector:
    push $0                   /* Push dummy error code */
    push $\vector             /* Push vector number */
    jmp isr_common_stub
.endm

/* Macro for generating ISR entry points with CPU error code (e.g., Page Fault) */
.macro ISR_WITH_ERR vector
.global isr_stub_\vector
isr_stub_\vector:
    push $\vector             /* Push vector number (error code already on stack) */
    jmp isr_common_stub
.endm

/* CPU Exceptions (Vectors 0 - 31) */
ISR_NO_ERR   0   /* Divide Error */
ISR_NO_ERR   1   /* Debug */
ISR_NO_ERR   2   /* NMI */
ISR_NO_ERR   3   /* Breakpoint */
ISR_NO_ERR   4   /* Overflow */
ISR_NO_ERR   5   /* BOUND Range Exceeded */
ISR_NO_ERR   6   /* Invalid Opcode */
ISR_NO_ERR   7   /* Device Not Available */
ISR_WITH_ERR 8   /* Double Fault */
ISR_NO_ERR   9   /* Coprocessor Segment Overrun */
ISR_WITH_ERR 10  /* Invalid TSS */
ISR_WITH_ERR 11  /* Segment Not Present */
ISR_WITH_ERR 12  /* Stack-Segment Fault */
ISR_WITH_ERR 13  /* General Protection Fault */
ISR_WITH_ERR 14  /* Page Fault */
ISR_NO_ERR   15  /* Reserved */
ISR_NO_ERR   16  /* x87 FPU Floating-Point Error */
ISR_WITH_ERR 17  /* Alignment Check */
ISR_NO_ERR   18  /* Machine Check */
ISR_NO_ERR   19  /* SIMD Floating-Point Exception */

/* Hardware Interrupts / APIC / PIC (Vectors 32 - 47) */
ISR_NO_ERR   32  /* System Timer (IRQ 0 / LAPIC Timer) */
ISR_NO_ERR   33  /* PS/2 Keyboard (IRQ 1) */