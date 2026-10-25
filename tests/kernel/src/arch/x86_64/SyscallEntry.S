/*
 * Project: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * File: tests/kernel/src/arch/x86_64/SyscallEntry.S
 * Description: Hardened x86_64 syscall entry point with swapgs and System V ABI marshaling.
 */

.code64
.section .text

.global syscall_entry
.extern Sys_Syscall_Dispatch

.type syscall_entry, @function
syscall_entry:
    /* 1. Swap GS base to access Per-CPU GS Scratchpad */
    swapgs

    /* 2. Save User RSP into %gs:0 (CpuScratch.UserRsp) */
    movq %rsp, %gs:0

    /* 3. Load Per-CPU Kernel Stack Top into RSP from %gs:8 (CpuScratch.KernelStack) */
    movq %gs:8, %rsp

    /* 4. Construct Interrupt/Syscall Return Frame on Kernel Stack */
    pushq $0x1B                /* User SS Selector (0x18 | 3) */
    pushq %gs:0                /* Saved User RSP */
    pushq %r11                 /* Saved User RFLAGS */
    pushq $0x23                /* User CS Selector (0x20 | 3) */
    pushq %rcx                 /* Saved User RIP */
    pushq %rax                 /* Syscall Number [96(%rsp)] */

    /* 5. Preserve General Purpose Registers (Creates Stack Frame) */
    pushq %rdi                 /* User arg1 [88(%rsp)] */
    pushq %rsi                 /* User arg2 [80(%rsp)] */
    pushq %rdx                 /* User arg3 [72(%rsp)] */
    pushq %r10                 /* User arg4 [64(%rsp)] */
    pushq %r8                  /* [56(%rsp)] */
    pushq %r9                  /* [48(%rsp)] */
    pushq %rbx                 /* [40(%rsp)] */
    pushq %rbp                 /* [32(%rsp)] */
    pushq %r12                 /* [24(%rsp)] */
    pushq %r13                 /* [16(%rsp)] */
    pushq %r14                 /* [8(%rsp)] */
    pushq %r15                 /* [0(%rsp)] */

    /* 6. Marshal System V ABI Arguments to Sys_Syscall_Dispatch
     *    Sys_Syscall_Dispatch(sysNum, arg1, arg2, arg3, arg4)
     */
    movq 96(%rsp), %rdi        /* 1st Arg (%rdi) = Syscall Number */
    movq 88(%rsp), %rsi        /* 2nd Arg (%rsi) = User arg1 */
    movq 80(%rsp), %rdx        /* 3rd Arg (%rdx) = User arg2 */
    movq 72(%rsp), %rcx        /* 4th Arg (%rcx) = User arg3 */
    movq 64(%rsp), %r8         /* 5th Arg (%r8)  = User arg4 */

    cld
    call Sys_Syscall_Dispatch
    /* Return value from Sys_Syscall_Dispatch is in %rax */

    /* 7. Restore User Registers (preserving %rax as return value) */
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbp
    popq %rbx
    popq %r9
    popq %r8
    popq %r10
    popq %rdx
    popq %rsi
    popq %rdi

    /* Clean up Syscall Number slot */
    addq $8, %rsp

    /* 8. Pop Return Frame & Sanitize RFLAGS */
    popq %rcx                  /* Restore User RIP */
    addq $8, %rsp              /* Skip User CS */
    popq %r11                  /* Restore User RFLAGS */
    orq $0x200, %r11           /* Force Interrupt Flag (IF=1) enabled for Ring 3 */
    andq $~0x4000, %r11        /* Clear Nested Task flag (NT=0) */
    popq %rsp                  /* Restore User RSP */

    /* Restore GS Base back to User Mode */
    swapgs
    sysretq
