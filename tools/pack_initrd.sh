#!/bin/bash
set -e
STAGING_DIR="build/initrd_staging"
rm -rf "${STAGING_DIR}"

# 0. Build native LLB BAX packager if needed
if [ ! -x "tools/bax_pack/build/bax_pack" ]; then
    echo "[+] Building Native Low-Level Basic BAX Packager (tools/bax_pack)..."
    ~/projects/LLB/llbc/build/llbc-stage0 tools/bax_pack/BaxPack.llbproj
fi

# Packaging ELF binaries into Neural BAX containers via native LLB tool
pack_bax() {
    local elf="$1"
    local bax="$2"
    local manifest="$3"
    if [ -f "${elf}" ] && [ -f "${manifest}" ]; then
        if [ -x "tools/bax_pack/build/bax_pack" ]; then
            tools/bax_pack/build/bax_pack "${elf}" -o "${bax}" --manifest "${manifest}"
        else
            python3 tools/bax_pack.py "${elf}" -o "${bax}" --manifest "${manifest}"
        fi
    fi
}

echo "[+] Packaging ELF binaries into Neural BAX containers..."
pack_bax drivers/disp/lfb/build/lfb_drv.elf drivers/disp/lfb/build/lfb_drv.bax drivers/disp/lfb/manifest.json
pack_bax drivers/disp/svga/build/svga_drv.elf drivers/disp/svga/build/svga_drv.bax drivers/disp/svga/manifest.json
pack_bax drivers/snd/hda/build/hda_drv.elf drivers/snd/hda/build/hda_drv.bax drivers/snd/hda/manifest.json
pack_bax services/genesis/build/genesis.elf services/genesis/build/genesis.bax services/genesis/manifest.json
pack_bax services/audio_srv/build/audio_srv.elf services/audio_srv/build/audio_srv.bax services/audio_srv/manifest.json
pack_bax services/disp_srv/build/disp_srv.elf services/disp_srv/build/disp_srv.bax services/disp_srv/manifest.json
pack_bax services/input_srv/build/input_srv.elf services/input_srv/build/input_srv.bax services/input_srv/manifest.json
pack_bax services/compositor/build/compositor.elf services/compositor/build/compositor.bax services/compositor/manifest.json
pack_bax services/dev_mgr/build/dev_mgr.elf services/dev_mgr/build/dev_mgr.bax services/dev_mgr/manifest.json
pack_bax services/plexus_mgr/build/plexus_mgr.elf services/plexus_mgr/build/plexus_mgr.bax services/plexus_mgr/manifest.json
pack_bax services/wm/build/wm.elf services/wm/build/wm.bax services/wm/manifest.json
pack_bax services/vfs_srv/build/vfs_srv.elf services/vfs_srv/build/vfs_srv.bax services/vfs_srv/manifest.json
pack_bax services/ramfs_srv/build/ramfs_srv.elf services/ramfs_srv/build/ramfs_srv.bax services/ramfs_srv/manifest.json
pack_bax apps/cli/coreutils/ls/build/ls.elf apps/cli/coreutils/ls/build/ls.bax apps/cli/coreutils/ls/manifest.json
pack_bax apps/cli/coreutils/cat/build/cat.elf apps/cli/coreutils/cat/build/cat.bax apps/cli/coreutils/cat/manifest.json
pack_bax apps/cli/coreutils/uptime/build/uptime.elf apps/cli/coreutils/uptime/build/uptime.bax apps/cli/coreutils/uptime/manifest.json
pack_bax apps/cli/coreutils/ver/build/ver.elf apps/cli/coreutils/ver/build/ver.bax apps/cli/coreutils/ver/manifest.json
pack_bax apps/cli/coreutils/echo/build/echo.elf apps/cli/coreutils/echo/build/echo.bax apps/cli/coreutils/echo/manifest.json
pack_bax apps/gui/sys_mon/build/sys_mon.elf apps/gui/sys_mon/build/sys_mon.bax apps/gui/sys_mon/manifest.json
pack_bax apps/gui/terminal/build/terminal.elf apps/gui/terminal/build/terminal.bax apps/gui/terminal/manifest.json
pack_bax apps/gui/node_viewer/build/node_viewer.elf apps/gui/node_viewer/build/node_viewer.bax apps/gui/node_viewer/manifest.json
pack_bax apps/gui/resource_mon/build/res_mon.elf apps/gui/resource_mon/build/res_mon.bax apps/gui/resource_mon/manifest.json
pack_bax apps/gui/user_app/build/user_app.elf apps/gui/user_app/build/user_app.bax apps/gui/user_app/manifest.json
pack_bax apps/gui/gl_demo/build/gl_demo.elf apps/gui/gl_demo/build/gl_demo.bax apps/gui/gl_demo/manifest.json
pack_bax apps/gui/doom/build/doom.elf apps/gui/doom/build/doom.bax apps/gui/doom/manifest.json

# 1. Directory Tree Creation
mkdir -p "${STAGING_DIR}/System/Services/Genesis"
mkdir -p "${STAGING_DIR}/System/Services/Compositor"
mkdir -p "${STAGING_DIR}/System/Services/DevMgr"
mkdir -p "${STAGING_DIR}/System/Services/AudioSrv"
mkdir -p "${STAGING_DIR}/System/Services/PlexusMgr"
mkdir -p "${STAGING_DIR}/System/Services/Wm"
mkdir -p "${STAGING_DIR}/System/Services/VfsSrv"
mkdir -p "${STAGING_DIR}/System/Services/RamfsSrv"

