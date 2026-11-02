$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$isoPath = "T:\projects\LLB\pros\kernel\build\kernel.iso"
$logPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\scratch\boot_enter_test.log"
if (Test-Path $logPath) { Remove-Item $logPath -Force }

$p = Start-Process -FilePath $qemuPath -ArgumentList "-cdrom `"$isoPath`" -smp 4 -m 1G -display none -serial file:`"$logPath`" -monitor telnet:127.0.0.1:44446,server,nowait -no-reboot" -PassThru

# Wait 25 seconds for DOOM to fully load
Start-Sleep -Seconds 25

try {
    $client = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 44446)
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
    Start-Sleep -Seconds 4

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

if (Test-Path $logPath) {
    Get-Content $logPath | Select-String -Pattern "DOOM|doom|PLEXUS|WARN|SCHED|FAULT|P_SetupLevel|P_Init|Z_Malloc|I_Error" | Select-Object -Last 40
}

