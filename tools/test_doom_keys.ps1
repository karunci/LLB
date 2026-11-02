$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$isoPath = "T:\projects\LLB\pros\kernel\build\kernel.iso"
$logPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\scratch\qemu_doom_test.log"

if (Test-Path $logPath) { Remove-Item $logPath -Force }

Write-Host "[*] Launching QEMU with telnet monitor..."
$p = Start-Process -FilePath $qemuPath -ArgumentList "-cdrom `"$isoPath`" -smp 4 -m 1G -display none -serial file:`"$logPath`" -monitor telnet:127.0.0.1:44445,server,nowait -no-reboot" -PassThru

Write-Host "[*] Waiting 10 seconds for boot..."
Start-Sleep -Seconds 10

try {
    $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 44445)
    $writer = New-Object System.IO.StreamWriter($client.GetStream())
    $writer.AutoFlush = $true
    Start-Sleep -Seconds 1

    Write-Host "[*] Sending Enter (New Game)..."
    $writer.WriteLine("sendkey ret")
    Start-Sleep -Seconds 2

    Write-Host "[*] Sending Enter (Episode 1)..."
    $writer.WriteLine("sendkey ret")
    Start-Sleep -Seconds 2

    Write-Host "[*] Sending Enter (Skill 3)..."
    $writer.WriteLine("sendkey ret")
    Start-Sleep -Seconds 3

    $writer.WriteLine("quit")
    $client.Close()
    Write-Host "[+] Finished sending keys."
} catch {
    Write-Host "[-] Telnet monitor error: $_"
}

Start-Sleep -Seconds 1
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force
}

Write-Host "[*] QEMU finished. Inspecting log..."
Get-Content $logPath | Select-String -Pattern "DOOM|P_SetupLevel|P_Init|Plexus|WARN|FAULT|PANIC|Exception|Spawned" | Select-Object -Last 40