mkdir -p "${STAGING_DIR}/System/Drivers/Nodes"
mkdir -p "${STAGING_DIR}/System/Drivers/Display"
mkdir -p "${STAGING_DIR}/System/Drivers/Sound"
mkdir -p "${STAGING_DIR}/System/Drivers/Input"

mkdir -p "${STAGING_DIR}/System/Apps/CoreUtils"
mkdir -p "${STAGING_DIR}/System/Apps/SysMon"
mkdir -p "${STAGING_DIR}/System/Apps/NodeViewer"
mkdir -p "${STAGING_DIR}/System/Apps/ResMon"

mkdir -p "${STAGING_DIR}/System/Libraries"
mkdir -p "${STAGING_DIR}/System/Configurations/Drives"

mkdir -p "${STAGING_DIR}/Apps/Terminal"
mkdir -p "${STAGING_DIR}/Apps/UserApp"
mkdir -p "${STAGING_DIR}/Apps/GlDemo"
mkdir -p "${STAGING_DIR}/Apps/Doom"
mkdir -p "${STAGING_DIR}/Libraries"
mkdir -p "${STAGING_DIR}/Users/Default/Desktop"
mkdir -p "${STAGING_DIR}/Users/Default/Documents"

# 2. Stage Configurations & Manifests
cp configs/environment.cfg "${STAGING_DIR}/System/Configurations/"
cp configs/drives/ramdisk0.cfg "${STAGING_DIR}/System/Configurations/Drives/"

# 3. Stage Microkernel Services & Daemons
cp services/genesis/build/genesis.bax "${STAGING_DIR}/System/Services/Genesis/"
cp services/compositor/build/compositor.bax "${STAGING_DIR}/System/Services/Compositor/"
cp services/dev_mgr/build/dev_mgr.bax "${STAGING_DIR}/System/Services/DevMgr/"
cp services/audio_srv/build/audio_srv.bax "${STAGING_DIR}/System/Services/AudioSrv/"
cp services/plexus_mgr/build/plexus_mgr.bax "${STAGING_DIR}/System/Services/PlexusMgr/"
cp services/wm/build/wm.bax "${STAGING_DIR}/System/Services/Wm/"
cp services/vfs_srv/build/vfs_srv.bax "${STAGING_DIR}/System/Services/VfsSrv/"
if [ -f "services/ramfs_srv/build/ramfs_srv.bax" ]; then
    cp services/ramfs_srv/build/ramfs_srv.bax "${STAGING_DIR}/System/Services/RamfsSrv/"
fi

# 4. Stage Hardware Driver Daemons
cp drivers/disp/lfb/build/lfb_drv.bax "${STAGING_DIR}/System/Drivers/Display/"
cp drivers/disp/svga/build/svga_drv.bax "${STAGING_DIR}/System/Drivers/Display/"
cp drivers/snd/hda/build/hda_drv.bax "${STAGING_DIR}/System/Drivers/Sound/"
cp services/disp_srv/build/disp_srv.bax "${STAGING_DIR}/System/Drivers/Display/"
cp services/input_srv/build/input_srv.bax "${STAGING_DIR}/System/Drivers/Input/"

# 5. Stage System Applications & CoreUtils
cp apps/gui/sys_mon/build/sys_mon.bax "${STAGING_DIR}/System/Apps/SysMon/"
cp apps/gui/node_viewer/build/node_viewer.bax "${STAGING_DIR}/System/Apps/NodeViewer/"
[ -f "apps/gui/resource_mon/build/res_mon.bax" ] && cp apps/gui/resource_mon/build/res_mon.bax "${STAGING_DIR}/System/Apps/ResMon/"
[ -f "apps/cli/coreutils/ls/build/ls.bax" ] && cp apps/cli/coreutils/ls/build/ls.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/cat/build/cat.bax" ] && cp apps/cli/coreutils/cat/build/cat.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/uptime/build/uptime.bax" ] && cp apps/cli/coreutils/uptime/build/uptime.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/ver/build/ver.bax" ] && cp apps/cli/coreutils/ver/build/ver.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/echo/build/echo.bax" ] && cp apps/cli/coreutils/echo/build/echo.bax "${STAGING_DIR}/System/Apps/CoreUtils/"

# 6. Stage User Applications
cp apps/gui/terminal/build/terminal.bax "${STAGING_DIR}/Apps/Terminal/"
cp apps/gui/user_app/build/user_app.bax "${STAGING_DIR}/Apps/UserApp/"
[ -f "apps/gui/gl_demo/build/gl_demo.bax" ] && cp apps/gui/gl_demo/build/gl_demo.bax "${STAGING_DIR}/Apps/GlDemo/"
if [ -f "apps/gui/doom/build/doom.bax" ]; then
    cp apps/gui/doom/build/doom.bax "${STAGING_DIR}/Apps/Doom/"
fi
if [ -f "apps/gui/doom/DOOM1.WAD" ]; then
    cp apps/gui/doom/DOOM1.WAD "${STAGING_DIR}/Apps/Doom/"
fi

mkdir -p build
tar -cf build/initrd.tar -C "${STAGING_DIR}" .
echo "[+] Packed build/initrd.tar successfully."

