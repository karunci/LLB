/*
 * Project: PRK / Low-Level Basic
 * File: tests/kernel/src/arch/x86_64/boot_mb1.S
 * Description: Dedicated Multiboot 1 header for Legacy BIOS / CSM boot + bootstrap code.
 */

.code32
.section .text._start
.align 4

/* ============================================================================
 * MULTIBOOT 1 HEADER (For Legacy BIOS / CSM / QEMU -kernel direct boot)
 * ============================================================================ */
#define MULTIBOOT1_HEADER_MAGIC      0x1BADB002
#define MULTIBOOT1_HEADER_FLAGS      0x00000007 /* ALIGN + MEMINFO + VIDEO (Native ELF loading) */

.align 4
multiboot1_header:
    .long MULTIBOOT1_HEADER_MAGIC
    .long MULTIBOOT1_HEADER_FLAGS
    .long -(MULTIBOOT1_HEADER_MAGIC + MULTIBOOT1_HEADER_FLAGS)
    /* 5 address dwords at offsets 12-28 so video fields reside at struct offset 32 per GRUB struct multiboot_header */
    .long 0     /* header_addr */
    .long 0     /* load_addr */
    .long 0     /* load_end_addr */
    .long 0     /* bss_end_addr */
    .long 0     /* entry_addr */
    /* Video mode fields at struct offset 32 */
    .long 0     /* mode_type: 0 = linear graphics */
    .long 1024  /* width */
    .long 768   /* height */
    .long 32    /* depth */

/* ============================================================================
 * 32-BIT PROTECTED MODE ENTRY POINT
 * ============================================================================ */
.code32
.global _start
.type _start, @function

_start:
    /* Disable Interrupts and Setup Temporary 32-bit Stack */
    cli
    cld

    /* Setup Temporary 32-bit Stack */
    mov $stack_top, %esp

    /* Push 32-bit Multiboot arguments safely on stack */
    push %ebx
    push %eax

    /* 1. Setup Early Paging structures (Identity maps 0 - 16GB physical RAM, preserves L3[2] for heap) */
    call setup_page_tables
    call enable_paging

    /* 2. Load 64-bit Global Descriptor Table (GDT) via 6-byte 32-bit descriptor pointer */
    mov $gdt64_pointer_32, %eax
    lgdt (%eax)

    /* 3. Pop Multiboot arguments cleanly into %edi (magic) and %esi (mbi pointer) */
    pop %edi
    pop %esi

    /* 4. Canonical 64-bit far return into long_mode_entry */
    push $0x08
    push $long_mode_entry
    lret

/* ============================================================================
 * EARLY BSS BOOTSTACK & PAGE TABLES (IDENTITY MAPPED FULL 16GB)
 * ============================================================================ */
.section .bss

.align 4096
page_table_l4:
    .skip 4096
page_table_l3:
    .skip 4096
page_table_l2:
    .skip 65536 /* 16 x 4096 = 64KB for 16GB identity space using 2MB pages */

.align 16
stack_bottom:
    .skip 16384 /* 16 KiB Kernel Boot Stack */
stack_top:

.section .text

/* Setup 4-level Page Tables (Full 0 - 16GB Identity Mapped, except L3[2] for VMM Heap) */
setup_page_tables:
    /* Zero out all early boot page tables (72KB: L4 (4KB), L3 (4KB), and 16x L2 tables (64KB)) */
    mov $page_table_l4, %edi
    xor %eax, %eax
    mov $18432, %ecx      /* 18432 dwords = 73728 bytes (72KB) */
    cld
    rep stosl

    /* Map L4[0] -> L3 */
    mov $page_table_l3, %eax
    or $0x3, %eax /* Present + Writable */
    mov $page_table_l4, %ebx
    mov %eax, (%ebx)
    movl $0, 4(%ebx)

    /* Map L3[0..15] -> page_table_l2 (each table is 4096 bytes)
     * CRITICAL INVARIANT: L3[2] (2GB..3GB: 0x80000000 - 0xC0000000) MUST BE LEFT 0 (UNMAPPED)!
     * VMM and KernelHeap dynamically manage 4KB page allocations in this 1GB range (heap at 0x81000000).
     */
    mov $page_table_l2, %eax
    or $0x3, %eax
    mov $page_table_l3, %ebx
    xor %ecx, %ecx        /* ecx = index 0..15 */
1:
    cmpl $2, %ecx
    je 2f                 /* Skip L3[2], leave it 0 */
    mov %eax, (%ebx)
    movl $0, 4(%ebx)
