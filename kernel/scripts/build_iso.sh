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

LLBC="${PROJECT_ROOT}/../llbc/build/llbc-stage0"
if [ ! -f "${LLBC}" ]; then
    LLBC="$(command -v llbc-stage0 || command -v llbc || true)"
fi

echo "[+] Building and packaging Userland Services and Applications..."
cd "${PROJECT_ROOT}"
if [ -n "${LLBC}" ] && [ -f "${LLBC}" ]; then
    "${LLBC}" lib/pros/Pros.llbproj
    "${LLBC}" drivers/disp/lfb/LfbDriver.llbproj
    "${LLBC}" drivers/disp/svga/SvgaDriver.llbproj
    "${LLBC}" services/genesis/Genesis.llbproj
    "${LLBC}" services/disp_srv/DispService.llbproj
    "${LLBC}" services/input_srv/InputService.llbproj
    "${LLBC}" services/compositor/Compositor.llbproj
    "${LLBC}" services/dev_mgr/DevMgr.llbproj
    "${LLBC}" services/plexus_mgr/PlexusMgr.llbproj
    "${LLBC}" services/wm/WmService.llbproj
    "${LLBC}" services/vfs_srv/VfsService.llbproj
    "${LLBC}" services/ramfs_srv/Ramfs.llbproj
    "${LLBC}" apps/cli/coreutils/ls/Ls.llbproj
    "${LLBC}" apps/cli/coreutils/cat/Cat.llbproj
    "${LLBC}" apps/cli/coreutils/uptime/Uptime.llbproj
    "${LLBC}" apps/cli/coreutils/ver/Ver.llbproj
    "${LLBC}" apps/cli/coreutils/echo/Echo.llbproj
    "${LLBC}" apps/gui/sys_mon/SysMon.llbproj
    "${LLBC}" apps/gui/terminal/Terminal.llbproj
    "${LLBC}" apps/gui/node_viewer/NodeViewer.llbproj
    "${LLBC}" apps/gui/user_app/UserApp.llbproj
    "${LLBC}" apps/gui/doom/Doom.llbproj
    "${LLBC}" tools/bax_pack/BaxPack.llbproj
fi

echo "[+] Packaging ELF binaries into Neural BAX containers..."
BAX_CMD="tools/bax_pack/build/bax_pack"
if [ ! -x "${BAX_CMD}" ]; then
    BAX_CMD="python3 tools/bax_pack.py"
fi

${BAX_CMD} drivers/disp/lfb/build/lfb_drv.elf -o drivers/disp/lfb/build/lfb_drv.bax --manifest drivers/disp/lfb/manifest.json
${BAX_CMD} drivers/disp/svga/build/svga_drv.elf -o drivers/disp/svga/build/svga_drv.bax --manifest drivers/disp/svga/manifest.json
${BAX_CMD} services/genesis/build/genesis.elf -o services/genesis/build/genesis.bax --manifest services/genesis/manifest.json
${BAX_CMD} services/disp_srv/build/disp_srv.elf -o services/disp_srv/build/disp_srv.bax --manifest services/disp_srv/manifest.json
${BAX_CMD} services/input_srv/build/input_srv.elf -o services/input_srv/build/input_srv.bax --manifest services/input_srv/manifest.json
${BAX_CMD} services/compositor/build/compositor.elf -o services/compositor/build/compositor.bax --manifest services/compositor/manifest.json
${BAX_CMD} services/dev_mgr/build/dev_mgr.elf -o services/dev_mgr/build/dev_mgr.bax --manifest services/dev_mgr/manifest.json
${BAX_CMD} services/plexus_mgr/build/plexus_mgr.elf -o services/plexus_mgr/build/plexus_mgr.bax --manifest services/plexus_mgr/manifest.json
${BAX_CMD} services/wm/build/wm.elf -o services/wm/build/wm.bax --manifest services/wm/manifest.json
${BAX_CMD} services/vfs_srv/build/vfs_srv.elf -o services/vfs_srv/build/vfs_srv.bax --manifest services/vfs_srv/manifest.json
${BAX_CMD} services/ramfs_srv/build/ramfs_srv.elf -o services/ramfs_srv/build/ramfs_srv.bax --manifest services/ramfs_srv/manifest.json
${BAX_CMD} apps/cli/coreutils/ls/build/ls.elf -o apps/cli/coreutils/ls/build/ls.bax --manifest apps/cli/coreutils/ls/manifest.json
${BAX_CMD} apps/cli/coreutils/cat/build/cat.elf -o apps/cli/coreutils/cat/build/cat.bax --manifest apps/cli/coreutils/cat/manifest.json
${BAX_CMD} apps/cli/coreutils/uptime/build/uptime.elf -o apps/cli/coreutils/uptime/build/uptime.bax --manifest apps/cli/coreutils/uptime/manifest.json
${BAX_CMD} apps/cli/coreutils/ver/build/ver.elf -o apps/cli/coreutils/ver/build/ver.bax --manifest apps/cli/coreutils/ver/manifest.json
${BAX_CMD} apps/cli/coreutils/echo/build/echo.elf -o apps/cli/coreutils/echo/build/echo.bax --manifest apps/cli/coreutils/echo/manifest.json
${BAX_CMD} apps/gui/sys_mon/build/sys_mon.elf -o apps/gui/sys_mon/build/sys_mon.bax --manifest apps/gui/sys_mon/manifest.json
${BAX_CMD} apps/gui/terminal/build/terminal.elf -o apps/gui/terminal/build/terminal.bax --manifest apps/gui/terminal/manifest.json
${BAX_CMD} apps/gui/node_viewer/build/node_viewer.elf -o apps/gui/node_viewer/build/node_viewer.bax --manifest apps/gui/node_viewer/manifest.json
${BAX_CMD} apps/gui/user_app/build/user_app.elf -o apps/gui/user_app/build/user_app.bax --manifest apps/gui/user_app/manifest.json
if [ -f apps/gui/doom/build/doom.elf ]; then
    ${BAX_CMD} apps/gui/doom/build/doom.elf -o apps/gui/doom/build/doom.bax --manifest apps/gui/doom/manifest.json
fi

bash tools/pack_initrd.sh

echo "[+] Building Dedicated Kernel ELFs (MB2 and MB1)..."
cd "${PROJECT_ROOT}"
if [ -n "${LLBC}" ] && [ -f "${LLBC}" ]; then
    "${LLBC}" kernel/Kernel_MB2.llbproj
    "${LLBC}" kernel/Kernel_MB1.llbproj
fi
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
