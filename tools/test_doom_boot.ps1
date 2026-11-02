$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$isoPath = "T:\projects\LLB\pros\kernel\build\kernel.iso"
$logPath = "C:\Users\MSCRUser\.gemini\antigravity\brain\dc2e93cc-93b9-4b3a-bcc6-84d192282649\scratch\boot_50s.log"
if (Test-Path $logPath) { Remove-Item $logPath -Force }

$p = Start-Process -FilePath $qemuPath -ArgumentList "-cdrom `"$isoPath`" -smp 4 -m 1G -display none -serial file:`"$logPath`" -no-reboot" -PassThru
Start-Sleep -Seconds 45
if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force
}
if (Test-Path $logPath) {
    Get-Content $logPath | Select-String -Pattern "PLEXUS|Spawned|exited|Auto-restarting|DOOM" | Select-Object -Last 40
}