2:
    add $4096, %eax
    add $8, %ebx
    inc %ecx
    cmp $16, %ecx
    jne 1b

    /* Identity map 0 - 16GB across L2 tables (16 tables * 512 entries = 8192 entries)
     * Skip Table 2 (entries 1024..1535, corresponding to 2GB..3GB), leaving them zero.
     * Use %edx to hold the upper 32 bits of physical address to avoid 32-bit overflow at 4GB!
     */
    mov $page_table_l2, %ebx
    xor %ecx, %ecx        /* ecx = entry index 0..8191 */
    mov $0x83, %eax       /* Physical base 0 | Present | Writable | HugePage (2MB) */
    xor %edx, %edx        /* Physical base high 32 bits = 0 */
3:
    cmpl $1024, %ecx
    jb 4f                 /* Entries 0..1023 (0..2GB): map normally */
    cmpl $1536, %ecx
    jb 5f                 /* Entries 1024..1535 (2GB..3GB): SKIP (leave 0 for heap) */
4:
    mov %eax, (%ebx)
    mov %edx, 4(%ebx)
5:
    add $0x200000, %eax   /* Add 2MB to lower 32 bits */
    adcl $0, %edx         /* Add carry to upper 32 bits (correctly handles >= 4GB!) */
    add $8, %ebx          /* Advance to next 8-byte entry */
    inc %ecx
    cmp $8192, %ecx
    jne 3b
    ret

/* Enable PAE, SSE, and Long Mode in CR4/CR0/EFER */
enable_paging:
    /* Pass L4 Page Table Address to CR3 */
    mov $page_table_l4, %eax
    mov %eax, %cr3

    /* Enable PAE (Physical Address Extension), OSFXSR, and OSXMMEXCPT in CR4 */
    mov %cr4, %eax
    or $((1 << 5) | (1 << 9) | (1 << 10)), %eax
    mov %eax, %cr4

    /* Set Long Mode Enable (LME) bit in EFER MSR (0xC0000080) */
    mov $0xC0000080, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr

    /* Enable Paging in CR0, clear EM (bit 2), set MP (bit 1) */
    mov %cr0, %eax
    and $~(1 << 2), %eax
    or $((1 << 1) | (1 << 31)), %eax
    mov %eax, %cr0
    ret

/* ============================================================================
 * 64-BIT LONG MODE EXECUTION REALM
 * ============================================================================ */
.code64
long_mode_entry:
    /* Reset Data Segment Registers for 64-bit flat mode */
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    /* Ensure 16-byte Stack Alignment for System V AMD64 ABI Call Rules */
    mov $stack_top, %rsp

    /* Zero-extend 32-bit Multiboot arguments to 64-bit registers */
    mov %edi, %edi
    mov %esi, %esi

    /* Call LLB Kernel Entrypoint generated by llbc */
    .extern KernelEntry
    call KernelEntry

    /* Infinite Halt Loop if Kernel Returns */
1:  cli
    hlt
    jmp 1b

/* ============================================================================
 * 64-BIT GLOBAL DESCRIPTOR TABLE (GDT)
 * ============================================================================ */
.section .rodata
.align 8
gdt64:
    .quad 0 /* Null Descriptor */
    .quad (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53) /* 0x08: Kernel Code (Executable/Readable/64-bit) */
    .quad (1 << 41) | (1 << 44) | (1 << 47)             /* 0x10: Kernel Data (Writable) */
gdt64_end:

gdt64_pointer_32:
    .word gdt64_end - gdt64 - 1
    .long gdt64

gdt64_pointer:
    .word gdt64_end - gdt64 - 1
    .quad gdt64

/* ============================================================================
 * STACK PROTECTOR STUBS (Bare-metal Freestanding ABI)
 * ============================================================================ */
.section .data
.global __stack_chk_guard
.align 8
__stack_chk_guard:
    .quad 0x595e9fbd94fda766

.section .text
.global __stack_chk_fail
__stack_chk_fail:
    cli
1:  hlt
    jmp 1b

.global abort
abort:
    cli
1:  hlt
    jmp 1b

.global dprintf
dprintf:
    ret

/* ============================================================================
 * FREESTANDING RUNTIME BUILTINS (Required by LLVM Optimization Passes)
 * ============================================================================ */
.global memset
.type memset, @function
memset:
    /* System V AMD64 ABI:
     * %rdi: dest pointer
     * %rsi: fill byte (int)
     * %rdx: count (size_t)
     * Returns: %rax = dest pointer
     */
    movq %rdi, %rax       /* Save dest for return value */
    movq %rdx, %rcx       /* Count into rcx for rep stosb */
    movb %sil, %al        /* Byte value */
    rep stosb
    movq %rdi, %rax       /* Restore dest return pointer */
    retq

