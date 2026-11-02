# Export SHIFTCAST for the Web (itch.io-friendly, single-threaded).
$ErrorActionPreference = "Stop"

$Godot = "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$Templates = "$env:APPDATA\Godot\export_templates\4.7.2.stable"
$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root "build"
$OutFile = Join-Path $OutDir "web\index.html"

if (-not (Test-Path $Godot)) { throw "Godot binary not found: $Godot" }
if (-not (Test-Path $Templates)) { throw "Export templates missing: $Templates" }
$required = @("web_nothreads_release.zip")
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $Templates $f))) { throw "Missing template file: $f" }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# Clean previous output
Get-ChildItem -Path $OutDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
# Godot will not create a missing target folder; recreate it after the clean.
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "web") | Out-Null

& $Godot --headless --path $Root --export-release "Web" $OutFile
if ($LASTEXITCODE -ne 0) { throw "Godot export failed with exit code $LASTEXITCODE" }

Write-Host "Export complete: $OutFile"
Get-ChildItem -Path $OutDir -Recurse -File | Measure-Object -Property Length -Sum | ForEach-Object {
    Write-Host ("Bundle size: {0:N2} MB" -f ($_.Sum / 1MB))
}
