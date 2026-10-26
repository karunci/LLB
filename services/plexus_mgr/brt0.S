/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: services/plexus_mgr/brt0.S
 * Description: Basic Runtime (BRT0) entry point for plexus_mgr.
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
    movq %rdi, %r8
    movzbl %sil, %eax
    movq %rdx, %rcx
    rep stosb
    movq %r8, %rax
    ret

.type memcpy, @function
memcpy:
    movq %rdi, %r8
    movq %rdx, %rcx
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
