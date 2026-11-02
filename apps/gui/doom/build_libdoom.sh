#!/bin/bash
# Project: Personal Research Operating System
# File: apps/gui/doom/build_libdoom.sh
# Description: Compiles freestanding DOOM generic C core and minimal PROS libc
#              into static archive build/libdoomgeneric.a.

set -e
DOOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DOOM_DIR}"
mkdir -p build/objs

CFLAGS="-target x86_64-unknown-none-elf -ffreestanding -nostdlibinc -fno-pie -fno-stack-protector -fcf-protection=none -mno-red-zone -O2 -Wno-everything -DFEATURE_SOUND -D__PROS__ -I c_src/include -I c_src/doomgeneric"

echo "=== 1. Compiling Minimal PROS LibC & Bridge ==="
clang ${CFLAGS} -c c_src/pros_libc.c -o build/objs/pros_libc.o
clang ${CFLAGS} -c c_src/doom_bridge.c -o build/objs/doom_bridge.o

OBJS="build/objs/pros_libc.o build/objs/doom_bridge.o"

echo "=== 2. Compiling DOOMgeneric Core Engine Files ==="
for f in c_src/doomgeneric/*.c; do
    name=$(basename "$f" .c)
    obj="build/objs/${name}.o"
    clang ${CFLAGS} -c "$f" -o "$obj"
    OBJS="${OBJS} ${obj}"
done

echo "=== 3. Creating Static Archive build/libdoomgeneric.a ==="
llvm-ar rcs build/libdoomgeneric.a ${OBJS}
echo "[SUCCESS] Generated build/libdoomgeneric.a ($(ls -lh build/libdoomgeneric.a | awk '{print $5}'))"
