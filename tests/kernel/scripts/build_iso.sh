#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Script: tests/kernel/scripts/build_iso.sh
# Purpose: Build a hybrid BIOS & UEFI bootable ISO using proot-distro (ubuntu)
#          and grub-mkrescue with dynamic host-guest home directory binding.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KERNEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROJECT_ROOT="$(cd "${KERNEL_DIR}/../.." && pwd -P)"

KERNEL_ELF="${KERNEL_DIR}/build/kernel.elf"
ISO_DIR="${KERNEL_DIR}/build/iso"
OUTPUT_ISO="${KERNEL_DIR}/build/kernel.iso"

if [ ! -f "${KERNEL_ELF}" ]; then
    echo "[!] kernel.elf not found at ${KERNEL_ELF}. Compiling..."
    cd "${PROJECT_ROOT}"
    ./build/llbc-stage0 tests/kernel/Kernel.llbproj
fi

echo "[+] Preparing GRUB ISO staging tree at ${ISO_DIR}..."
rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}/boot/grub"
cp "${KERNEL_ELF}" "${ISO_DIR}/boot/kernel.elf"

cat << 'EOF' > "${ISO_DIR}/boot/grub/grub.cfg"
set timeout=3
set default=0
set gfxpayload=1280x720x32

menuentry "Low-Level Basic Kernel (PRK/LLB)" {
    insmod all_video
    multiboot2 /boot/kernel.elf
    boot
}
menuentry "Low-Level Basic Kernel (PRK/LLB) - Multiboot 1 Fallback" {
    insmod all_video
    multiboot /boot/kernel.elf
    boot
}
EOF

echo "[+] Validating Multiboot headers via proot-distro grub-file..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-file --is-x86-multiboot2 "${ISO_DIR}/boot/kernel.elf"

echo "[+] Generating Hybrid BIOS/UEFI bootable ISO with grub-mkrescue..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_DIR}"

echo "[SUCCESS] Bootable ISO generated: ${OUTPUT_ISO}"
