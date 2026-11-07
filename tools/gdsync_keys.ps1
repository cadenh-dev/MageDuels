$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$secretDir = Join-Path $env:USERPROFILE '.shiftcast\gdsync'
$publicPath = Join-Path $secretDir 'public_key'
$privatePath = Join-Path $secretDir 'private_key'
$outputPath = Join-Path $root 'addons\GD-Sync\keys.cfg'

$ignorePath = 'addons/GD-Sync/keys.cfg'
git -C $root check-ignore --quiet $ignorePath
if ($LASTEXITCODE -ne 0) {
	throw 'GD-Sync keys.cfg is not ignored. Add it to .gitignore before generating keys.'
}
if (-not (Test-Path -LiteralPath $publicPath -PathType Leaf) -or -not (Test-Path -LiteralPath $privatePath -PathType Leaf)) {
	throw 'GD-Sync key source files are missing.'
}

$publicKey = [System.IO.File]::ReadAllText($publicPath)
$privateKey = [System.IO.File]::ReadAllText($privatePath)
if ($publicKey.Length -ne 16 -or $privateKey.Length -ne 16) {
	throw 'GD-Sync key files must each contain exactly 16 characters with no newline.'
}

$quote = [string][char]34
$contents = "[keys]`r`npublicKey=$quote$publicKey$quote`r`nprivateKey=$quote$privateKey$quote`r`n"
[System.IO.File]::WriteAllText($outputPath, $contents, [System.Text.UTF8Encoding]::new($false))
Remove-Variable publicKey, privateKey, contents
