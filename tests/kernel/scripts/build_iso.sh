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

INITRD_TAR="${PROJECT_ROOT}/tests/user_app/build/initrd.tar"

if [ ! -f "${KERNEL_ELF}" ]; then
    echo "[!] kernel.elf not found at ${KERNEL_ELF}. Compiling..."
    cd "${PROJECT_ROOT}"
    ./build/llbc-stage0 tests/kernel/Kernel.llbproj
fi

if [ ! -f "${INITRD_TAR}" ]; then
    echo "[!] initrd.tar not found at ${INITRD_TAR}. Packaging..."
    cd "${PROJECT_ROOT}"
    ./build/llbc-stage0 services/disp_srv/DispService.llbproj
    ./build/llbc-stage0 services/input_srv/InputService.llbproj
    ./build/llbc-stage0 tests/user_app/UserApp.llbproj
    python3 tools/bax_pack.py services/disp_srv/build/disp_srv.elf -o services/disp_srv/build/disp_srv.bax --manifest services/disp_srv/manifest.json
    python3 tools/bax_pack.py services/input_srv/build/input_srv.elf -o services/input_srv/build/input_srv.bax --manifest services/input_srv/manifest.json
    python3 tools/bax_pack.py tests/user_app/build/user_app.elf -o tests/user_app/build/user_app.bax --manifest tests/user_app/manifest.json
    tar -cf tests/user_app/build/initrd.tar -C tests/user_app/build user_app.bax -C ../../../services/disp_srv/build disp_srv.bax -C ../../../services/input_srv/build input_srv.bax
fi

echo "[+] Preparing GRUB ISO staging tree at ${ISO_DIR}..."
rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}/boot/grub"
cp "${KERNEL_ELF}" "${ISO_DIR}/boot/kernel.elf"
cp "${INITRD_TAR}" "${ISO_DIR}/boot/initrd.tar"

cat << 'EOF' > "${ISO_DIR}/boot/grub/grub.cfg"
set timeout=3
set default=0

insmod all_video
insmod gfxterm
set gfxmode=1024x768x32,1024x768,auto
terminal_output gfxterm
set gfxpayload=keep

menuentry "Low-Level Basic Kernel (PRK/LLB)" {
    insmod part_msdos
    insmod iso9660
    set gfxpayload=keep
    multiboot /boot/kernel.elf
    module /boot/initrd.tar
    boot
}

menuentry "Low-Level Basic Kernel (PRK/LLB) - Multiboot 2" {
    insmod part_msdos
    insmod iso9660
    set gfxpayload=keep
    multiboot2 /boot/kernel.elf
    module2 /boot/initrd.tar
    boot
}
EOF

echo "[+] Validating Multiboot headers via proot-distro grub-file..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-file --is-x86-multiboot2 "${ISO_DIR}/boot/kernel.elf"

echo "[+] Generating Hybrid BIOS/UEFI bootable ISO with grub-mkrescue..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_DIR}"

echo "[SUCCESS] Bootable ISO generated: ${OUTPUT_ISO}"
