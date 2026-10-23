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

    /* Multiboot2 End Tag */
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

    /* Store Multiboot Magic Number (%eax) and Information Structure (%ebx) */
    mov %eax, %edi
    mov %ebx, %esi

    /* 1. Setup Early Paging structures (Identity map 0 - 2MB) */
    call setup_page_tables
    call enable_paging

    /* 2. Load 64-bit Global Descriptor Table (GDT) */
    mov $gdt64_pointer, %eax
    lgdt (%eax)

    /* 3. Far jump to 64-bit code segment using 32-bit far return (lret) */
    push $0x08
    push $long_mode_entry
    lret

/* Setup 4-level Page Tables */
setup_page_tables:
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

    /* Map IOAPIC physical 0xFEC00000 (Index (0xFEC00000 - 0xC0000000) / 2MB = 502 -> offset 502*8 = 4016) */
    mov $page_table_l2_apic, %ebx
    mov $0xFEC00000, %eax
    or $0x93, %eax /* Present + Writable + HugePage (0x80) + Cache-Disable (0x10) for MMIO */
    mov %eax, 4016(%ebx)
    movl $0, 4020(%ebx)

    /* Map Local APIC physical 0xFEE00000 (Index (0xFEE00000 - 0xC0000000) / 2MB = 503 -> offset 503*8 = 4024) */
    mov $0xFEE00000, %eax
    or $0x93, %eax /* Present + Writable + HugePage + Cache-Disable */
    mov %eax, 4024(%ebx)
    movl $0, 4028(%ebx)
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

