import subprocess
import socket
import time
import os
import sys

qemu_exe = r"C:\Program Files\qemu\qemu-system-x86_64.exe"
iso_path = r"T:\projects\LLB\llbc\tests\kernel\build\kernel.iso"
serial_log = r"T:\projects\LLB\llbc\qemu_serial_adv.log"

if os.path.exists(serial_log):
    try:
        os.remove(serial_log)
    except Exception:
        pass

cmd = [
    qemu_exe,
    "-cdrom", iso_path,
    "-smp", "4",
    "-m", "1G",
    "-display", "none",
    "-serial", f"file:{serial_log}",
    "-monitor", "tcp:127.0.0.1:55556,server,nowait",
    "-no-reboot"
]

print("[ADV] Starting QEMU with SMP 4...")
proc = subprocess.Popen(cmd)

sock = None
for _ in range(30):
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 55556))
        sock = s
        print("[ADV] Connected to QEMU monitor!")
        break
    except Exception:
        pass

if not sock:
    print("[ADV] Failed to connect to QEMU monitor.")
    proc.kill()
    sys.exit(1)

def send_qmp(cmd_str):
    sock.sendall(cmd_str.encode("ascii") + b"\n")
    time.sleep(0.05)

print("[ADV] Waiting for system to settle...")
deadline = time.time() + 50
while time.time() < deadline:
    time.sleep(0.5)
    if os.path.exists(serial_log):
        with open(serial_log, "r", errors="ignore") as f:
            content = f.read()
            if "Active execution: 5/10 seconds" in content:
                print("[ADV] System settled!")
                break

time.sleep(1)
send_qmp("screendump adv_baseline.ppm")
time.sleep(0.5)

# Initial cursor is at center (512, 384).
# Test 1: Drag Window 3 (Terminal, titlebar originally at ~250, 150)
print("[ADV] Step 1: Drag Window 3 across desktop...")
dx = 250 - 512
dy = 150 - 384
send_qmp(f"mouse_move {dx} {dy}")
time.sleep(0.2)
send_qmp("mouse_button 1")
time.sleep(0.1)

# Move diagonally through Window 2 (SysMon)
for _ in range(12):
    send_qmp("mouse_move 25 15")
    time.sleep(0.08)

send_qmp("screendump adv_drag_win3.ppm")
time.sleep(0.2)
send_qmp("mouse_button 0")
time.sleep(0.5)
send_qmp("screendump adv_drop_win3.ppm")
time.sleep(0.5)

# Test 2: Rapid multi-window overlapping drag
# Cursor is currently at: 250 + 12*25 = 550, 150 + 12*15 = 330
# Window 2 (SysMon) titlebar is at (180, 95): dx = 180 - 550 = -370, dy = 95 - 330 = -235
print("[ADV] Step 2: Grab Window 2 and drag over Window 1 and Window 3...")
send_qmp("mouse_move -370 -235")
time.sleep(0.2)
send_qmp("mouse_button 1")
time.sleep(0.1)

# Rapid zig-zag drag across overlapping regions
for _ in range(8):
    send_qmp("mouse_move 30 25")
    time.sleep(0.06)
for _ in range(8):
    send_qmp("mouse_move -20 20")
    time.sleep(0.06)

send_qmp("screendump adv_drag_win2_zigzag.ppm")
time.sleep(0.2)
send_qmp("mouse_button 0")
time.sleep(0.5)
send_qmp("screendump adv_drop_win2.ppm")
time.sleep(0.5)

# Test 3: Screen Boundary Stress Test
# Drag toward left screen edge
print("[ADV] Step 3: Boundary drag test near x=0...")
# Cursor is at: 180 + 8*30 - 8*20 = 260, 95 + 8*25 + 8*20 = 455
# Grab Window 1 (Node Viewer) titlebar at ~ (120, 50): dx = 120 - 260 = -140, dy = 50 - 455 = -405
send_qmp("mouse_move -140 -405")
time.sleep(0.2)
send_qmp("mouse_button 1")
time.sleep(0.1)

# Drag aggressively toward left boundary
for _ in range(15):
    send_qmp("mouse_move -15 10")
    time.sleep(0.06)

send_qmp("screendump adv_drag_boundary.ppm")
time.sleep(0.2)
send_qmp("mouse_button 0")
time.sleep(0.5)
send_qmp("screendump adv_drop_boundary.ppm")
time.sleep(0.5)

send_qmp("quit")
time.sleep(0.5)
sock.close()
proc.kill()
print("[ADV] Test completed successfully!")
