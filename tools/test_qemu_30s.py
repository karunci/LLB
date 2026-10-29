#!/usr/bin/env python3
import subprocess
import time
import socket
import sys
import os

def ppm_to_bmp(ppm_path, bmp_path):
    with open(ppm_path, 'rb') as f:
        magic = f.readline().strip()
        line = f.readline()
        while line.startswith(b'#'):
            line = f.readline()
        w, h = map(int, line.split())
        maxval = int(f.readline().strip())
        rgb_data = f.read()

    row_size = w * 3
    padding = (4 - (row_size % 4)) % 4
    file_size = 54 + (row_size + padding) * h

    hdr = bytearray(54)
    hdr[0:2] = b'BM'
    hdr[2:6] = file_size.to_bytes(4, 'little')
    hdr[10:14] = (54).to_bytes(4, 'little')
    hdr[14:18] = (40).to_bytes(4, 'little')
    hdr[18:22] = w.to_bytes(4, 'little')
    hdr[22:26] = h.to_bytes(4, 'little')
    hdr[26:28] = (1).to_bytes(2, 'little')
    hdr[28:30] = (24).to_bytes(2, 'little')

    with open(bmp_path, 'wb') as out_f:
        out_f.write(hdr)
        for y in range(h - 1, -1, -1):
            row = rgb_data[y * row_size : (y + 1) * row_size]
            bgr_row = bytearray(len(row) + padding)
            for x in range(w):
                bgr_row[x*3] = row[x*3 + 2]     # B
                bgr_row[x*3 + 1] = row[x*3 + 1] # G
                bgr_row[x*3 + 2] = row[x*3]     # R
            out_f.write(bgr_row)
    print(f"[+] Converted {ppm_path} ({w}x{h}) -> {bmp_path}")

def main():
    iso_path = "kernel/build/kernel.iso"
    if not os.path.exists(iso_path):
        print(f"Error: {iso_path} does not exist!")
        sys.exit(1)

    log_file = open("qemu_run.log", "w")
    monitor_port = 44445

    cmd = [
        "qemu-system-x86_64",
        "-cdrom", iso_path,
        "-smp", "4",
        "-m", "1G",
        "-display", "none",
        "-serial", "stdio",
        "-monitor", f"tcp:127.0.0.1:{monitor_port},server,nowait",
        "-no-reboot"
    ]

    print("[*] Launching QEMU (SMP 4, 1G RAM)...")
    proc = subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT)

    total_duration = 50  # Minimum 30 seconds
    print(f"[*] Running QEMU test for {total_duration} seconds...")

    # Wait 40 seconds for full system bring-up before taking screenshot
    time.sleep(40)

    print("[*] Connecting to QEMU monitor to capture desktop screenshot...")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect(("127.0.0.1", monitor_port))
        time.sleep(1)
        # Flush banner
        s.recv(1024)
        # Send screendump command
        dump_cmd = "screendump desktop.ppm\n"
        s.sendall(dump_cmd.encode('utf-8'))
        time.sleep(2)
        s.close()
        print("[+] Screendump command sent to QEMU monitor.")
    except Exception as e:
        print(f"[-] Screendump via monitor failed: {e}")

    # Wait remaining time to reach total duration
    time.sleep(8)

    print("[*] Terminating QEMU process...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    log_file.close()

    # Convert PPM to BMP if generated
    if os.path.exists("desktop.ppm"):
        ppm_to_bmp("desktop.ppm", "desktop.bmp")
    else:
        print("[-] desktop.ppm not found.")

    print("[+] Test run finished.")

if __name__ == "__main__":
    main()
