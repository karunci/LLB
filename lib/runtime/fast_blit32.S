/*
 * Project: PROS Freestanding Runtime
 * File: lib/runtime/fast_blit32.S
 * Description: High-performance 32-bit DWORD scanline burst blitter primitive for PCIe MMIO transfers.
 */

.code64
.text
.global fast_blit32
.type fast_blit32, @function

fast_blit32:
    /* System V AMD64 ABI:
     *   %rdi = dst DWORD pointer (MMIO VRAM aperture or surface buffer)
     *   %rsi = src DWORD pointer (RAM backbuffer or source buffer)
     *   %rdx = count of 32-bit DWORD pixels (UInt64)
     */
    cld
    movq %rdx, %rcx
    rep movsl
    ret

.size fast_blit32, . - fast_blit32
