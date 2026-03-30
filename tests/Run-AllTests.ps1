# ============================================================================
# WinInit Test Runner: Orchestrates all Test-*.ps1 files in the tests/ dir
# Usage:
#   .\tests\Run-AllTests.ps1                     Run all test files
#   .\tests\Run-AllTests.ps1 -DryRun             Pass -DryRun to each test
#   .\tests\Run-AllTests.ps1 -Suite json          Pass -Suite to each test
#   .\tests\Run-AllTests.ps1 -JUnit results.xml   Merge JUnit XML outputs
#   .\tests\Run-AllTests.ps1 -Quick               Skip slow test files
#   .\tests\Run-AllTests.ps1 -Verbose             Pass -Verbose to each test
# ============================================================================

param(
    [switch]$DryRun,
    [switch]$Verbose,
    [string]$JUnit = "",
    [string]$Suite = "",
    [switch]$Quick
)

$ErrorActionPreference = "Continue"
$runnerStart = Get-Date
$testsDir = $PSScriptRoot

# --- Discover test files ---
$testFiles = Get-ChildItem -Path $testsDir -Filter "Test-*.ps1" -File | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Host ""
    Write-Host "  No Test-*.ps1 files found in $testsDir" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# --- Banner ---
Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host "  |   WinInit Test Runner                              |" -ForegroundColor Cyan
Write-Host "  |   Discovering and running all test files            |" -ForegroundColor Cyan
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host ""

