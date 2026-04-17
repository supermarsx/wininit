# WinInit Quick Installer - Downloads and runs WinInit
# Usage: irm https://raw.githubusercontent.com/USER/wininit/main/install.ps1 | iex

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$installDir = "$env:USERPROFILE\wininit"
$repo = "https://github.com/USER/wininit"  # TODO: Update with actual repo URL

Write-Host ""
Write-Host "  WinInit Quick Installer" -ForegroundColor Cyan
Write-Host "  ======================" -ForegroundColor Cyan
Write-Host ""

# --- Verify Windows version ---
$osBuild = [Environment]::OSVersion.Version.Build
if ($osBuild -lt 19041) {
    Write-Host "  [!] Windows build $osBuild is too old. WinInit requires build 19041+ (Windows 10 2004 or later)." -ForegroundColor Red
    Write-Host ""
    exit 1
}
Write-Host "  [+] Windows build: $osBuild" -ForegroundColor Green

# --- Verify disk space ---
$driveLetter = $env:SystemDrive.TrimEnd(':')
$freeGB = [math]::Round((Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue).Free / 1GB, 1)
if ($freeGB -lt 5) {
    Write-Host "  [!] Only ${freeGB}GB free disk space. WinInit recommends 10GB+." -ForegroundColor Yellow
}
Write-Host "  [+] Free disk space: ${freeGB}GB" -ForegroundColor Green

# --- Ensure TLS 1.2 ---
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- Check if git is available ---
$hasGit = Get-Command git -ErrorAction SilentlyContinue

if ($hasGit) {
    Write-Host "  [*] Cloning repository via git..." -ForegroundColor Gray
    if (Test-Path $installDir) {
        Write-Host "  [*] Removing existing $installDir ..." -ForegroundColor Gray
        Remove-Item $installDir -Recurse -Force
    }
    try {
        git clone $repo $installDir 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }
    } catch {
        Write-Host "  [-] Git clone failed: $_" -ForegroundColor Red
        Write-Host "  [*] Falling back to ZIP download..." -ForegroundColor Gray
        $hasGit = $null
    }
}

if (-not $hasGit) {
    Write-Host "  [*] Downloading latest release as ZIP..." -ForegroundColor Gray
    $zipUrl = "$repo/archive/refs/heads/main.zip"
    $zipPath = Join-Path $env:TEMP "wininit.zip"

    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Host "  [-] Download failed: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Check your internet connection and verify the repository URL:" -ForegroundColor Yellow
        Write-Host "    $repo" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-Host "  [*] Extracting archive..." -ForegroundColor Gray
    $extractDir = Join-Path $env:TEMP "wininit-extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # Find the extracted folder (usually <repo>-main)
    $extractedFolder = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if (-not $extractedFolder) {
        Write-Host "  [-] Archive extraction failed - no folder found." -ForegroundColor Red
        exit 1
    }

    if (Test-Path $installDir) {
        Write-Host "  [*] Removing existing $installDir ..." -ForegroundColor Gray
        Remove-Item $installDir -Recurse -Force
    }
    Move-Item $extractedFolder.FullName $installDir

    # Cleanup
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Verify download ---
$initScript = Join-Path $installDir "init.ps1"
if (-not (Test-Path $initScript)) {
    Write-Host "  [-] Download failed - init.ps1 not found in $installDir" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$moduleCount = (Get-ChildItem (Join-Path $installDir "modules\*.ps1") -ErrorAction SilentlyContinue).Count
Write-Host "  [+] Downloaded to: $installDir" -ForegroundColor Green
Write-Host "  [+] Found $moduleCount modules" -ForegroundColor Green
Write-Host ""

# --- Launch ---
Write-Host "  [*] Launching WinInit..." -ForegroundColor Gray
Write-Host ""

$launchBat = Join-Path $installDir "launch.bat"
if (Test-Path $launchBat) {
    Set-Location $installDir
    & $launchBat
} else {
    # Fallback: run init.ps1 directly
    Set-Location $installDir
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $initScript
}
