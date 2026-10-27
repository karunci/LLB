/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: services/wm/brt0.S
 * Description: Basic Runtime (BRT0) entry point for wm.
 */

.code64
.section .text.entry

.global _start
.extern user_main

_start:
    xorq %rbp, %rbp
    popq %rdi
    movq %rsp, %rsi
    andq $-16, %rsp
    call user_main
    movq %rax, %rdi
    movq $16, %rax             /* SYS_PROCESS_EXIT = 16 */
    syscall
1:
    pause
    jmp 1b

.global __stack_chk_guard
.global __stack_chk_fail
.global memset
.global memcpy
.global strlen

.section .data
.align 8
__stack_chk_guard:
    .quad 0x595e9fbd94fda766

.section .text
.type __stack_chk_fail, @function
__stack_chk_fail:
    movq $255, %rdi
    movq $16, %rax
    syscall
1:
    pause
    jmp 1b

.type memset, @function
memset:
    cld
    movq %rdi, %r8
    movzbl %sil, %eax
    movabsq $0x0101010101010101, %r9
    imulq %r9, %rax
    movq %rdx, %rcx
    shrq $3, %rcx
    rep stosq
    movq %rdx, %rcx
    andq $7, %rcx
    rep stosb
    movq %r8, %rax
    ret

.type memcpy, @function
memcpy:
    cld
    movq %rdi, %r8
    movq %rdx, %rcx
    shrq $3, %rcx
    rep movsq
    movq %rdx, %rcx
    andq $7, %rcx
    rep movsb
    movq %r8, %rax
    ret

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
