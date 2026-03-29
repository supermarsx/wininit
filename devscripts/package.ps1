# ============================================================================
# WinInit DevScript: Packager
# Creates a distributable zip/folder of WinInit ready for deployment
# Usage: .\devscripts\package.ps1 [-OutputDir <path>] [-Version <semver>]
# ============================================================================

param(
    [string]$OutputDir = "$PSScriptRoot\..\dist",
    [string]$Version   = ""
)

$ErrorActionPreference = "Stop"

# Auto-detect version from git tag or use date
if (-not $Version) {
    $gitTag = git describe --tags --abbrev=0 2>$null
    if ($gitTag) {
        $Version = $gitTag -replace "^v", ""
    } else {
        $Version = Get-Date -Format "yyyy.MM.dd"
    }
}

$packageName = "WinInit-$Version"

Write-Host ""
Write-Host "  WinInit Packager" -ForegroundColor Cyan
Write-Host "  ================" -ForegroundColor Cyan
Write-Host "  Version: $Version" -ForegroundColor Gray
Write-Host ""

# --- Run CI first ---
Write-Host "  Running CI checks before packaging..." -ForegroundColor Yellow
& "$PSScriptRoot\ci.ps1" -Quick
if ($LASTEXITCODE -ne 0) {
    Write-Host "  CI checks failed - aborting package" -ForegroundColor Red
    exit 1
}

# --- Create staging directory ---
$stagingDir = Join-Path $env:TEMP "wininit-package-$Version"
if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

Write-Host "  Staging to: $stagingDir" -ForegroundColor DarkGray

# --- Copy files ---
$projectRoot = Resolve-Path "$PSScriptRoot\.."

$filesToInclude = @(
    "launch.bat",
    "init.ps1",
    "lib\common.ps1",
    "modules\*.ps1"
)

foreach ($pattern in $filesToInclude) {
    $source = Join-Path $projectRoot $pattern
    $items = Get-Item $source -ErrorAction SilentlyContinue

    foreach ($item in $items) {
        $relativePath = $item.FullName.Substring($projectRoot.Path.Length + 1)
        $destPath = Join-Path $stagingDir $relativePath
        $destDir = Split-Path $destPath

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $item.FullName -Destination $destPath
        Write-Host "    + $relativePath" -ForegroundColor DarkGray
    }
}

# --- Generate manifest ---
$manifest = @{
    name        = "WinInit"
    version     = $Version
    description = "Windows Initialization & Customization Script"
    created     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    modules     = (Get-ChildItem "$stagingDir\modules\*.ps1" | ForEach-Object { $_.Name })
    fileCount   = (Get-ChildItem $stagingDir -Recurse -File).Count
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $stagingDir "manifest.json") -Encoding UTF8
Write-Host "    + manifest.json" -ForegroundColor DarkGray

# --- Generate README ---
$readme = @"
# WinInit $Version

Windows Initialization & Customization Script.

## Quick Start

1. Double-click ``launch.bat``
2. Accept the UAC prompt
3. Wait for completion
4. Reboot

## Structure

- ``launch.bat`` -- One-click launcher (auto-elevates)
- ``init.ps1`` -- Orchestrator
- ``lib\common.ps1`` -- Shared functions
- ``modules\*.ps1`` -- 18 independent modules

## Modules

$((Get-ChildItem "$stagingDir\modules\*.ps1" | Sort-Object Name | ForEach-Object {
    "- ``$($_.Name)``"
}) -join "`n")

## Requirements

- Windows 10/11 (64-bit)
- Administrator privileges
- Internet connection

Generated: $(Get-Date -Format "yyyy-MM-dd")
"@
Set-Content (Join-Path $stagingDir "README.md") -Value $readme -Encoding UTF8
Write-Host "    + README.md" -ForegroundColor DarkGray

# --- Create output directory ---
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# --- Create ZIP ---
$zipPath = Join-Path $OutputDir "$packageName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$stagingDir\*" -DestinationPath $zipPath -CompressionLevel Optimal
$zipSize = "{0:N1} MB" -f ((Get-Item $zipPath).Length / 1MB)

# --- Cleanup ---
Remove-Item $stagingDir -Recurse -Force

# --- Summary ---
Write-Host ""
Write-Host "  +==============================================+" -ForegroundColor Green
Write-Host "  |   Package Created                            |" -ForegroundColor Green
Write-Host "  +==============================================+" -ForegroundColor Green
Write-Host "  |   Name:    $($packageName.PadRight(33))|" -ForegroundColor Green
Write-Host "  |   Size:    $($zipSize.PadRight(33))|" -ForegroundColor Green
Write-Host "  |   Output:  dist\$packageName.zip" -ForegroundColor Green -NoNewline
$outPad = 22 - $packageName.Length; if ($outPad -lt 0) { $outPad = 0 }
Write-Host (" " * $outPad) -NoNewline
Write-Host "|" -ForegroundColor Green
Write-Host "  |   Files:   $("$($manifest.fileCount)".PadRight(33))|" -ForegroundColor Green
Write-Host "  |   Modules: $("$($manifest.modules.Count)".PadRight(33))|" -ForegroundColor Green
Write-Host "  +==============================================+" -ForegroundColor Green
Write-Host ""
