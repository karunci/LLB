/*
 * Project: PROS (Personal Research Operating System) / Low-Level Basic
 * File: lib/runtime/brt0.S
 * Description: Canonical Basic Runtime (BRT0) entry point, stack alignment, and canary stubs.
 */

.code64
.section .text.entry
.global _start
.type _start, @function

.weak user_main
.weak Main
.set Main, user_main

_start:
    /* 1. Clear Frame Pointer for clean stack backtrace boundary */
    xorq %rbp, %rbp

    /* 2. Retrieve argc and argv from stack per System V ABI */
    popq %rdi                  /* %rdi = argc */
    movq %rsp, %rsi            /* %rsi = argv */

    /* 3. Align stack pointer to 16 bytes prior to function call */
    andq $-16, %rsp

    /* 4. Invoke high-level application entry point */
    call Main

    /* 5. Exit application cleanly via SYS_PROCESS_EXIT (16)
     *    Pass return code in %rdi
     */
    movq %rax, %rdi
    movq $16, %rax             /* SYS_PROCESS_EXIT = 16 */
    syscall

    /* Linux SYS_exit (60) fallback for hosted qemu-x86_64 verification */
    movq $60, %rax             /* SYS_exit = 60 */
    syscall

    /* 6. Safety pause loop if exit syscall returns */
1:
    pause
    jmp 1b

.size _start, . - _start

/* ============================================================================
 * Stack Smashing Protector (SSP) Primitives
 * ============================================================================ */

.section .data
.align 8
.global __stack_chk_guard
.type __stack_chk_guard, @object
.size __stack_chk_guard, 8
__stack_chk_guard:
    .quad 0x595e9fbd94fda766

.section .text
.global __stack_chk_fail
.type __stack_chk_fail, @function
__stack_chk_fail:
    movq $255, %rdi            /* exit status code = 255 */
    movq $16, %rax             /* SYS_PROCESS_EXIT = 16 */
    syscall
1:
    pause
    jmp 1b

.size __stack_chk_fail, . - __stack_chk_fail
