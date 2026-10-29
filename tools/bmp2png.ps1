Add-Type -AssemblyName System.Drawing
$bmpFile = "T:\projects\LLB\pros\desktop.bmp"
$pngFile = "T:\projects\LLB\pros\docs\desktop_verified.png"
if (Test-Path $bmpFile) {
    $img = [System.Drawing.Bitmap]::FromFile($bmpFile)
    $img.Save($pngFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()
    Write-Host "[+] Converted desktop.bmp -> docs/desktop_verified.png"
} else {
    Write-Host "[-] desktop.bmp not found"
}
