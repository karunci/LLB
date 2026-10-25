/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: tests/user_app/brt0.S
 * Description: Basic Runtime (BRT0) entry point for freestanding Ring 3 user applications.
 */

.code64
.section .text.entry

.global _start
.extern user_main

_start:
    /* 1. Clear Frame Pointer for clean stack backtrace boundary */
    xorq %rbp, %rbp

    /* 2. Pop argc from user stack per System V ABI */
    popq %rdi                  /* %rdi = argc */
    movq %rsp, %rsi            /* %rsi = argv */

    /* 3. Align stack to 16 bytes (RSP % 16 == 0 before call) */
    andq $-16, %rsp

    /* 4. Invoke high-level application main: user_main(argc, argv) */
    call user_main

    /* 5. Exit application cleanly via native SYS_PROCESS_EXIT syscall (sysNum = 16)
     *    %rax holds return value from user_main; pass as arg1 in %rdi
     */
    movq %rax, %rdi            /* arg1 = exitCode */
    movq $16, %rax             /* SYS_PROCESS_EXIT = 16 */
    syscall

    /* 6. Safety pause loop if exit syscall returns */
1:
    pause
    jmp 1b

/* ============================================================================
 * Basic Runtime (BRT0) Freestanding Primitives
 * ============================================================================ */

.global __stack_chk_guard
.global __stack_chk_fail
.global memset
.global memcpy

.section .data
.align 8
__stack_chk_guard:
    .quad 0x595e9fbd94fda766

.section .text
.type __stack_chk_fail, @function
__stack_chk_fail:
    movq $255, %rdi
    movq $16, %rax             /* SYS_PROCESS_EXIT = 16 */
    syscall
1:
    pause
    jmp 1b

/* void *memset(void *dest, int c, size_t n) */
.type memset, @function
memset:
    movq %rdi, %r11            /* preserve dest */
    movzbq %sil, %rax          /* c byte */
    movq %rdx, %rcx            /* n count */
    cld
    rep stosb
    movq %r11, %rax            /* return dest */
    ret

/* void *memcpy(void *dest, const void *src, size_t n) */
.type memcpy, @function
memcpy:
    movq %rdi, %r11            /* preserve dest */
    movq %rdx, %rcx            /* n count */
    cld
    rep movsb
    movq %r11, %rax            /* return dest */
    ret
