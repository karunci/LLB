#!/bin/bash
set -e
PROS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LLBC="${PROS_ROOT}/../llbc/build/llbc-stage0"
cd "${PROS_ROOT}"

echo "=== 1. Building Libraries ==="
(cd lib/metal && "${LLBC}" Metal.llbproj)
(cd lib/pros && "${LLBC}" Pros.llbproj)

echo "=== 2. Building Services ==="
(cd services/genesis && "${LLBC}" Genesis.llbproj)
(cd services/disp_srv && "${LLBC}" DispService.llbproj)
(cd services/input_srv && "${LLBC}" InputService.llbproj)
(cd services/compositor && "${LLBC}" Compositor.llbproj)
(cd services/dev_mgr && "${LLBC}" DevMgr.llbproj)
(cd services/plexus_mgr && "${LLBC}" PlexusMgr.llbproj)
(cd services/wm && "${LLBC}" WmService.llbproj)
(cd services/vfs_srv && "${LLBC}" VfsService.llbproj)
(cd services/ramfs_srv && "${LLBC}" Ramfs.llbproj)

echo "=== 3. Building CoreUtils & GUI Apps ==="
(cd apps/cli/coreutils/ls && "${LLBC}" Ls.llbproj)
(cd apps/cli/coreutils/cat && "${LLBC}" Cat.llbproj)
(cd apps/cli/coreutils/uptime && "${LLBC}" Uptime.llbproj)
(cd apps/cli/coreutils/ver && "${LLBC}" Ver.llbproj)
(cd apps/cli/coreutils/echo && "${LLBC}" Echo.llbproj)
(cd apps/gui/sys_mon && "${LLBC}" SysMon.llbproj)
(cd apps/gui/terminal && "${LLBC}" Terminal.llbproj)
(cd apps/gui/node_viewer && "${LLBC}" NodeViewer.llbproj)
(cd apps/gui/user_app && "${LLBC}" UserApp.llbproj)

echo "=== 4. Packing initrd.tar ==="
bash ./tools/pack_initrd.sh

echo "=== 5. Building Kernel ==="
(cd kernel && "${LLBC}" Kernel_MB2.llbproj)

echo "=== 6. Building Bootable ISO ==="
bash ./kernel/scripts/build_iso.sh

echo "=== BUILD COMPLETE ==="

