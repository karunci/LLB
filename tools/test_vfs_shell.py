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
    print("[+] Converted PPM -> BMP")

def send_string(sock, s):
    key_map = {
        ' ': 'spc',
        '\n': 'ret',
        '.': 'dot',
        '/': 'slash',
        '\\': 'backslash',
        ':': 'shift-semicolon',
        '-': 'minus',
        '_': 'shift-minus',
        '~': 'shift-grave_accent'
    }
    for ch in s:
        if ch in key_map:
            k = key_map[ch]
        elif ch.isupper():
            k = "shift-" + ch.lower()
        else:
            k = ch
        sock.sendall(("sendkey " + k + "\n").encode('utf-8'))
        time.sleep(0.12)

def main():
    iso_path = "kernel/build/kernel.iso"
    if not os.path.exists(iso_path):
        print("Error: kernel.iso does not exist!")
        sys.exit(1)

    log_file = open("qemu_vfs_run.log", "w")
    monitor_port = 44446

    cmd = [
        "qemu-system-x86_64",
        "-cdrom", iso_path,
        "-smp", "4",
        "-m", "1G",
        "-display", "none",
        "-serial", "stdio",
        "-monitor", "tcp:127.0.0.1:" + str(monitor_port) + ",server,nowait",
        "-no-reboot"
    ]

    print("[*] Launching QEMU...")
    proc = subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT)

    print("[*] Waiting 42s for desktop and terminal bring-up...")
    time.sleep(42)

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(10.0)
        s.connect(("127.0.0.1", monitor_port))
        time.sleep(2)
        s.recv(1024)

        print("[*] Typing: ls")
        send_string(s, "ls\n")
        time.sleep(3)

        print("[*] Typing: cd System")
        send_string(s, "cd System\n")
        time.sleep(3)

        print("[*] Typing: pwd")
        send_string(s, "pwd\n")
        time.sleep(3)

        print("[*] Typing: ls")
        send_string(s, "ls\n")
        time.sleep(3)

        print("[*] Typing: cd ..")
        send_string(s, "cd ..\n")
        time.sleep(3)

        print("[*] Typing: cat System\\Configurations\\environment.cfg")
        send_string(s, "cat System\\Configurations\\environment.cfg\n")
        time.sleep(5)

        print("[*] Screendump...")
        s.sendall(b"screendump desktop_vfs.ppm\n")
        time.sleep(2)
        s.close()
    except Exception as e:
        print("[-] Monitor failed: " + str(e))

    print("[*] Terminating QEMU...")
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    log_file.close()

    if os.path.exists("desktop_vfs.ppm"):
        ppm_to_bmp("desktop_vfs.ppm", "desktop_vfs.bmp")
    print("[+] Test run finished.")

if __name__ == '__main__':
    main()

