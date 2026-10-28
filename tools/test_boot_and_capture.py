import subprocess
import socket
import time
import os

qemu_exe = r"C:\Program Files\qemu\qemu-system-x86_64.exe"
iso_path = r"T:\projects\LLB\llbc\tests\kernel\build\kernel.iso"
serial_log = r"T:\projects\LLB\llbc\qemu_serial.log"

if os.path.exists(serial_log):
    os.remove(serial_log)

cmd = [
    qemu_exe,
    "-cdrom", iso_path,
    "-smp", "4",
    "-m", "1G",
    "-display", "none",
    "-serial", f"file:{serial_log}",
    "-monitor", "tcp:127.0.0.1:55555,server,nowait",
    "-no-reboot"
]

print("Starting QEMU...")
proc = subprocess.Popen(cmd)

sock = None
for _ in range(30):
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 55555))
        sock = s
        print("Connected to QEMU monitor!")
        break
    except Exception:
        pass

if not sock:
    print("Failed to connect to QEMU monitor.")
    proc.kill()
    exit(1)

print("Waiting for compositor and all services to fully settle...")
deadline = time.time() + 30
while time.time() < deadline:
    time.sleep(0.5)
    if os.path.exists(serial_log):
        with open(serial_log, "r", errors="ignore") as f:
            content = f.read()
            if "Active execution: 5/10 seconds" in content:
                print("Desktop fully settled (5s liveness verified)!")
                break

time.sleep(1)
sock.sendall(b"screendump desktop_settled.ppm\n")
time.sleep(0.5)

# Initial cursor is at (512, 384).
# Window 3 titlebar is at (250, 150): dx = 250 - 512 = -262, dy = 150 - 384 = -234.
print("Moving to window titlebar (250, 150)...")
sock.sendall(b"mouse_move -262 -234\n")
time.sleep(0.5)

# Press left button to start dragging
print("Pressing mouse button down...")
sock.sendall(b"mouse_button 1\n")
time.sleep(0.2)

# Drag window in steps: dx=20, dy=15 each step
print("Dragging window...")
for i in range(10):
    sock.sendall(b"mouse_move 20 15\n")
    time.sleep(0.1)

# Capture during drag
sock.sendall(b"screendump desktop_dragging.ppm\n")
time.sleep(0.5)

# Release button
print("Releasing mouse button...")
sock.sendall(b"mouse_button 0\n")
time.sleep(1)

sock.sendall(b"screendump desktop_released.ppm\n")
time.sleep(1)
sock.sendall(b"quit\n")
time.sleep(1)
sock.close()
proc.kill()
print("Done!")
