<#
.SYNOPSIS
    Bumps the version in package.json and builds a new
    kobixel-X.Y.Z.aseprite-extension, removing old builds.

.USAGE
    .\release.ps1                # bumps the patch version (0.1.0 -> 0.1.1)
    .\release.ps1 -Bump minor    # 0.1.0 -> 0.2.0
    .\release.ps1 -Bump major    # 0.1.0 -> 1.0.0
#>
param(
    [ValidateSet("major", "minor", "patch")]
    [string]$Bump = "patch"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$pkgPath = "package.json"
$content = Get-Content $pkgPath -Raw -Encoding UTF8
$match = [regex]::Match($content, '"version":\s*"(\d+)\.(\d+)\.(\d+)"')
if (-not $match.Success) {
    throw "Could not find a `"version`": `"X.Y.Z`" field in $pkgPath"
}

[int]$majorNum = $match.Groups[1].Value
[int]$minorNum = $match.Groups[2].Value
[int]$patchNum = $match.Groups[3].Value

switch ($Bump) {
    "major" { $majorNum++; $minorNum = 0; $patchNum = 0 }
    "minor" { $minorNum++; $patchNum = 0 }
    "patch" { $patchNum++ }
}
$newVersion = "$majorNum.$minorNum.$patchNum"

# Regex replace in place instead of ConvertFrom-Json/ConvertTo-Json, so the
# rest of package.json's formatting (key order, spacing) doesn't get
# reshuffled by a JSON round-trip.
$newContent = $content -replace '"version":\s*"\d+\.\d+\.\d+"', "`"version`": `"$newVersion`""
# Set-Content -Encoding utf8 writes a BOM in Windows PowerShell 5.1, and
# Aseprite's JSON parser chokes on it ("error parsing json file: expected
# value, got (-17)" - -17 is the signed byte value of the BOM's first byte,
# 0xEF). Write via .NET directly with a BOM-less UTF8Encoding instead.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $pkgPath), $newContent, $utf8NoBom)

Remove-Item -Force -ErrorAction SilentlyContinue kobixel-*.aseprite-extension
$zipPath = "kobixel-$newVersion.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $zipPath
Compress-Archive -Path package.json, kobixel.lua -DestinationPath $zipPath -CompressionLevel Optimal
$extPath = "kobixel-$newVersion.aseprite-extension"
Rename-Item $zipPath $extPath -Force

Write-Output "Built $extPath (version $newVersion)"
Write-Output "Next: install it in Aseprite (Edit > Preferences > Extensions > Add Extension), remove the old version first, restart Aseprite."
