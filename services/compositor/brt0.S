/*
 * Project: PROS Display Compositor Service
 * File: services/compositor/brt0.S
 * Description: Basic Runtime (BRT0) entrypoint for Ring 3 Display Compositor.
 */

.code64
.section .text._start
.global _start
.type _start, @function

_start:
    /* Align stack pointer to 16-byte boundary */
    andq $-16, %rsp
    xorq %rbp, %rbp

    /* argc = 0, argv = NULL */
    xorq %rdi, %rdi
    xorq %rsi, %rsi

    .extern user_main
    callq user_main

    /* Return value (%rax) -> exit code in %rdi */
    movq %rax, %rdi
    movq $0, %rax /* SYS_PROCESS_EXIT = 0 */
    syscall

1:  hlt
    jmp 1b

/* Freestanding stack check guard */
.section .data
.global __stack_chk_guard
.align 8
__stack_chk_guard:
    .quad 0x595e9fbd94fda766

.section .text
.global __stack_chk_fail
__stack_chk_fail:
    movq $1, %rdi
    movq $0, %rax
    syscall
1:  hlt
    jmp 1b

.global memset
.type memset, @function
memset:
    movq %rdi, %r8
    movzbl %sil, %eax
    movq %rdx, %rcx
    rep stosb
    movq %r8, %rax
    ret

.global memcpy
.type memcpy, @function
memcpy:
    movq %rdi, %r8
    movq %rdx, %rcx
    rep movsb
    movq %r8, %rax
    ret

.global strlen
.type strlen, @function
strlen:
    xorq %rax, %rax
1:
    cmpb $0, (%rdi, %rax)
    je 2f
    incq %rax
    jmp 1b
2:
    ret

