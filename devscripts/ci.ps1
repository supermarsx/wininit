# ============================================================================
# WinInit DevScript: CI Pipeline
# Runs all checks in sequence: format, lint, typecheck, test
# Usage: .\devscripts\ci.ps1 [-Quick] [-SkipSystemTests]
# ============================================================================

param(
    [switch]$Quick,             # Skip slow checks (system state tests)
    [switch]$SkipSystemTests    # Skip tests that require admin/system state
)

$ErrorActionPreference = "Continue"
$ciStart = Get-Date

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host "  |   WinInit CI Pipeline                             |" -ForegroundColor Cyan
Write-Host "  |   Format -> Lint -> TypeCheck -> Test              |" -ForegroundColor Cyan
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host ""

$steps = @(
    @{ name = "Format Check";  script = "format.ps1";    args = @("-Check") },
    @{ name = "Lint";          script = "lint.ps1";       args = @() },
    @{ name = "Type Check";    script = "typecheck.ps1";  args = @() },
    @{ name = "Test Suite";    script = "test.ps1";       args = @() }
)

if ($Quick) {
    $steps = $steps | Where-Object { $_.name -ne "Test Suite" }
}

$results = @()
$allPassed = $true

foreach ($step in $steps) {
    $stepStart = Get-Date
    Write-Host "  +--- $($step.name) " -ForegroundColor DarkCyan -NoNewline
    Write-Host ("-" * (46 - $step.name.Length)) -ForegroundColor DarkCyan
    Write-Host ""

    $scriptPath = Join-Path $PSScriptRoot $step.script
    $stepArgs = $step.args
    if ($step.name -eq "Test Suite" -and $SkipSystemTests) {
        $stepArgs += "-DryRun"
    }

    & $scriptPath @stepArgs
    $exitCode = $LASTEXITCODE

    $stepDuration = (Get-Date) - $stepStart
    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL"; $allPassed = $false }
    $statusColor = if ($exitCode -eq 0) { "Green" } else { "Red" }

    $results += @{
        name     = $step.name
        status   = $status
        exit     = $exitCode
        duration = $stepDuration
    }

    Write-Host ""
    Write-Host "  +--- " -ForegroundColor DarkCyan -NoNewline
    Write-Host "[$status]" -ForegroundColor $statusColor -NoNewline
    Write-Host " $($step.name) - $("{0:N1}s" -f $stepDuration.TotalSeconds)" -ForegroundColor DarkGray
    Write-Host ""
}

# --- Summary ---
$ciDuration = (Get-Date) - $ciStart

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
Write-Host "  |   CI Results                                      |" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
Write-Host "  +====================================================+" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })

foreach ($r in $results) {
    $icon = if ($r.status -eq "PASS") { "[OK]" } else { "[FAIL]" }
    $color = if ($r.status -eq "PASS") { "Green" } else { "Red" }
    $line = "  |   $icon $($r.name.PadRight(30)) $($r.status.PadRight(6)) $("{0:N1}s" -f $r.duration.TotalSeconds)"
    $pad = 54 - $line.Length + 4
    if ($pad -lt 0) { $pad = 0 }
    Write-Host $line -ForegroundColor $color -NoNewline
    Write-Host (" " * $pad) -NoNewline
    Write-Host "|" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
}

Write-Host "  +====================================================+" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
$totalLine = "  |   Total: $("{0:N1}s" -f $ciDuration.TotalSeconds)"
$totalPad = 54 - $totalLine.Length + 4
if ($totalPad -lt 0) { $totalPad = 0 }
Write-Host $totalLine -ForegroundColor White -NoNewline
Write-Host (" " * $totalPad) -NoNewline
Write-Host "|" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
Write-Host "  +====================================================+" -ForegroundColor $(if ($allPassed) { "Green" } else { "Red" })
Write-Host ""

if ($allPassed) {
    Write-Host "  All checks passed!" -ForegroundColor Green
} else {
    Write-Host "  Some checks failed. Review output above." -ForegroundColor Red
}
Write-Host ""

exit $(if ($allPassed) { 0 } else { 1 })
