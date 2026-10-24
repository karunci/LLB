/*
 * Project Name: PRK (Personal Research Kernel) / Low-Level Basic (LLB)
 * Filename: tests/kernel/src/arch/x86_64/boot.S
 * Summary: 32-bit Multiboot bootstrap, 64-bit long-mode paging setup, and kernel entry.
 */

.code32
.section .multiboot_header
.align 8

/* ============================================================================
 * MULTIBOOT 1 HEADER (For QEMU -kernel direct boot)
 * ============================================================================ */
#define MULTIBOOT_HEADER_MAGIC      0x1BADB002
#define MULTIBOOT_HEADER_FLAGS      0x00010003 /* ALIGN + MEMINFO + AOUT_KLUDGE */

.align 4
multiboot1_header:
    .long MULTIBOOT_HEADER_MAGIC
    .long MULTIBOOT_HEADER_FLAGS
    .long -(MULTIBOOT_HEADER_MAGIC + MULTIBOOT_HEADER_FLAGS)
    .long multiboot1_header /* header_addr */
    .long 0x100000          /* load_addr */
    .long 0                 /* load_end_addr */
    .long 0                 /* bss_end_addr */
    .long _start            /* entry_addr */

/* ============================================================================
 * MULTIBOOT 2 HEADER SPECIFICATION
 * ============================================================================ */
#define MULTIBOOT2_HEADER_MAGIC     0xe85250d6
#define MULTIBOOT_ARCHITECTURE_I386 0
#define MULTIBOOT_HEADER_TAG_END    0

.align 8
header_start:
    .long MULTIBOOT2_HEADER_MAGIC
    .long MULTIBOOT_ARCHITECTURE_I386
    .long header_end - header_start
    .long -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + (header_end - header_start))

    /* Multiboot2 Framebuffer Request Tag (Type 5) */
    .align 8
    .short 5     /* type = MULTIBOOT_HEADER_TAG_FRAMEBUFFER */
    .short 0     /* flags = 0 */
    .long  24    /* size = 24 bytes */
    .long  1280  /* preferred width */
    .long  720   /* preferred height */
    .long  32    /* preferred depth (bpp) */
    .long  0     /* padding to 8-byte boundary */

    /* Multiboot2 End Tag */
    .align 8
    .word MULTIBOOT_HEADER_TAG_END
    .word 0
    .long 8
header_end:

/* ============================================================================
 * EARLY BSS BOOTSTACK & PAGE TABLES (IDENTITY MAPPED FIRST 2MB)
 * ============================================================================ */
.section .bss
.align 4096
page_table_l4:
    .skip 4096
page_table_l3:
    .skip 4096
page_table_l2:
    .skip 4096
page_table_l2_apic:
    .skip 4096

.align 16
stack_bottom:
    .skip 16384 /* 16 KiB Kernel Boot Stack */
stack_top:

/* ============================================================================
 * 32-BIT PROTECTED MODE ENTRY POINT
 * ============================================================================ */
.code32
.section .text
.global _start
.type _start, @function

_start:
    /* Disable Interrupts and Setup Temporary 32-bit Stack */
    cli
    mov $stack_top, %esp

    /* Store Multiboot Magic Number (%eax) and Information Structure (%ebx) on stack */
    push %ebx
    push %eax

    /* 1. Setup Early Paging structures (Zeroes 16KB and identity maps) */
    call setup_page_tables
    call enable_paging

    /* 2. Load 64-bit Global Descriptor Table (GDT) */
    mov $gdt64_pointer, %eax
    lgdt (%eax)

    /* Restore Multiboot arguments for long mode (%edi = magic, %esi = mbi) */
    pop %edi
    pop %esi

    /* 3. Far jump to 64-bit code segment using 32-bit far return (lret) */
    push $0x08
    push $long_mode_entry
    lret

/* Setup 4-level Page Tables */
setup_page_tables:
    /* Zero out all early boot page tables (16KB: page_table_l4, page_table_l3, page_table_l2, page_table_l2_apic) */
    mov $page_table_l4, %edi
    xor %eax, %eax
    mov $4096, %ecx       /* 4096 dwords = 16384 bytes */
    cld
    rep stosl

    /* Map L4[0] -> L3 */
    mov $page_table_l3, %eax
    or $0x3, %eax /* Present + Writable */
    mov $page_table_l4, %ebx
    mov %eax, (%ebx)
    movl $0, 4(%ebx)

    /* Map L3[0] -> L2 */
    mov $page_table_l2, %eax
    or $0x3, %eax
    mov $page_table_l3, %ebx
    mov %eax, (%ebx)
    movl $0, 4(%ebx)

    /* Map all 512 entries of L2 -> 2MB Huge Pages (Identity Map physical 0x0 - 0x40000000 = 1GB) */
    mov $page_table_l2, %ebx
    mov $512, %ecx        /* 512 entries */
    mov $0x83, %eax       /* Physical 0x0 | Present (1) | Writable (2) | HugePage (0x80) */
1:
    mov %eax, (%ebx)
    movl $0, 4(%ebx)
    add $0x200000, %eax   /* Next 2MB physical frame */
    add $8, %ebx          /* Next PTE entry */
    sub $1, %ecx
    jnz 1b

    /* Map L3[3] -> L2_APIC (Physical 3GB - 4GB region) */
    mov $page_table_l2_apic, %eax
    or $0x3, %eax
    mov $page_table_l3, %ebx
    mov %eax, 24(%ebx)
    movl $0, 28(%ebx)

    /* Identity map all 512 entries of L2_APIC (3GB to 4GB: 0xC0000000 - 0x100000000)
     * This covers ACPI tables (RSDT/MADT/FADT around 0xFE232000), IOAPIC (0xFEC00000), and LAPIC (0xFEE00000).
     */
    mov $page_table_l2_apic, %ebx
    mov $512, %ecx
    mov $0xC0000083, %eax /* Physical 3GB | Present | Writable | HugePage */
1:
    mov %eax, (%ebx)
    movl $0, 4(%ebx)
    add $0x200000, %eax
    add $8, %ebx
    sub $1, %ecx
    jnz 1b
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

    /* Pass Multiboot2 arguments (%rdi = magic, %rsi = multiboot_info_ptr) */
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

