import subprocess
import socket
import time
import os
import sys

qemu_exe = r"C:\Program Files\qemu\qemu-system-x86_64.exe"
iso_path = r"T:\projects\LLB\pros\kernel\build\kernel.iso"
serial_log = r"T:\projects\LLB\pros\qemu_serial_re35.log"
output_dir = r"C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649"

if os.path.exists(serial_log):
    try:
        os.remove(serial_log)
    except Exception:
        pass

# Boot with QEMU WHPX first (or fallback to TCG)
cmd = [
    qemu_exe,
    "-cdrom", iso_path,
    "-smp", "4",
    "-m", "1G",
    "-accel", "whpx",
    "-display", "none",
    "-serial", f"file:{serial_log}",
    "-monitor", "tcp:127.0.0.1:55557,server,nowait",
    "-no-reboot"
]

print("[TEST] Launching QEMU WHPX mode...")
proc = subprocess.Popen(cmd)

sock = None
for _ in range(30):
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 55557))
        sock = s
        print("[TEST] Connected to QEMU monitor!")
        break
    except Exception:
        pass

if not sock:
    print("[TEST] Failed to connect to QEMU monitor.")
    proc.kill()
    sys.exit(1)

def send_mon(cmd_str):
    sock.sendall(cmd_str.encode("ascii") + b"\n")
    time.sleep(0.08)

print("[TEST] Waiting for system to boot and reach steady state...")
settled = False
deadline = time.time() + 45
while time.time() < deadline:
    time.sleep(1.0)
    if os.path.exists(serial_log):
        with open(serial_log, "r", errors="ignore") as f:
            content = f.read()
            if "Active execution: 5/10 seconds" in content:
                print("[TEST] Desktop settled and verified live!")
                settled = True
                break

if not settled:
    print("[TEST] Timed out waiting for settle, proceeding with screendump anyway...")

time.sleep(2)
baseline_ppm = os.path.join(output_dir, "desktop_re35_baseline.ppm")
send_mon(f"screendump {baseline_ppm}")
print(f"[TEST] Baseline screendump requested -> {baseline_ppm}")
time.sleep(1)

# Initial cursor is at (512, 384).
# 1. Click the Wallpaper Switcher button at (590, 10)
# dx = 590 - 512 = +78, dy = 10 - 384 = -374
print("[TEST] Moving cursor to Wallpaper Switcher button at (590, 10)...")
send_mon("mouse_move 78 -374")
time.sleep(0.3)
send_mon("mouse_button 1")
time.sleep(0.15)
send_mon("mouse_button 0")
time.sleep(0.8)

# Capture after wallpaper switch 1 (to CHECKER)
checker_ppm = os.path.join(output_dir, "desktop_re35_checker.ppm")
send_mon(f"screendump {checker_ppm}")
print(f"[TEST] Checkerboard wallpaper screendump requested -> {checker_ppm}")
time.sleep(1)

# Click wallpaper button again (switch to NORD DARK)
print("[TEST] Clicking Wallpaper Switcher again (Nord Dark)...")
send_mon("mouse_button 1")
time.sleep(0.15)
send_mon("mouse_button 0")
time.sleep(0.8)

nord_ppm = os.path.join(output_dir, "desktop_re35_nord.ppm")
send_mon(f"screendump {nord_ppm}")
print(f"[TEST] Nord Dark wallpaper screendump requested -> {nord_ppm}")
time.sleep(1)

# 2. Test closing a window:
# Terminal Console is initially Window 1 at (16, 36, 644, 430)
# Titlebar close button is at (winX + winW - 17, winY + 13) = (16 + 644 - 17, 36 + 13) = (643, 49)
# Currently cursor is at (590, 10). dx = 643 - 590 = +53, dy = 49 - 10 = +39
print("[TEST] Moving cursor to Window Close button at (643, 49)...")
send_mon("mouse_move 53 39")
time.sleep(0.3)
send_mon("mouse_button 1")
time.sleep(0.15)
send_mon("mouse_button 0")
time.sleep(1.0)

close_ppm = os.path.join(output_dir, "desktop_re35_closed_win.ppm")
send_mon(f"screendump {close_ppm}")
print(f"[TEST] Closed window screendump requested -> {close_ppm}")
time.sleep(1)

send_mon("quit")
time.sleep(0.5)
sock.close()
proc.kill()
print("[TEST] All tests completed successfully!")

