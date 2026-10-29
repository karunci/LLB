#!/bin/bash
set -e
STAGING_DIR="build/initrd_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/System/Servers"
mkdir -p "${STAGING_DIR}/System/Libraries"
mkdir -p "${STAGING_DIR}/System/Configs"
mkdir -p "${STAGING_DIR}/Apps/UserApp"
mkdir -p "${STAGING_DIR}/Users/Default"

cp services/genesis/build/genesis.bax "${STAGING_DIR}/System/Servers/"
cp services/disp_srv/build/disp_srv.bax "${STAGING_DIR}/System/Servers/"
cp services/input_srv/build/input_srv.bax "${STAGING_DIR}/System/Servers/"
cp services/compositor/build/compositor.bax "${STAGING_DIR}/System/Servers/"
cp services/dev_mgr/build/dev_mgr.bax "${STAGING_DIR}/System/Servers/"
cp services/plexus_mgr/build/plexus_mgr.bax "${STAGING_DIR}/System/Servers/"
cp services/wm/build/wm.bax "${STAGING_DIR}/System/Servers/"
cp services/vfs_srv/build/vfs_srv.bax "${STAGING_DIR}/System/Servers/"
cp apps/gui/sys_mon/build/sys_mon.bax "${STAGING_DIR}/System/Servers/"
cp apps/gui/terminal/build/terminal.bax "${STAGING_DIR}/System/Servers/"
cp apps/gui/node_viewer/build/node_viewer.bax "${STAGING_DIR}/System/Servers/"
cp apps/gui/user_app/build/user_app.bax "${STAGING_DIR}/Apps/UserApp/"

cp "${STAGING_DIR}/System/Servers/"*.bax "${STAGING_DIR}/"
cp "${STAGING_DIR}/Apps/UserApp/user_app.bax" "${STAGING_DIR}/"

mkdir -p build
tar -cf build/initrd.tar -C "${STAGING_DIR}" .
echo "[+] Packed build/initrd.tar successfully."
