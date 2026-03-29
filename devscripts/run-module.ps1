#Requires -RunAsAdministrator
# ============================================================================
# WinInit DevScript: Run Single Module
# Run an individual module for testing or re-applying a specific section
# Usage: .\devscripts\run-module.ps1 -Module <number|name>  [-List]
# ============================================================================

param(
    [string]$Module = "",
    [switch]$List
)

$ErrorActionPreference = "Continue"

# Load shared library
. "$PSScriptRoot\..\lib\common.ps1"
$script:TotalSteps = 1
$script:CurrentStep = 0

$modulesDir = "$PSScriptRoot\..\modules"
$allModules = Get-ChildItem "$modulesDir\*.ps1" | Sort-Object Name

if ($List -or -not $Module) {
    Write-Host ""
    Write-Host "  Available Modules:" -ForegroundColor Cyan
    Write-Host "  ==================" -ForegroundColor Cyan
    Write-Host ""
    foreach ($mod in $allModules) {
        $num = $mod.BaseName -replace "^(\d+)-.*", '$1'
        $name = $mod.BaseName -replace "^\d+-", ""
        Write-Host "    $num  " -ForegroundColor Yellow -NoNewline
        Write-Host $name -ForegroundColor White
    }
    Write-Host ""
    Write-Host "  Usage: .\devscripts\run-module.ps1 -Module 03" -ForegroundColor Gray
    Write-Host "         .\devscripts\run-module.ps1 -Module DesktopEnvironment" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Find the module
$target = $allModules | Where-Object {
    $_.BaseName -match $Module -or $_.BaseName -like "*$Module*"
} | Select-Object -First 1

if (-not $target) {
    Write-Host "  Module not found: $Module" -ForegroundColor Red
    Write-Host "  Use -List to see available modules" -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Host "  Running module: $($target.BaseName)" -ForegroundColor Cyan
Write-Host "  Path: $($target.FullName)" -ForegroundColor DarkGray
Write-Host ""

$startTime = Get-Date

try {
    . $target.FullName
    $duration = (Get-Date) - $startTime
    Write-Host ""
    Write-Host "  Module completed in $("{0:N1}s" -f $duration.TotalSeconds)" -ForegroundColor Green
} catch {
    $duration = (Get-Date) - $startTime
    Write-Host ""
    Write-Host "  Module FAILED after $("{0:N1}s" -f $duration.TotalSeconds): $_" -ForegroundColor Red
    exit 1
}
