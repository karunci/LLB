$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$isoPath = "T:\projects\LLB\pros\kernel\build\kernel.iso"
$logPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\scratch\test_verified.log"
$screenPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\scratch\screen_verified.ppm"
$pngPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\desktop_re51_verified.png"

if (Test-Path $logPath) { Remove-Item $logPath -Force }
if (Test-Path $screenPath) { Remove-Item $screenPath -Force }

$p = Start-Process -FilePath $qemuPath -ArgumentList "-cdrom `"$isoPath`" -smp 4 -m 1G -display none -serial file:`"$logPath`" -monitor telnet:127.0.0.1:44448,server,nowait -no-reboot" -PassThru
Start-Sleep -Seconds 30

try {
    $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 44448)
    $writer = New-Object System.IO.StreamWriter($client.GetStream())
    $writer.AutoFlush = $true
    Start-Sleep -Seconds 1
    $writer.WriteLine("screendump $screenPath")
    Start-Sleep -Seconds 2
    $writer.WriteLine("quit")
    $client.Close()
    Write-Host "[+] Screendump command sent."
} catch {
    Write-Host "[-] Telnet monitor error: $_"
}

Start-Sleep -Seconds 1
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force
}

if (Test-Path $screenPath) {
    python T:\projects\LLB\pros\tools\ppm_to_png.py $screenPath $pngPath
    Write-Host "[SUCCESS] Converted screenshot to $pngPath"
}

if (Test-Path $logPath) {
    Get-Content $logPath | Select-String -Pattern "PLEXUS|Spawned|exited|DOOM|WARN" | Select-Object -Last 35
}

