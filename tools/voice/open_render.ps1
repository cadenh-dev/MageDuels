# Open the SHIFTCAST chant project in OpenUTAU for rendering.
$ErrorActionPreference = "Stop"

$OpenUtau = Join-Path $env:USERPROFILE "Apps\OpenUtau\OpenUtau.exe"
$Project = Join-Path $PSScriptRoot "chant_demo.ust"

if (-not (Test-Path $OpenUtau)) {
    throw "OpenUTAU not found at $OpenUtau. Install the portable build or update this path."
}
if (-not (Test-Path $Project)) {
    throw "Starter project not found at $Project."
}

Start-Process -FilePath $OpenUtau -ArgumentList "`"$Project`""
Write-Host "Opened chant_demo.ust in OpenUTAU."
Write-Host "Select the Tsukuyomi-chan singer, then File -> Export Audio -> Export Wav Files."
Write-Host "Credit: Tsukuyomi-chan UTAU Voicebank (CV. Rei Yumesaki) - https://tyc.rei-yumesaki.net/material/utau/"
Write-Host "Do not commit or redistribute the voicebank files."
