# PROS DOOM Port

## Overview
This directory contains the port of Classic DOOM (DOOMgeneric / Chocolate DOOM core) running natively on Personal Research Operating System (PROS / PRK-OS).

## Architecture
- **Engine Core (`c_src/doomgeneric/`):** Pure ANSI C game logic compiled with Clang into a static library (`libdoomgeneric.a`).
- **Platform Layer (`DoomMain.bas`):** Native Low-Level Basic application that initializes the DOOM window via `WmCreateWindow`, manages frame timing (`GetUptime`), and streams double-buffered ARGB dirty rectangles via `WmSignalDirty`.
- **Input Pipeline:** Events are non-blockingly consumed from the Window Manager via `WmPollEvent(g_winId, inEvt)` using shared memory queues.
- **Key Rollover & Movement:** The bridge receives discrete `EVENT_KEY_DOWN` and `EVENT_KEY_UP` events, maintaining continuous player momentum across 35 Hz tics without typematic delay.

## Default Controls
| Key | Action |
|:---|:---|
| **W / Up Arrow** | Move Forward |
| **S / Down Arrow** | Move Backward |
| **A / Left Arrow** | Turn Left |
| **D / Right Arrow** | Turn Right |
| **Ctrl** | Fire Weapon |
| **Space** | Open Doors / Activate Switches |
| **1 – 7** | Switch Weapons |
| **Enter** | Menu Select / Confirm |
| **Escape** | Pause / Toggle Menu |
| **Tab** | Automap |
| **Shift** | Run |

## Building
DOOM is built automatically as part of the system build pipeline:
```bash
bash tools/rebuild_all.sh
```
Or built individually via `apps/gui/doom/build_libdoom.sh`.

