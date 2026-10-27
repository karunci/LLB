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

echo "[+] Building and packaging Userland Services and Applications..."
cd "${PROJECT_ROOT}"
./build/llbc-stage0 lib/pros/Pros.llbproj
./build/llbc-stage0 services/genesis/Genesis.llbproj
./build/llbc-stage0 services/disp_srv/DispService.llbproj
./build/llbc-stage0 services/input_srv/InputService.llbproj
./build/llbc-stage0 services/compositor/Compositor.llbproj
./build/llbc-stage0 services/dev_mgr/DevMgr.llbproj
./build/llbc-stage0 services/plexus_mgr/PlexusMgr.llbproj
./build/llbc-stage0 services/wm/WmService.llbproj
./build/llbc-stage0 services/vfs_srv/VfsService.llbproj
./build/llbc-stage0 services/sys_mon/SysMon.llbproj
./build/llbc-stage0 services/terminal/Terminal.llbproj
./build/llbc-stage0 services/node_viewer/NodeViewer.llbproj
./build/llbc-stage0 tests/user_app/UserApp.llbproj

python3 tools/bax_pack.py services/genesis/build/genesis.elf -o services/genesis/build/genesis.bax --manifest services/genesis/manifest.json
python3 tools/bax_pack.py services/disp_srv/build/disp_srv.elf -o services/disp_srv/build/disp_srv.bax --manifest services/disp_srv/manifest.json
python3 tools/bax_pack.py services/input_srv/build/input_srv.elf -o services/input_srv/build/input_srv.bax --manifest services/input_srv/manifest.json
python3 tools/bax_pack.py services/compositor/build/compositor.elf -o services/compositor/build/compositor.bax --manifest services/compositor/manifest.json
python3 tools/bax_pack.py services/dev_mgr/build/dev_mgr.elf -o services/dev_mgr/build/dev_mgr.bax --manifest services/dev_mgr/manifest.json
python3 tools/bax_pack.py services/plexus_mgr/build/plexus_mgr.elf -o services/plexus_mgr/build/plexus_mgr.bax --manifest services/plexus_mgr/manifest.json
python3 tools/bax_pack.py services/wm/build/wm.elf -o services/wm/build/wm.bax --manifest services/wm/manifest.json
python3 tools/bax_pack.py services/vfs_srv/build/vfs_srv.elf -o services/vfs_srv/build/vfs_srv.bax --manifest services/vfs_srv/manifest.json
python3 tools/bax_pack.py services/sys_mon/build/sys_mon.elf -o services/sys_mon/build/sys_mon.bax --manifest services/sys_mon/manifest.json
python3 tools/bax_pack.py services/terminal/build/terminal.elf -o services/terminal/build/terminal.bax --manifest services/terminal/manifest.json
python3 tools/bax_pack.py services/node_viewer/build/node_viewer.elf -o services/node_viewer/build/node_viewer.bax --manifest services/node_viewer/manifest.json
python3 tools/bax_pack.py tests/user_app/build/user_app.elf -o tests/user_app/build/user_app.bax --manifest tests/user_app/manifest.json

STAGING_DIR="${PROJECT_ROOT}/build/initrd_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/System/Servers"
mkdir -p "${STAGING_DIR}/System/Libraries"
mkdir -p "${STAGING_DIR}/System/Configs"
mkdir -p "${STAGING_DIR}/Apps/UserApp"
mkdir -p "${STAGING_DIR}/Users/Default"

cp "${PROJECT_ROOT}/services/genesis/build/genesis.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/disp_srv/build/disp_srv.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/input_srv/build/input_srv.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/compositor/build/compositor.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/dev_mgr/build/dev_mgr.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/plexus_mgr/build/plexus_mgr.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/wm/build/wm.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/vfs_srv/build/vfs_srv.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/sys_mon/build/sys_mon.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/terminal/build/terminal.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/services/node_viewer/build/node_viewer.bax" "${STAGING_DIR}/System/Servers/"
cp "${PROJECT_ROOT}/tests/user_app/build/user_app.bax" "${STAGING_DIR}/Apps/UserApp/"

# Dual compatibility: provide root-level copies so flat lookups and hierarchical lookups both succeed
cp "${STAGING_DIR}/System/Servers/"*.bax "${STAGING_DIR}/"
cp "${STAGING_DIR}/Apps/UserApp/user_app.bax" "${STAGING_DIR}/"

mkdir -p tests/user_app/build
tar -cf "${INITRD_TAR}" -C "${STAGING_DIR}" .

echo "[+] Building Dedicated Kernel ELFs (MB2 and MB1)..."
./build/llbc-stage0 tests/kernel/Kernel_MB2.llbproj
./build/llbc-stage0 tests/kernel/Kernel_MB1.llbproj
cp "${KERNEL_DIR}/build/kernel_mb2.elf" "${KERNEL_DIR}/build/kernel.elf"

echo "[+] Preparing GRUB ISO staging tree at ${ISO_DIR}..."
rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}/boot/grub"
cp "${KERNEL_DIR}/build/kernel_mb2.elf" "${ISO_DIR}/boot/kernel_mb2.elf"
cp "${KERNEL_DIR}/build/kernel_mb1.elf" "${ISO_DIR}/boot/kernel_mb1.elf"
cp "${KERNEL_DIR}/build/kernel_mb2.elf" "${ISO_DIR}/boot/kernel.elf"
cp "${INITRD_TAR}" "${ISO_DIR}/boot/initrd.tar"

cat << 'EOF' > "${ISO_DIR}/boot/grub/grub.cfg"
set timeout=3

insmod all_video
insmod font
insmod multiboot
insmod multiboot2

# Firmware auto-selection: Multiboot 2 for UEFI GOP, Multiboot 1 for Legacy BIOS / VirtualBox CSM
if [ "$grub_platform" = "efi" ]; then
    insmod efi_gop
    set default=0
else
    insmod vbe
    insmod vga
    set default=1
fi

if loadfont unicode ; then
    insmod gfxterm
    set gfxmode=1024x768x32,1920x1080x32,1366x768x32,1280x720x32,auto
    set gfxpayload=1024x768x32,auto,keep
    terminal_output gfxterm
fi

set gfxmode=1024x768x32,1920x1080x32,1366x768x32,1280x720x32,auto
set gfxpayload=1024x768x32,auto,keep

menuentry "Low-Level Basic Kernel (PROS/LLB) [Multiboot 2 - Native UEFI GOP]" {
    set gfxpayload=1024x768x32,auto,keep
    multiboot2 /boot/kernel_mb2.elf
    module2 /boot/initrd.tar "initrd"
    boot
}

menuentry "Low-Level Basic Kernel (PROS/LLB) [Multiboot 1 - Legacy BIOS / CSM]" {
    insmod part_msdos
    insmod iso9660
    set gfxpayload=1024x768x32,auto,keep
    multiboot /boot/kernel_mb1.elf
    module /boot/initrd.tar "initrd"
    boot
}
EOF

echo "[+] Validating Multiboot headers via proot-distro grub-file..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-file --is-x86-multiboot2 "${ISO_DIR}/boot/kernel_mb2.elf"
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-file --is-x86-multiboot "${ISO_DIR}/boot/kernel_mb1.elf"

echo "[+] Generating Hybrid BIOS/UEFI bootable ISO with grub-mkrescue..."
proot-distro login ubuntu --minimal --shared-tmp -b "$HOME:$HOME" -- grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_DIR}"

echo "[SUCCESS] Bootable ISO generated: ${OUTPUT_ISO}"