.global memcpy
.type memcpy, @function
memcpy:
    /* %rdi: dest pointer
     * %rsi: src pointer
     * %rdx: count (size_t)
     * Returns: %rax = dest pointer
     */
    movq %rdi, %rax       /* Save dest for return value */
    movq %rdx, %rcx       /* Count into rcx for rep movsb */
    rep movsb
    retq

.global memmove
.type memmove, @function
memmove:
    /* %rdi: dest pointer, %rsi: src pointer, %rdx: count */
    movq %rdi, %rax
    testq %rdx, %rdx
    jz 2f
    cmpq %rsi, %rdi
    jbe 1f                /* dest <= src: copy forward */
    /* Dest > src: copy backward to prevent overlapping corruption */
    leaq -1(%rdi,%rdx), %rdi
    leaq -1(%rsi,%rdx), %rsi
    movq %rdx, %rcx
    std                   /* Set direction flag for decrement */
    rep movsb
    cld                   /* Restore direction flag */
    retq
1:
    movq %rdx, %rcx
    rep movsb
2:
    retq

.global memcmp
.type memcmp, @function
memcmp:
    /* %rdi: s1, %rsi: s2, %rdx: count */
    xorl %eax, %eax
    testq %rdx, %rdx
    jz 2f
1:
    movzbl (%rdi), %eax
    movzbl (%rsi), %ecx
    subl %ecx, %eax
    jnz 2f
    incq %rdi
    incq %rsi
    decq %rdx
    jnz 1b
2:
    retq

/* ============================================================================
 * SMP AP STARTUP TRAMPOLINE (16-bit Real Mode -> 64-bit Long Mode)
 * Ported from PRK kernel/boot.S (smp_trampoline_start..smp_trampoline_end).
 * BSP copies this blob to physical 0x8000, patches smp_cr3_slot with the
 * current kernel CR3, then sends INIT-SIPI-SIPI. The AP climbs to 64-bit
 * long mode and calls ap_main (Arch.Smp.ApMain).
 * ============================================================================ */
.section .text
.global smp_trampoline_start
.global smp_trampoline_end
.global smp_cr3_slot
.global smp_stack_slot

smp_trampoline_start:
    .code16
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss

    data32 lgdt (ap_gdt_desc - smp_trampoline_start + 0x8000)

    movl %cr0, %eax
    orl $1, %eax
    movl %eax, %cr0

    ljmpl $0x08, $(ap_protected_mode - smp_trampoline_start + 0x8000)

.code32
ap_protected_mode:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    /* Enable PAE (0x20), OSFXSR (0x200), and OSXMMEXCPT (0x400) for SSE */
    movl %cr4, %eax
    orl $0x620, %eax
    movl %eax, %cr4

    movl (smp_cr3_slot - smp_trampoline_start + 0x8000), %eax
    movl %eax, %cr3

    movl $0xC0000080, %ecx
    rdmsr
    orl $0x0100, %eax
    wrmsr

    movl %cr0, %eax
    orl $0x80000001, %eax
    movl %eax, %cr0

    lgdt (ap_gdt64_desc - smp_trampoline_start + 0x8000)

    .byte 0xea
    .long (ap_long_mode - smp_trampoline_start + 0x8000)
    .word 0x08

.code64
ap_long_mode:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss

    /* Load the AP stack allocated by BSP in Smp.InitCores */
    movq (smp_stack_slot - smp_trampoline_start + 0x8000), %rsp

    /* Jump to LLB Arch.Smp.ApMain */
    movabs $ap_main, %rax
    callq *%rax

.ap_hang:
    cli
    hlt
    jmp .ap_hang

/* --- BSP<->AP Communication Slots (patched at runtime) --- */
.align 8
smp_cr3_slot:   .long 0
smp_stack_slot: .quad 0

/* --- Temporary AP Transition GDTs (32-bit and 64-bit) --- */
.align 8
ap_gdt:
    .quad 0
    .quad 0x00cf9a000000ffff   /* 32-bit code */
    .quad 0x00cf92000000ffff   /* 32-bit data */
ap_gdt_desc:
    .word (. - ap_gdt - 1)
    .long (ap_gdt - smp_trampoline_start + 0x8000)

.align 8
ap_gdt64:
    .quad 0
    .quad 0x00af9a000000ffff   /* 64-bit code */
    .quad 0x00cf92000000ffff   /* 64-bit data */
ap_gdt64_desc:
    .word (. - ap_gdt64 - 1)
    .long (ap_gdt64 - smp_trampoline_start + 0x8000)

smp_trampoline_end:

/* ap_main symbol -> Arch_Smp_ApMain emitted by llbc */
.extern Arch_Smp_ApMain
.global ap_main
ap_main:
    jmp Arch_Smp_ApMain
