/*
 * Project: LibPROS / Low-Level Basic
 * File: lib/pros/src/fast_fill32.S
 * Description: High-performance 32-bit DWORD hardware burst fill primitive (rep stosl).
 */

.code64
.text
.global fast_fill32
.type fast_fill32, @function

fast_fill32:
    /* System V AMD64 ABI:
     *   %rdi = dst DWORD pointer (UInt32 *)
     *   %esi = color (32-bit DWORD)
     *   %rdx = count of 32-bit pixels (UInt64)
     */
    cld
    movl %esi, %eax
    movq %rdx, %rcx
    rep stosl
    ret
