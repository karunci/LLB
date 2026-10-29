# Project: PRK (Personal Research Kernel) / Low-Level Basic
# File: tools/run_qemu.ps1
# Description: Deterministic QEMU runner script with hard timeout and early exit detection.

param(
    [string]$Kernel = "T:\projects\LLB\pros\kernel\build\kernel.elf",
    [string]$Initrd = "T:\projects\LLB\pros\build\initrd.tar",
    [int]$Smp = 2,
    [string]$Accel = "whpx",
    [int]$TimeoutSec = 30
)

$qemuPath = "C:\Program Files\qemu\qemu-system-x86_64.exe"
$serialLog = "$env:TEMP\qemu_serial.log"

if (Test-Path $serialLog) { Remove-Item $serialLog -Force -ErrorAction SilentlyContinue }

$argsList = "-kernel `"$Kernel`" -initrd `"$Initrd`" -serial file:`"$serialLog`" -display none -accel $Accel -smp $Smp -cpu Nehalem,+x2apic -M q35 -m 1G --no-reboot"

$proc = Start-Process -FilePath $qemuPath -ArgumentList $argsList -PassThru -NoNewWindow

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline -and !$proc.HasExited) {
    Start-Sleep -Milliseconds 200
    if (Test-Path $serialLog) {
        $content = Get-Content $serialLog -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains("Reaped terminated task")) {
            break
        }
    }
}

if (!$proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

if (Test-Path $serialLog) {
    Get-Content $serialLog
}
