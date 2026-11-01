import subprocess
import socket
import time
import os
import sys
import zlib
import struct

qemu_exe = r"C:\Program Files\qemu\qemu-system-x86_64.exe"
iso_path = r"T:\projects\LLB\pros\kernel\build\kernel.iso"
serial_log = r"T:\projects\LLB\pros\qemu_serial_re37.log"
output_dir = r"C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649"

if os.path.exists(serial_log):
    try:
        os.remove(serial_log)
    except Exception:
        pass

def ppm_to_png(ppm_path, png_path):
    with open(ppm_path, 'rb') as f:
        header = f.readline().strip()
        if header != b'P6':
            raise ValueError('Not a P6 PPM')
        line = f.readline()
        while line.startswith(b'#'):
            line = f.readline()
        width, height = map(int, line.split())
        maxval = int(f.readline().strip())
        data = f.read()

    raw_data = bytearray()
    row_bytes = width * 3
    for y in range(height):
        raw_data.append(0) # filter byte: None
        raw_data.extend(data[y*row_bytes:(y+1)*row_bytes])

    compressed = zlib.compress(bytes(raw_data))

    def chunk(tag, chunk_data):
        return struct.pack('>I', len(chunk_data)) + tag + chunk_data + struct.pack('>I', zlib.crc32(tag + chunk_data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', compressed)
    png += chunk(b'IEND', b'')

    with open(png_path, 'wb') as f:
        f.write(png)
    print(f"[CONVERT] Successfully converted {ppm_path} -> {png_path} ({width}x{height})")

cmd = [
    qemu_exe,
    "-cdrom", iso_path,
    "-smp", "4",
    "-m", "1G",
    "-accel", "whpx",
    "-vga", "vmware",
    "-display", "none",
    "-serial", f"file:{serial_log}",
    "-monitor", "tcp:127.0.0.1:55559,server,nowait",
    "-no-reboot"
]

print("[TEST] Launching QEMU WHPX mode with VMware SVGA-II acceleration...")
proc = subprocess.Popen(cmd)

sock = None
for _ in range(30):
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("127.0.0.1", 55559))
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
    time.sleep(0.1)

print("[TEST] Waiting for system to boot and reach steady state...")
settled = False
deadline = time.time() + 65
while time.time() < deadline:
    time.sleep(1.0)
    if os.path.exists(serial_log):
        with open(serial_log, "r", errors="ignore") as f:
            content = f.read()
            if "Active execution: 6/10 seconds" in content:
                print("[TEST] Desktop settled and verified live!")
                settled = True
                break

if not settled:
    print("[TEST] Timed out waiting for settle, proceeding with screendump anyway...")

time.sleep(2)
svga_ppm = os.path.join(output_dir, "desktop_re37_svga.ppm")
send_mon(f"screendump {svga_ppm}")
print(f"[TEST] SVGA screendump requested -> {svga_ppm}")
time.sleep(1.5)

send_mon("quit")
time.sleep(0.5)
sock.close()
proc.kill()
print("[TEST] QEMU WHPX test finished.")

if os.path.exists(svga_ppm):
    svga_png = os.path.join(output_dir, "desktop_re37_svga.png")
    ppm_to_png(svga_ppm, svga_png)

# Inspect serial log
if os.path.exists(serial_log):
    with open(serial_log, "r", errors="ignore") as f:
        print("\n[TEST] Serial Log Summary:")
        lines = f.readlines()
        for line in lines:
            if any(k in line for k in ["[SVGA]", "[COMPOSITOR]", "[CPU FAULT]", "[RES_MON]", "apps.res_mon", "REV:"]):
                print("  ", line.strip())
