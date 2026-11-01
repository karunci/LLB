import socket
import subprocess
import time
import os

log_file = open('shell_test.log', 'w')
proc = subprocess.Popen([
    'qemu-system-x86_64',
    '-cdrom', 'kernel/build/kernel.iso',
    '-smp', '4',
    '-m', '1G',
    '-display', 'none',
    '-serial', 'stdio',
    '-monitor', 'tcp:127.0.0.1:44459,server,nowait',
    '-no-reboot'
], stdout=log_file, stderr=subprocess.STDOUT)

print('[*] Waiting 35s for VM boot...')
time.sleep(35)

try:
    s = socket.socket()
    s.settimeout(10.0)
    s.connect(('127.0.0.1', 44459))
    time.sleep(1)
    banner = s.recv(1024).decode()
    print('[*] Connected to monitor:', repr(banner[:30]))

    def send_cmd(cmd_str):
        print(f'[*] Typing command: {cmd_str}')
        for ch in cmd_str:
            if ch == ' ':
                k = 'spc'
            elif ch == '.':
                k = 'dot'
            elif ch == '/':
                k = 'slash'
            elif ch == '\\':
                k = 'backslash'
            elif ch == ':':
                k = 'shift-semicolon'
            elif ch == '-':
                k = 'minus'
            elif ch == '_':
                k = 'shift-minus'
            elif ch.isupper():
                k = 'shift-' + ch.lower()
            else:
                k = ch
            s.sendall(f'sendkey {k}\n'.encode())
            time.sleep(0.3)
            s.recv(1024)
        s.sendall(b'sendkey ret\n')
        time.sleep(1.0)
        s.recv(1024)

    send_cmd('ver')
    time.sleep(3)

    send_cmd('dir')
    time.sleep(5)

    send_cmd('cd System\\Configurations')
    time.sleep(4)

    send_cmd('ls')
    time.sleep(4)

    send_cmd('cat environment.cfg')
    time.sleep(4)

    print('[*] Capturing screendump...')
    s.sendall(b'screendump shell_test.ppm\n')
    time.sleep(2)
    s.recv(1024)
    s.close()
    print('[+] Commands sent and screendump saved successfully!')
except Exception as e:
    print('[-] Error:', e)
finally:
    proc.terminate()
    proc.wait()
    log_file.close()

os.system('python3 tools/ppm_to_png.py shell_test.ppm shell_test.png')
