# Remove the local Godot import cache.
# Use after pulling changes that add/remove/ignore asset folders, or if the
# editor crashes before the project opens. Godot rebuilds .godot on next open.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Cache = Join-Path $Root ".godot"

if (Test-Path $Cache) {
    Remove-Item -Path $Cache -Recurse -Force
    Write-Host "Removed $Cache"
} else {
    Write-Host "No .godot cache at $Cache"
}

Write-Host "Reopen the project in Godot. It will reimport fonts, shaders, and scripts."
