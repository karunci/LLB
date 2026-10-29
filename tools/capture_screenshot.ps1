$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$isoPath = "T:\projects\LLB\pros\kernel\build\kernel.iso"
$ppmPath = "T:\projects\LLB\pros\desktop.ppm"
$pngPath = "T:\projects\LLB\pros\docs\desktop_verified.png"

if (Test-Path $ppmPath) { Remove-Item $ppmPath -Force }

Write-Host "[*] Launching QEMU on Windows (WHPX/TCG SMP 4, 1G RAM)..."
$p = Start-Process -FilePath $qemuPath -ArgumentList "-cdrom `"$isoPath`" -smp 4 -m 1G -vga std -display none -monitor telnet:127.0.0.1:44445,server,nowait -serial file:T:\projects\LLB\pros\win_qemu.log -no-reboot" -PassThru

Write-Host "[*] Waiting 42 seconds for full OS boot and desktop composition..."
Start-Sleep -Seconds 42

Write-Host "[*] Connecting to QEMU monitor via Telnet to issue screendump..."
try {
    $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 44445)
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    Start-Sleep -Seconds 1
    $writer.WriteLine("screendump T:\projects\LLB\pros\desktop.ppm")
    Start-Sleep -Seconds 3
    $client.Close()
    Write-Host "[+] Screendump command executed."
} catch {
    Write-Host "[-] Monitor connection error: $_"
}

Start-Sleep -Seconds 2
Stop-Process -Id $p.Id -Force
Write-Host "[*] QEMU stopped."

if (Test-Path $ppmPath) {
    Write-Host "[*] Converting PPM to PNG..."
    python -c "
with open(r'T:\projects\LLB\pros\desktop.ppm', 'rb') as f:
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

bmp_path = r'T:\projects\LLB\pros\desktop.bmp'
with open(bmp_path, 'wb') as out_f:
    out_f.write(hdr)
    for y in range(h - 1, -1, -1):
        row = rgb_data[y * row_size : (y + 1) * row_size]
        bgr_row = bytearray(len(row) + padding)
        for x in range(w):
            bgr_row[x*3] = row[x*3 + 2]
            bgr_row[x*3 + 1] = row[x*3 + 1]
            bgr_row[x*3 + 2] = row[x*3]
        out_f.write(bgr_row)
"
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Image]::FromFile("T:\projects\LLB\pros\desktop.bmp")
    $bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Remove-Item "T:\projects\LLB\pros\desktop.bmp" -Force
    Remove-Item $ppmPath -Force
    Write-Host "[SUCCESS] Verified desktop screenshot saved to $pngPath"
} else {
    Write-Host "[-] desktop.ppm not produced."
}
