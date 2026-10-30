#!/bin/bash
set -e
STAGING_DIR="build/initrd_staging"
rm -rf "${STAGING_DIR}"

# 1. Directory Tree Creation
mkdir -p "${STAGING_DIR}/System/Services/Genesis"
mkdir -p "${STAGING_DIR}/System/Services/Compositor"
mkdir -p "${STAGING_DIR}/System/Services/DevMgr"
mkdir -p "${STAGING_DIR}/System/Services/PlexusMgr"
mkdir -p "${STAGING_DIR}/System/Services/Wm"
mkdir -p "${STAGING_DIR}/System/Services/VfsSrv"
mkdir -p "${STAGING_DIR}/System/Services/RamfsSrv"

mkdir -p "${STAGING_DIR}/System/Drivers/Nodes"
mkdir -p "${STAGING_DIR}/System/Drivers/Display"
mkdir -p "${STAGING_DIR}/System/Drivers/Input"

mkdir -p "${STAGING_DIR}/System/Apps/CoreUtils"
mkdir -p "${STAGING_DIR}/System/Apps/SysMon"
mkdir -p "${STAGING_DIR}/System/Apps/NodeViewer"

mkdir -p "${STAGING_DIR}/System/Libraries"
mkdir -p "${STAGING_DIR}/System/Configurations/Drives"

mkdir -p "${STAGING_DIR}/Apps/Terminal"
mkdir -p "${STAGING_DIR}/Apps/UserApp"
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
cp services/plexus_mgr/build/plexus_mgr.bax "${STAGING_DIR}/System/Services/PlexusMgr/"
cp services/wm/build/wm.bax "${STAGING_DIR}/System/Services/Wm/"
cp services/vfs_srv/build/vfs_srv.bax "${STAGING_DIR}/System/Services/VfsSrv/"
if [ -f "services/ramfs_srv/build/ramfs_srv.bax" ]; then
    cp services/ramfs_srv/build/ramfs_srv.bax "${STAGING_DIR}/System/Services/RamfsSrv/"
fi

# 4. Stage Hardware Driver Daemons
cp services/disp_srv/build/disp_srv.bax "${STAGING_DIR}/System/Drivers/Display/"
cp services/input_srv/build/input_srv.bax "${STAGING_DIR}/System/Drivers/Input/"

# 5. Stage System Applications & CoreUtils
cp apps/gui/sys_mon/build/sys_mon.bax "${STAGING_DIR}/System/Apps/SysMon/"
cp apps/gui/node_viewer/build/node_viewer.bax "${STAGING_DIR}/System/Apps/NodeViewer/"
[ -f "apps/cli/coreutils/ls/build/ls.bax" ] && cp apps/cli/coreutils/ls/build/ls.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/cat/build/cat.bax" ] && cp apps/cli/coreutils/cat/build/cat.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/uptime/build/uptime.bax" ] && cp apps/cli/coreutils/uptime/build/uptime.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/ver/build/ver.bax" ] && cp apps/cli/coreutils/ver/build/ver.bax "${STAGING_DIR}/System/Apps/CoreUtils/"
[ -f "apps/cli/coreutils/echo/build/echo.bax" ] && cp apps/cli/coreutils/echo/build/echo.bax "${STAGING_DIR}/System/Apps/CoreUtils/"

# 6. Stage User Applications
cp apps/gui/terminal/build/terminal.bax "${STAGING_DIR}/Apps/Terminal/"
cp apps/gui/user_app/build/user_app.bax "${STAGING_DIR}/Apps/UserApp/"

mkdir -p build
tar -cf build/initrd.tar -C "${STAGING_DIR}" .
echo "[+] Packed build/initrd.tar successfully."

