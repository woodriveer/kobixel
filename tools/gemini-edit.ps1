<#
.SYNOPSIS
    CLI wrapper around the `gemini` CLI + nanobanana extension, for the
    Aseprite "Gemini Edit" extension.

.DESCRIPTION
    Reuses your existing `gemini` CLI login instead of a separate API key
    for Gemini itself (the nanobanana extension still needs its own key,
    see setup below).

    The official gemini CLI + nanobanana extension always writes to
    ./nanobanana-output/ with a name derived from the prompt, so the exact
    output path is unpredictable. This script runs the CLI inside a fresh,
    isolated temp directory and moves the newest PNG it produced to
    -OutPath, hiding that detail from the caller.

.SETUP
    gemini extensions install https://github.com/gemini-cli-extensions/nanobanana
    setx NANOBANANA_API_KEY "your-api-key-here"   # https://aistudio.google.com/apikey

.USAGE
    Matches the extension's {input}/{output}/{prompt} placeholders:
    powershell -ExecutionPolicy Bypass -File gemini-edit.ps1 -InPath "{input}" -OutPath "{output}" -Prompt "{prompt}"
#>
param(
    [Parameter(Mandatory = $true)][string]$InPath,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][string]$Prompt
)

$ErrorActionPreference = "Stop"

$PixelArtInstructions = "This is pixel art. Preserve the exact pixel grid: no anti-aliasing, no smoothing, no gradients, no blur. Use flat, solid colors only. Keep the transparent background transparent. Keep the same image dimensions and canvas framing."

$resolvedIn = (Resolve-Path -LiteralPath $InPath).Path
$fullPrompt = "$Prompt`n`n$PixelArtInstructions"

$workDir = Join-Path $env:TEMP ("gemini-edit-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workDir | Out-Null

try {
    Push-Location $workDir
    try {
        # /edit is a nanobanana slash command; --yolo auto-approves the
        # extension's file-write tool call so this can run unattended.
        & gemini --yolo -p "/edit `"$resolvedIn`" `"$fullPrompt`""
        if ($LASTEXITCODE -ne 0) {
            throw "gemini CLI exited with code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $outputDir = Join-Path $workDir "nanobanana-output"
    if (-not (Test-Path $outputDir)) {
        throw "gemini/nanobanana produced no output directory: $outputDir"
    }

    $latest = Get-ChildItem -Path $outputDir -Filter *.png |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No PNG found in $outputDir"
    }

    Move-Item -Force -LiteralPath $latest.FullName -Destination $OutPath
    Write-Output "Wrote $OutPath"
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $workDir -ErrorAction SilentlyContinue
}
