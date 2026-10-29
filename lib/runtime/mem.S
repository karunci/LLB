/*
 * Project: PROS (Personal Research Operating System) / Low-Level Basic
 * File: lib/runtime/mem.S
 * Description: High-performance freestanding memory primitives (memcpy, memset, memmove, memcmp, strlen).
 */

.code64
.text

/* ============================================================================
 * Function: memcpy
 * Signature: void *memcpy(void *dest, const void *src, size_t n)
 * Returns: dest pointer in %rax
 * Invariant: %rcx explicitly reloaded for tail byte transfer
 * ============================================================================ */
.global memcpy
.type memcpy, @function
memcpy:
    movq %rdi, %rax            /* Save dest for return value */
    cld

    /* Copy 64-bit quadwords */
    movq %rdx, %rcx
    shrq $3, %rcx
    rep movsq

    /* %rcx reload invariant for trailing bytes */
    movq %rdx, %rcx
    andq $7, %rcx
    rep movsb

    ret
.size memcpy, . - memcpy

/* ============================================================================
 * Function: memset
 * Signature: void *memset(void *dest, int val, size_t n)
 * Returns: dest pointer in %rax
 * Invariant: 64-bit broadcast of val; %rcx explicitly reloaded for tail bytes
 * ============================================================================ */
.global memset
.type memset, @function
memset:
    cld
    movq %rdi, %r8             /* Save dest in scratch register */

    /* 64-bit broadcast of 8-bit fill byte in %sil across %rax */
    movzbl %sil, %eax
    movabsq $0x0101010101010101, %r9
    imulq %r9, %rax

    /* Store 64-bit quadwords */
    movq %rdx, %rcx
    shrq $3, %rcx
    rep stosq

    /* %rcx reload invariant for trailing bytes (%al holds broadcast byte) */
    movq %rdx, %rcx
    andq $7, %rcx
    rep stosb

    movq %r8, %rax             /* Restore dest to %rax */
    ret
.size memset, . - memset

/* ============================================================================
 * Function: memmove
 * Signature: void *memmove(void *dest, const void *src, size_t n)
 * Returns: dest pointer in %rax
 * Invariant: Overlap check: backward copy on dest > src and dest < src + n
 * ============================================================================ */
.global memmove
.type memmove, @function
memmove:
    movq %rdi, %rax            /* Save dest for return value */
    testq %rdx, %rdx
    jz .Lmemmove_done

    cmpq %rsi, %rdi
    jbe .Lmemmove_forward      /* dest <= src: safe to copy forward */

    movq %rsi, %r8
    addq %rdx, %r8             /* %r8 = src + n */
    cmpq %r8, %rdi
    jae .Lmemmove_forward      /* dest >= src + n: disjoint, safe to copy forward */

.Lmemmove_backward:
    /* Overlapping: dest > src and dest < src + n. Copy backward from end */
    std                        /* Set direction flag (decrement pointers) */
    addq %rdx, %rsi
    decq %rsi                  /* %rsi = src + n - 1 */
    addq %rdx, %rdi
    decq %rdi                  /* %rdi = dest + n - 1 */
    movq %rdx, %rcx
    rep movsb
    cld                        /* Clear direction flag per System V ABI */
    ret

.Lmemmove_forward:
    cld
    movq %rdx, %rcx
    shrq $3, %rcx
    rep movsq
    movq %rdx, %rcx
    andq $7, %rcx
    rep movsb

.Lmemmove_done:
    ret
.size memmove, . - memmove

/* ============================================================================
 * Function: memcmp
 * Signature: int memcmp(const void *s1, const void *s2, size_t n)
 * Returns: <0, 0, or >0 signed integer in %eax
 * ============================================================================ */
.global memcmp
.type memcmp, @function
memcmp:
    xorq %rax, %rax
    testq %rdx, %rdx
    jz .Lmemcmp_done

    movq %rdx, %rcx

.Lmemcmp_loop:
    movzbl (%rdi), %eax
    movzbl (%rsi), %edx
    subl %edx, %eax
    jnz .Lmemcmp_done          /* Return difference *s1 - *s2 in %eax */

    incq %rdi
    incq %rsi
    decq %rcx
    jnz .Lmemcmp_loop

    xorq %rax, %rax            /* All bytes matched: return 0 */

.Lmemcmp_done:
    ret
.size memcmp, . - memcmp

/* ============================================================================
 * Function: strlen
 * Signature: size_t strlen(const char *str)
 * Returns: byte count in %rax (excluding null terminator)
 * Invariant: Guards against null pointer, returning 0
 * ============================================================================ */
.global strlen
.type strlen, @function
strlen:
    xorq %rax, %rax
    testq %rdi, %rdi
    jz .Lstrlen_done           /* Null pointer guard: return 0 */

.Lstrlen_loop:
    cmpb $0, (%rdi, %rax)
    je .Lstrlen_done
    incq %rax
    jmp .Lstrlen_loop

.Lstrlen_done:
    ret
.size strlen, . - strlen
