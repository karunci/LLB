/*
 * Project: PROS Freestanding Runtime
 * File: lib/runtime/fast_blit32.S
 * Description: High-performance 32-bit DWORD scanline burst blitter primitives for
 *              PCIe MMIO transfers and RAM-to-RAM backbuffer copies.
 *
 *   fast_blit32     — RAM-to-RAM: `rep movsl`. Use for backSurf compositing passes.
 *   fast_blit32_nt  — RAM-to-VRAM: non-temporal `movnti`. Use for frontSurf MMIO
 *                     flushes. Bypasses CPU cache, avoids EPT violations in VirtualBox,
 *                     and prevents cache pollution from UC/WC framebuffer apertures.
 */

.code64
.text

/* -----------------------------------------------------------------------
 * fast_blit32 — Cached DWORD copy (RAM -> RAM, backbuffer compositing)
 *   %rdi = dst DWORD pointer
 *   %rsi = src DWORD pointer
 *   %rdx = count (UInt64)
 * --------------------------------------------------------------------- */
.global fast_blit32
.type fast_blit32, @function
fast_blit32:
    cld
    movq %rdx, %rcx
    rep movsl
    ret
.size fast_blit32, . - fast_blit32

/* -----------------------------------------------------------------------
 * fast_blit32_nt — Non-temporal DWORD store (RAM -> VRAM MMIO aperture)
 *   %rdi = dst DWORD pointer (VRAM / MMIO aperture — frontSurf)
 *   %rsi = src DWORD pointer (RAM backbuffer — backSurf)
 *   %rdx = count (UInt64)
 *
 *  Uses `movnti` (non-temporal store) to write directly to the MMIO
 *  aperture without allocating a cache line, avoiding:
 *   - CPU write-back cache eviction storms on WB-mapped VRAM
 *   - EPT violations in VirtualBox on UC-mapped framebuffers
 *   - Cache line splits on PCIe MMIO boundaries
 *  sfence ensures all stores reach the framebuffer before returning.
 * --------------------------------------------------------------------- */
.global fast_blit32_nt
.type fast_blit32_nt, @function
fast_blit32_nt:
    test %rdx, %rdx
    jz   .nt_done
    /* Unroll 4x to maximize PCIe burst utilisation */
.nt_loop4:
    cmp  $4, %rdx
    jb   .nt_tail
    movl  (%rsi),    %eax
    movnti %eax,    (%rdi)
    movl  4(%rsi),  %eax
    movnti %eax,   4(%rdi)
    movl  8(%rsi),  %eax
    movnti %eax,   8(%rdi)
    movl 12(%rsi),  %eax
    movnti %eax,  12(%rdi)
    addq $16, %rsi
    addq $16, %rdi
    subq $4,  %rdx
    jmp  .nt_loop4
.nt_tail:
    test %rdx, %rdx
    jz   .nt_sfence
    movl (%rsi), %eax
    movnti %eax, (%rdi)
    addq $4, %rsi
    addq $4, %rdi
    decq %rdx
    jmp  .nt_tail
.nt_sfence:
    sfence
.nt_done:
    ret
.size fast_blit32_nt, . - fast_blit32_nt
