/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: tests/kernel/src/arch/x86_64/SwitchContext.S
 * Description: Context switch routine and thread bootstrap trampoline.
 *              Ports PRK kernel/switch.S and thread_start_trampoline.
 */

.code64
.section .text

/*
 * void switch_context(uint64_t *old_rsp, uint64_t new_rsp, uint64_t new_cr3, spinlock_t *lock);
 * System V AMD64 ABI:
 *   %rdi = old_rsp pointer (uint64_t *)
 *   %rsi = new_rsp (uint64_t)
 *   %rdx = new_cr3 (uint64_t)
 *   %rcx = lock pointer (uint8_t *)
 */
.global switch_context
.type switch_context, @function
switch_context:
    /* 1. Save Callee-Saved Registers */
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    /* 2. Atomically store old stack pointer */
    movq %rsp, (%rdi)

    /* 3. Load new stack pointer and CR3 (conditional reload avoids TLB flushes) */
    movq %rsi, %rsp
    movq %cr3, %rax
    cmpq %rdx, %rax
    je 1f
    movq %rdx, %cr3
1:

    /* 4. Release Runqueue Lock ONLY AFTER stack pointer is securely saved */
    testq %rcx, %rcx
    jz .skip_lock_release
    movb $0, (%rcx)

.skip_lock_release:
    /* 5. Restore Callee-Saved Registers */
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    ret

/*
 * thread_start_trampoline
 * Popped by switch_context ret for brand new threads.
 * Restores 15 general purpose registers, skips vector and error,
 * applies swapgs if transitioning to Ring 3, and iretq.
 */
.global thread_start_trampoline
.type thread_start_trampoline, @function
thread_start_trampoline:
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %r11
    pop %r10
    pop %r9
    pop %r8
    pop %rbp
    pop %rdi
    pop %rsi
    pop %rdx
    pop %rcx
    pop %rbx
    /* Check target CS RPL at [RSP + 32] while %rax is still safely stacked */
    testb $3, 32(%rsp)
    jz 1f
    swapgs                   /* Switch GS base to user */
    mov $0x1B, %ax           /* User data selector: 0x18 | RPL 3 */
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    pop %rax                 /* Restore genuine user %rax */
    add $16, %rsp            /* Skip dummy Vector and Error Code slots */
    iretq
1:
    mov $0x10, %ax           /* Kernel data selector: 0x10 | RPL 0 */
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    pop %rax                 /* Restore genuine kernel %rax */
    add $16, %rsp            /* Skip dummy Vector and Error Code slots */
    iretq