$modeFlags = @()
if ($DryRun)  { $modeFlags += "DryRun" }
if ($Verbose) { $modeFlags += "Verbose" }
if ($Suite)   { $modeFlags += "Suite=$Suite" }
if ($Quick)   { $modeFlags += "Quick" }
$modeStr = if ($modeFlags.Count -gt 0) { $modeFlags -join ", " } else { "Default" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host "  Test files found: $($testFiles.Count)" -ForegroundColor Gray
Write-Host ""

# --- Run each test file ---
$results = @()
$totalFailures = 0
$junitTempFiles = @()

foreach ($testFile in $testFiles) {
    $testName = $testFile.BaseName

    # --- Header ---
    Write-Host "  +--- $testName " -ForegroundColor DarkCyan -NoNewline
    $padLen = 50 - $testName.Length
    if ($padLen -lt 1) { $padLen = 1 }
    Write-Host ("-" * $padLen) -ForegroundColor DarkCyan
    Write-Host ""

    # --- Build arguments ---
    $testArgs = @()
    if ($DryRun)  { $testArgs += "-DryRun" }
    if ($Verbose) { $testArgs += "-Verbose" }
    if ($Suite)   { $testArgs += "-Suite"; $testArgs += $Suite }

    # If -JUnit is requested, give each test file its own temp JUnit output
    $tempJUnit = ""
    if ($JUnit) {
        $tempJUnit = Join-Path $env:TEMP "wininit-junit-$($testFile.BaseName)-$([guid]::NewGuid().ToString('N').Substring(0,8)).xml"
        $testArgs += "-JUnit"
        $testArgs += $tempJUnit
        $junitTempFiles += $tempJUnit
    }

    # --- Execute ---
    $testStart = Get-Date
    try {
        & $testFile.FullName @testArgs
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    } catch {
        $exitCode = 1
        Write-Host "  [ERR]  Exception running $($testFile.Name): $_" -ForegroundColor Yellow
    }
    $testDuration = (Get-Date) - $testStart

    # --- Record result ---
    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $statusColor = if ($exitCode -eq 0) { "Green" } else { "Red" }

    if ($exitCode -ne 0) {
        $totalFailures += $exitCode
    }

    $results += @{
        Name     = $testName
        File     = $testFile.Name
        Status   = $status
        ExitCode = $exitCode
        Duration = $testDuration
    }

    Write-Host ""
    Write-Host "  +--- " -ForegroundColor DarkCyan -NoNewline
    Write-Host "[$status]" -ForegroundColor $statusColor -NoNewline
    Write-Host " $testName - $("{0:N1}s" -f $testDuration.TotalSeconds)" -ForegroundColor DarkGray
    Write-Host ""
}

# --- Summary Table ---
$runnerDuration = (Get-Date) - $runnerStart
$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$allPassed = $failCount -eq 0
$borderColor = if ($allPassed) { "Green" } else { "Red" }

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor $borderColor
Write-Host "  |   Test Runner Results                              |" -ForegroundColor $borderColor
Write-Host "  +----------------------------------------------------+" -ForegroundColor $borderColor

# Table header
$hdrLine = "  |   {0}  {1}  {2}" -f "Test File".PadRight(30), "Status".PadRight(6), "Duration"
$hdrPad = 55 - $hdrLine.Length
if ($hdrPad -lt 0) { $hdrPad = 0 }
Write-Host $hdrLine -ForegroundColor White -NoNewline
Write-Host (" " * $hdrPad) -NoNewline
Write-Host "|" -ForegroundColor $borderColor

Write-Host "  +----------------------------------------------------+" -ForegroundColor $borderColor

foreach ($r in $results) {
    $icon = if ($r.Status -eq "PASS") { "[OK]  " } else { "[FAIL]" }
    $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    $durStr = "{0:N1}s" -f $r.Duration.TotalSeconds
    $line = "  |   $icon $($r.Name.PadRight(28)) $($r.Status.PadRight(6)) $durStr"
    $pad = 55 - $line.Length
    if ($pad -lt 0) { $pad = 0 }
    Write-Host $line -ForegroundColor $color -NoNewline
    Write-Host (" " * $pad) -NoNewline
    Write-Host "|" -ForegroundColor $borderColor
}

Write-Host "  +----------------------------------------------------+" -ForegroundColor $borderColor

# Totals row
$summaryLine = "  |   Files: $($results.Count)   Passed: $passCount   Failed: $failCount"
$summaryPad = 55 - $summaryLine.Length
if ($summaryPad -lt 0) { $summaryPad = 0 }
Write-Host $summaryLine -ForegroundColor White -NoNewline
Write-Host (" " * $summaryPad) -NoNewline
Write-Host "|" -ForegroundColor $borderColor

$totalLine = "  |   Total time: $("{0:N1}s" -f $runnerDuration.TotalSeconds)"
$totalPad = 55 - $totalLine.Length
if ($totalPad -lt 0) { $totalPad = 0 }
Write-Host $totalLine -ForegroundColor White -NoNewline
Write-Host (" " * $totalPad) -NoNewline
Write-Host "|" -ForegroundColor $borderColor

Write-Host "  +====================================================+" -ForegroundColor $borderColor
Write-Host ""

if ($allPassed) {
    Write-Host "  All test files passed!" -ForegroundColor Green
} else {
    Write-Host "  $failCount test file(s) had failures. Review output above." -ForegroundColor Red
}
Write-Host ""

# --- Merge JUnit XML ---
if ($JUnit) {
    $mergedXml = '<?xml version="1.0" encoding="UTF-8"?>' + "`n"

    # Collect all testsuites from temp files
    $allSuitesXml = ""
    $grandTotalTests = 0
    $grandTotalFailures = 0
    $grandTotalErrors = 0
    $grandTotalSkipped = 0

    foreach ($tempFile in $junitTempFiles) {
        if (Test-Path $tempFile) {
            $content = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Parse aggregate counts from the top-level <testsuites> element
                if ($content -match '<testsuites\s+tests="(\d+)"\s+failures="(\d+)"\s+errors="(\d+)"\s+skipped="(\d+)"') {
                    $grandTotalTests += [int]$Matches[1]
                    $grandTotalFailures += [int]$Matches[2]
                    $grandTotalErrors += [int]$Matches[3]
                    $grandTotalSkipped += [int]$Matches[4]
                }

                # Extract inner <testsuite> elements
                $suiteMatches = [regex]::Matches($content, '(?s)(<testsuite\b.*?</testsuite>)')
                foreach ($m in $suiteMatches) {
                    $allSuitesXml += "  " + $m.Value + "`n"
                }
            }
            # Clean up temp file
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    $mergedXml += "<testsuites tests=`"$grandTotalTests`" failures=`"$grandTotalFailures`" errors=`"$grandTotalErrors`" skipped=`"$grandTotalSkipped`">`n"
    $mergedXml += $allSuitesXml
    $mergedXml += "</testsuites>"

    # Resolve output path relative to the original working directory if not absolute
    if (-not [System.IO.Path]::IsPathRooted($JUnit)) {
        $JUnit = Join-Path (Get-Location).Path $JUnit
    }

    Set-Content -Path $JUnit -Value $mergedXml -Encoding UTF8
    Write-Host "  JUnit XML merged to: $JUnit" -ForegroundColor Gray
    Write-Host ""
}

exit $totalFailures
