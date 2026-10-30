#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Script: tests/kernel/scripts/build_iso.sh
# Purpose: Build a hybrid BIOS & UEFI bootable ISO using proot-distro (ubuntu)
#          and grub-mkrescue with dynamic host-guest home directory binding.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KERNEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROJECT_ROOT="$(cd "${KERNEL_DIR}/.." && pwd -P)"

KERNEL_ELF="${KERNEL_DIR}/build/kernel.elf"
ISO_DIR="${KERNEL_DIR}/build/iso"
OUTPUT_ISO="${KERNEL_DIR}/build/kernel.iso"

INITRD_TAR="${PROJECT_ROOT}/build/initrd.tar"

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
./build/llbc-stage0 services/ramfs_srv/Ramfs.llbproj
./build/llbc-stage0 apps/cli/coreutils/ls/Ls.llbproj
./build/llbc-stage0 apps/cli/coreutils/cat/Cat.llbproj
./build/llbc-stage0 apps/cli/coreutils/uptime/Uptime.llbproj
./build/llbc-stage0 apps/cli/coreutils/ver/Ver.llbproj
./build/llbc-stage0 apps/cli/coreutils/echo/Echo.llbproj
./build/llbc-stage0 apps/gui/sys_mon/SysMon.llbproj
./build/llbc-stage0 apps/gui/terminal/Terminal.llbproj
./build/llbc-stage0 apps/gui/node_viewer/NodeViewer.llbproj
./build/llbc-stage0 apps/gui/user_app/UserApp.llbproj

python3 tools/bax_pack.py services/genesis/build/genesis.elf -o services/genesis/build/genesis.bax --manifest services/genesis/manifest.json
python3 tools/bax_pack.py services/disp_srv/build/disp_srv.elf -o services/disp_srv/build/disp_srv.bax --manifest services/disp_srv/manifest.json
python3 tools/bax_pack.py services/input_srv/build/input_srv.elf -o services/input_srv/build/input_srv.bax --manifest services/input_srv/manifest.json
python3 tools/bax_pack.py services/compositor/build/compositor.elf -o services/compositor/build/compositor.bax --manifest services/compositor/manifest.json
python3 tools/bax_pack.py services/dev_mgr/build/dev_mgr.elf -o services/dev_mgr/build/dev_mgr.bax --manifest services/dev_mgr/manifest.json
python3 tools/bax_pack.py services/plexus_mgr/build/plexus_mgr.elf -o services/plexus_mgr/build/plexus_mgr.bax --manifest services/plexus_mgr/manifest.json
python3 tools/bax_pack.py services/wm/build/wm.elf -o services/wm/build/wm.bax --manifest services/wm/manifest.json
python3 tools/bax_pack.py services/vfs_srv/build/vfs_srv.elf -o services/vfs_srv/build/vfs_srv.bax --manifest services/vfs_srv/manifest.json
python3 tools/bax_pack.py services/ramfs_srv/build/ramfs_srv.elf -o services/ramfs_srv/build/ramfs_srv.bax --manifest services/ramfs_srv/manifest.json
python3 tools/bax_pack.py apps/cli/coreutils/ls/build/ls.elf -o apps/cli/coreutils/ls/build/ls.bax --manifest apps/cli/coreutils/ls/manifest.json
python3 tools/bax_pack.py apps/cli/coreutils/cat/build/cat.elf -o apps/cli/coreutils/cat/build/cat.bax --manifest apps/cli/coreutils/cat/manifest.json
python3 tools/bax_pack.py apps/cli/coreutils/uptime/build/uptime.elf -o apps/cli/coreutils/uptime/build/uptime.bax --manifest apps/cli/coreutils/uptime/manifest.json
python3 tools/bax_pack.py apps/cli/coreutils/ver/build/ver.elf -o apps/cli/coreutils/ver/build/ver.bax --manifest apps/cli/coreutils/ver/manifest.json
python3 tools/bax_pack.py apps/cli/coreutils/echo/build/echo.elf -o apps/cli/coreutils/echo/build/echo.bax --manifest apps/cli/coreutils/echo/manifest.json
python3 tools/bax_pack.py apps/gui/sys_mon/build/sys_mon.elf -o apps/gui/sys_mon/build/sys_mon.bax --manifest apps/gui/sys_mon/manifest.json
python3 tools/bax_pack.py apps/gui/terminal/build/terminal.elf -o apps/gui/terminal/build/terminal.bax --manifest apps/gui/terminal/manifest.json
python3 tools/bax_pack.py apps/gui/node_viewer/build/node_viewer.elf -o apps/gui/node_viewer/build/node_viewer.bax --manifest apps/gui/node_viewer/manifest.json
python3 tools/bax_pack.py apps/gui/user_app/build/user_app.elf -o apps/gui/user_app/build/user_app.bax --manifest apps/gui/user_app/manifest.json

bash tools/pack_initrd.sh

echo "[+] Building Dedicated Kernel ELFs (MB2 and MB1)..."
./build/llbc-stage0 kernel/Kernel_MB2.llbproj
./build/llbc-stage0 kernel/Kernel_MB1.llbproj
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
