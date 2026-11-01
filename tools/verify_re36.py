import subprocess
import socket
import time
import os
import sys

qemu_exe = r"C:\Program Files\qemu\qemu-system-x86_64.exe"
iso_path = r"T:\projects\LLB\pros\kernel\build\kernel.iso"
serial_log = r"T:\projects\LLB\pros\qemu_serial_re36.log"
output_dir = r"C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649"

if os.path.exists(serial_log):
    try:
        os.remove(serial_log)
    except Exception:
        pass

# Boot with QEMU WHPX mode and -vga vmware (or standard VGA)
cmd = [
    qemu_exe,
    "-cdrom", iso_path,
    "-smp", "4",
    "-m", "1G",
    "-accel", "whpx",
    "-vga", "vmware",
    "-display", "none",
    "-serial", f"file:{serial_log}",
    "-monitor", "tcp:127.0.0.1:55558,server,nowait",
    "-no-reboot"
]

print("[TEST] Launching QEMU WHPX mode with VMware SVGA-II controller...")
proc = subprocess.Popen(cmd)

sock = None
for _ in range(30):
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 55558))
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
baseline_ppm = os.path.join(output_dir, "desktop_re36_baseline.ppm")
send_mon(f"screendump {baseline_ppm}")
print(f"[TEST] Baseline screendump requested -> {baseline_ppm}")
time.sleep(1)

# Check serial log for SVGA initialization
if os.path.exists(serial_log):
    with open(serial_log, "r", errors="ignore") as f:
        print("[TEST] Serial output snippet:")
        lines = f.readlines()
        for line in lines[-25:]:
            print("  ", line.strip())

send_mon("quit")
time.sleep(0.5)
sock.close()
proc.kill()
print("[TEST] QEMU WHPX test finished.")

