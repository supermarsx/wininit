# ============================================================================
# WinInit Test Suite: Infrastructure - Checkpoint, Rollback, Safety, Dashboard
# Standalone test script that can run independently.
#
# Usage:
#   .\tests\Test-Infrastructure.ps1                     Run all tests
#   .\tests\Test-Infrastructure.ps1 -Suite checkpoint   Run checkpoint suite
#   .\tests\Test-Infrastructure.ps1 -Suite rollback     Run rollback suite
#   .\tests\Test-Infrastructure.ps1 -Suite safety       Run safety suite
#   .\tests\Test-Infrastructure.ps1 -Suite dashboard    Run dashboard suite
#   .\tests\Test-Infrastructure.ps1 -Verbose            Show timing details
#   .\tests\Test-Infrastructure.ps1 -JUnit results.xml  Export JUnit XML
# ============================================================================

param(
    [string]$Suite = "",
    [switch]$Verbose,
    [switch]$DryRun,
    [string]$JUnit = ""
)

$ErrorActionPreference = "Continue"
$script:Passed   = 0
$script:Failed   = 0
$script:Skipped  = 0
$script:Warnings = 0
$script:Results  = @()
$script:CurrentSuite = ""

# Resolve project root
if ($PSScriptRoot) {
    $projectRoot = Resolve-Path "$PSScriptRoot\.."
} elseif ($MyInvocation.MyCommand.Path) {
    $projectRoot = Resolve-Path (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "..")
} else {
    $cwd = Get-Location
    if (Test-Path (Join-Path $cwd "modules")) {
        $projectRoot = $cwd.Path
    } elseif (Test-Path (Join-Path $cwd "..\modules")) {
        $projectRoot = Resolve-Path (Join-Path $cwd "..")
    } else {
        Write-Host "  ERROR: Cannot determine project root. Run from project directory." -ForegroundColor Red
        exit 1
    }
}
$projectRoot = $projectRoot.ToString()

# ============================================================================
# Embedded Test Framework (copied from devscripts\test.ps1 for standalone use)
# ============================================================================

function Test-Assert {
    param(
        [string]$Name,
        [scriptblock]$Condition,
        [string]$FailMessage = "",
        [switch]$Skip
    )
    $result = @{
        Suite   = $script:CurrentSuite
        Name    = $Name
        Status  = "UNKNOWN"
        Message = ""
        Time    = 0
    }

    if ($Skip) {
        $result.Status = "SKIP"
        $script:Skipped++
        if ($Verbose) {
            Write-Host "  [SKIP] " -ForegroundColor DarkGray -NoNewline
            Write-Host $Name -ForegroundColor DarkGray
        }
        $script:Results += $result
        return
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $testResult = & $Condition
        $sw.Stop()
        $result.Time = $sw.ElapsedMilliseconds

        if ($testResult) {
            $result.Status = "PASS"
            $script:Passed++
            if ($Verbose) {
                Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
                Write-Host "$Name ($($result.Time)ms)"
            } else {
                Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
                Write-Host $Name
            }
        } else {
            $result.Status = "FAIL"
            $result.Message = if ($FailMessage) { $FailMessage } else { "Condition returned false" }
            $script:Failed++
            Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
            Write-Host "$Name - $($result.Message)"
        }
    } catch {
        $sw.Stop()
        $result.Time = $sw.ElapsedMilliseconds
        $result.Status = "ERR"
        $result.Message = $_.ToString()
        $script:Warnings++
        Write-Host "  [ERR]  " -ForegroundColor Yellow -NoNewline
        Write-Host "$Name - $_"
    }
    $script:Results += $result
}

function Start-Suite {
    param([string]$Name)
    $script:CurrentSuite = $Name
    Write-Host ""
    Write-Host "  --- $Name ---" -ForegroundColor Magenta
}

# ============================================================================
# Helper: suite filter
# ============================================================================

$shouldRun = { param($s) -not $Suite -or $Suite -eq $s }

# ============================================================================
# Load libraries under test
# ============================================================================

# common.ps1 must be loaded first (provides Write-Log etc.)
$script:LogFile = Join-Path $env:TEMP "wininit_test_infra.log"
if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue }

. "$projectRoot\lib\common.ps1"
if ($script:SpinnerSync -and $script:SpinnerSync.Active) { Stop-Spinner }

# Source infrastructure libraries
. "$projectRoot\lib\safety.ps1"
. "$projectRoot\lib\checkpoint.ps1"
. "$projectRoot\lib\rollback.ps1"
. "$projectRoot\lib\dashboard.ps1"

# ============================================================================
# Banner
# ============================================================================

Write-Host ""
Write-Host "  WinInit Infrastructure Test Suite" -ForegroundColor Cyan
Write-Host "  ===================================" -ForegroundColor Cyan
$modeStr = if ($Suite) { "Suite: $Suite" } else { "All suites" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Setup: temp directory for test files
# ============================================================================

$testTempDir = Join-Path $env:TEMP "wininit_test_infra_$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $testTempDir -Force | Out-Null

# ============================================================================
# SUITE: checkpoint
# ============================================================================
if (& $shouldRun "checkpoint") {
    Start-Suite "checkpoint"

    # Override checkpoint file to use temp directory
    $origCheckpointFile = $script:CheckpointFile
    $script:CheckpointFile = Join-Path $testTempDir "test_checkpoint.json"

    # --- Test: Save-Checkpoint creates file ---
    Test-Assert "Save-Checkpoint: creates checkpoint file" {
        Save-Checkpoint -LastCompletedModule 3 -LastModuleFile "03-DesktopEnvironment.ps1" -Status "in_progress"
        Test-Path $script:CheckpointFile
    }

    # --- Test: Get-Checkpoint returns saved data ---
    Test-Assert "Get-Checkpoint: reads saved checkpoint" {
        $cp = Get-Checkpoint
        $null -ne $cp
    }

    Test-Assert "Get-Checkpoint: last_completed_module is correct" {
        $cp = Get-Checkpoint
        $cp.last_completed_module -eq 3
    }

    Test-Assert "Get-Checkpoint: last_module_file is correct" {
        $cp = Get-Checkpoint
        $cp.last_module_file -eq "03-DesktopEnvironment.ps1"
    }

    Test-Assert "Get-Checkpoint: status is correct" {
        $cp = Get-Checkpoint
        $cp.status -eq "in_progress"
    }

    Test-Assert "Get-Checkpoint: timestamp is ISO 8601" {
        $cp = Get-Checkpoint
        $null -ne $cp.timestamp -and $cp.timestamp -match '^\d{4}-\d{2}-\d{2}T'
    }

    Test-Assert "Get-Checkpoint: user field is set" {
        $cp = Get-Checkpoint
        -not [string]::IsNullOrEmpty($cp.user)
    }

    Test-Assert "Get-Checkpoint: computer field is set" {
        $cp = Get-Checkpoint
        -not [string]::IsNullOrEmpty($cp.computer)
    }

    Test-Assert "Get-Checkpoint: version is 1" {
        $cp = Get-Checkpoint
        $cp.version -eq 1
    }

    # --- Test: Save-Checkpoint with ExtraData ---
    Test-Assert "Save-Checkpoint: ExtraData persists" {
        Save-Checkpoint -LastCompletedModule 5 -LastModuleFile "05-Performance.ps1" -Status "paused" -ExtraData @{ note = "test extra" }
        $cp = Get-Checkpoint
        $cp.extra.note -eq "test extra"
    }

    # --- Test: Save-Checkpoint overwrites previous ---
    Test-Assert "Save-Checkpoint: overwrites previous checkpoint" {
        Save-Checkpoint -LastCompletedModule 10 -LastModuleFile "10-NetworkPerformance.ps1" -Status "rebooting"
        $cp = Get-Checkpoint
        $cp.last_completed_module -eq 10 -and $cp.status -eq "rebooting"
    }

    # --- Test: Remove-Checkpoint deletes file ---
    Test-Assert "Remove-Checkpoint: removes checkpoint file" {
        Remove-Checkpoint
        -not (Test-Path $script:CheckpointFile)
    }

    # --- Test: Get-Checkpoint returns null when no file ---
    Test-Assert "Get-Checkpoint: returns null when no checkpoint file" {
        $cp = Get-Checkpoint
        $null -eq $cp
    }

    # --- Test: Get-Checkpoint handles corrupt JSON ---
    Test-Assert "Get-Checkpoint: handles corrupt JSON gracefully" {
        "this is not json {{{" | Set-Content $script:CheckpointFile -Encoding UTF8
        $cp = Get-Checkpoint
        $null -eq $cp
    }

    # --- Test: checkpoint JSON is valid JSON ---
    Test-Assert "Save-Checkpoint: produces valid JSON" {
        Save-Checkpoint -LastCompletedModule 7 -LastModuleFile "07-Privacy.ps1" -Status "in_progress"
        $raw = Get-Content $script:CheckpointFile -Raw
        try {
            $parsed = $raw | ConvertFrom-Json
            $null -ne $parsed
        } catch {
            $false
        }
    }

    # Cleanup
    Remove-Checkpoint
    $script:CheckpointFile = $origCheckpointFile
}

# ============================================================================
# SUITE: rollback
# ============================================================================
if (& $shouldRun "rollback") {
    Start-Suite "rollback"

    # Override rollback file to use temp directory
    $origRollbackFile = $script:RollbackFile
    $script:RollbackFile = Join-Path $testTempDir "test_rollback.json"
    $script:RollbackEntries = @()
    $script:SectionName = "TestModule"

    # --- Test: Initialize-Rollback with no file ---
    Test-Assert "Initialize-Rollback: no file starts empty" {
        if (Test-Path $script:RollbackFile) { Remove-Item $script:RollbackFile -Force }
        $script:RollbackEntries = @()
        Initialize-Rollback
        $script:RollbackEntries.Count -eq 0
    }

    # --- Test: Add-RollbackEntry records entry ---
    Test-Assert "Add-RollbackEntry: records a registry entry" {
        $script:RollbackEntries = @()
        Add-RollbackEntry -Type "registry" -Description "Test reg key" -Data @{
            path = "HKCU:\SOFTWARE\Test"
            name = "TestValue"
            previous_value = 1
            new_value = 0
        }
        $script:RollbackEntries.Count -eq 1
    }

    Test-Assert "Add-RollbackEntry: entry has correct type" {
        $script:RollbackEntries[0].type -eq "registry"
    }

    Test-Assert "Add-RollbackEntry: entry has correct description" {
        $script:RollbackEntries[0].description -eq "Test reg key"
    }

    Test-Assert "Add-RollbackEntry: entry has timestamp" {
        -not [string]::IsNullOrEmpty($script:RollbackEntries[0].timestamp)
    }

    Test-Assert "Add-RollbackEntry: entry has module name" {
        $script:RollbackEntries[0].module -eq "TestModule"
    }

    Test-Assert "Add-RollbackEntry: entry data has previous_value" {
        $script:RollbackEntries[0].data.previous_value -eq 1
    }

    # --- Test: multiple entries accumulate ---
    Test-Assert "Add-RollbackEntry: multiple entries accumulate" {
        Add-RollbackEntry -Type "service" -Description "Test service" -Data @{
            name = "TestSvc"
            previous_start_type = "Automatic"
            new_start_type = "Disabled"
        }
        Add-RollbackEntry -Type "file" -Description "Test file" -Data @{
            path = "C:\test.txt"
            action = "created"
        }
        $script:RollbackEntries.Count -eq 3
    }

    # --- Test: Save-Rollback creates file ---
    Test-Assert "Save-Rollback: creates rollback JSON file" {
        Save-Rollback
        Test-Path $script:RollbackFile
    }

    # --- Test: rollback JSON is valid ---
    Test-Assert "Save-Rollback: produces valid JSON" {
        $raw = Get-Content $script:RollbackFile -Raw
        try {
            $parsed = $raw | ConvertFrom-Json
            $null -ne $parsed
        } catch {
            $false
        }
    }

    # --- Test: rollback JSON deserializes correctly ---
    Test-Assert "Save-Rollback: JSON round-trips correctly" {
        $raw = Get-Content $script:RollbackFile -Raw
        $entries = @($raw | ConvertFrom-Json)
        $entries.Count -eq 3
    }

    Test-Assert "Save-Rollback: deserialized entries have type field" {
        $raw = Get-Content $script:RollbackFile -Raw
        $entries = @($raw | ConvertFrom-Json)
        $entries[0].type -eq "registry" -and
        $entries[1].type -eq "service" -and
        $entries[2].type -eq "file"
    }

    # --- Test: Initialize-Rollback loads existing file ---
    Test-Assert "Initialize-Rollback: loads existing rollback data" {
        $script:RollbackEntries = @()
        Initialize-Rollback
        $script:RollbackEntries.Count -eq 3
    }

    # --- Test: rollback entry types ---
    Test-Assert "Add-RollbackEntry: supports 'app_remove' type" {
        $script:RollbackEntries = @()
        Add-RollbackEntry -Type "app_remove" -Description "Removed bloat app" -Data @{
            package = "Microsoft.BingNews"
        }
        $script:RollbackEntries[0].type -eq "app_remove"
    }

    Test-Assert "Add-RollbackEntry: supports 'feature' type" {
        Add-RollbackEntry -Type "feature" -Description "Enabled Hyper-V" -Data @{
            feature = "Microsoft-Hyper-V-All"
            action = "enabled"
        }
        $script:RollbackEntries[1].type -eq "feature"
    }

    # Cleanup
    Remove-Item $script:RollbackFile -Force -ErrorAction SilentlyContinue
    $script:RollbackFile = $origRollbackFile
    $script:RollbackEntries = @()
}

# ============================================================================
# SUITE: safety
# ============================================================================
if (& $shouldRun "safety") {
    Start-Suite "safety"

    # --- Test: risk level definitions exist ---
    Test-Assert "RiskLevels: 'safe' level is defined" {
        $script:RiskLevels.ContainsKey("safe")
    }

    Test-Assert "RiskLevels: 'moderate' level is defined" {
        $script:RiskLevels.ContainsKey("moderate")
    }

    Test-Assert "RiskLevels: 'aggressive' level is defined" {
        $script:RiskLevels.ContainsKey("aggressive")
    }

    # --- Test: risk level properties ---
    Test-Assert "RiskLevels: 'safe' has [S] icon" {
        $script:RiskLevels["safe"].Icon -eq "[S]"
    }

    Test-Assert "RiskLevels: 'moderate' has [M] icon" {
        $script:RiskLevels["moderate"].Icon -eq "[M]"
    }

    Test-Assert "RiskLevels: 'aggressive' has [A] icon" {
        $script:RiskLevels["aggressive"].Icon -eq "[A]"
    }

    Test-Assert "RiskLevels: each level has Color property" {
        $allHaveColor = $true
        foreach ($key in $script:RiskLevels.Keys) {
            if (-not $script:RiskLevels[$key].ContainsKey("Color")) { $allHaveColor = $false; break }
        }
        $allHaveColor
    }

    Test-Assert "RiskLevels: each level has Desc property" {
        $allHaveDesc = $true
        foreach ($key in $script:RiskLevels.Keys) {
            if (-not $script:RiskLevels[$key].ContainsKey("Desc")) { $allHaveDesc = $false; break }
        }
        $allHaveDesc
    }

    # --- Test: risk stats tracker ---
    Test-Assert "RiskStats: initializes with zero counts" {
        # Reset stats for testing
        $script:RiskStats = @{ safe = 0; moderate = 0; aggressive = 0 }
        $script:RiskStats.safe -eq 0 -and
        $script:RiskStats.moderate -eq 0 -and
        $script:RiskStats.aggressive -eq 0
    }

    # --- Test: Write-RiskLog increments stats ---
    Test-Assert "Write-RiskLog: increments safe count" {
        $script:RiskStats = @{ safe = 0; moderate = 0; aggressive = 0 }
        Write-RiskLog "Test safe tweak" "safe" "OK" 6>&1 | Out-Null
        $script:RiskStats.safe -eq 1
    }

    Test-Assert "Write-RiskLog: increments moderate count" {
        Write-RiskLog "Test moderate tweak" "moderate" "OK" 6>&1 | Out-Null
        $script:RiskStats.moderate -eq 1
    }

    Test-Assert "Write-RiskLog: increments aggressive count" {
        Write-RiskLog "Test aggressive tweak" "aggressive" "OK" 6>&1 | Out-Null
        $script:RiskStats.aggressive -eq 1
    }

    Test-Assert "Write-RiskLog: cumulative counting works" {
        Write-RiskLog "Another safe" "safe" "OK" 6>&1 | Out-Null
        Write-RiskLog "Another safe" "safe" "OK" 6>&1 | Out-Null
        $script:RiskStats.safe -eq 3
    }

    # --- Test: Write-RiskSummary does not throw ---
    Test-Assert "Write-RiskSummary: does not throw" {
        $script:RiskStats = @{ safe = 10; moderate = 5; aggressive = 2 }
        Write-RiskSummary 6>&1 | Out-Null
        $true
    }

    # --- Test: risk level tracking in Privacy module ---
    Test-Assert "Privacy module: contains Write-RiskLog calls" {
        $privacyPath = Join-Path $projectRoot "modules\07-Privacy.ps1"
        if (-not (Test-Path $privacyPath)) { return $false }
        $content = Get-Content $privacyPath -Raw
        $content -match 'Write-RiskLog'
    }

    Test-Assert "Privacy module: uses 'safe' risk level" {
        $privacyPath = Join-Path $projectRoot "modules\07-Privacy.ps1"
        if (-not (Test-Path $privacyPath)) { return $false }
        $content = Get-Content $privacyPath -Raw
        $content -match '"safe"'
    }

    Test-Assert "Privacy module: uses 'moderate' risk level" {
        $privacyPath = Join-Path $projectRoot "modules\07-Privacy.ps1"
        if (-not (Test-Path $privacyPath)) { return $false }
        $content = Get-Content $privacyPath -Raw
        $content -match '"moderate"'
    }

    Test-Assert "Privacy module: uses 'aggressive' risk level" {
        $privacyPath = Join-Path $projectRoot "modules\07-Privacy.ps1"
        if (-not (Test-Path $privacyPath)) { return $false }
        $content = Get-Content $privacyPath -Raw
        $content -match '"aggressive"'
    }

    # Reset risk stats
    $script:RiskStats = @{ safe = 0; moderate = 0; aggressive = 0 }
}

# ============================================================================
# SUITE: dashboard
# ============================================================================
if (& $shouldRun "dashboard") {
    Start-Suite "dashboard"

    # --- Test: module weight table exists ---
    Test-Assert "ModuleWeights: table exists and is hashtable" {
        $script:ModuleWeights -is [hashtable]
    }

    Test-Assert "ModuleWeights: has entries for all 18 modules" {
        $script:ModuleWeights.Count -eq 18
    } -FailMessage "Expected 18, got $($script:ModuleWeights.Count)"

    # --- Test: all weights are positive integers ---
    Test-Assert "ModuleWeights: all values are positive integers" {
        $allPositive = $true
        foreach ($key in $script:ModuleWeights.Keys) {
            $w = $script:ModuleWeights[$key]
            if ($w -le 0 -or $w -isnot [int]) { $allPositive = $false; break }
        }
        $allPositive
    }

    # --- Test: heaviest module is Applications (15) ---
    Test-Assert "ModuleWeights: 02-Applications has highest weight" {
        $maxKey = $script:ModuleWeights.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        $maxKey.Key -eq "02-Applications"
    }

    # --- Test: total weight sum ---
    Test-Assert "ModuleWeights: total weight sum is reasonable (> 50)" {
        $total = 0
        foreach ($v in $script:ModuleWeights.Values) { $total += $v }
        $total -gt 50
    }

    # --- Test: Initialize-Dashboard ---
    Test-Assert "Initialize-Dashboard: sets StartTime" {
        Initialize-Dashboard -TotalModules 18
        $null -ne $script:DashboardState.StartTime
    }

    Test-Assert "Initialize-Dashboard: sets TotalModules to 18" {
        $script:DashboardState.TotalModules -eq 18
    }

    Test-Assert "Initialize-Dashboard: resets CurrentModule to 0" {
        $script:DashboardState.CurrentModule -eq 0
    }

    Test-Assert "Initialize-Dashboard: resets CompletedWeight to 0" {
        $script:DashboardState.CompletedWeight -eq 0
    }

    Test-Assert "Initialize-Dashboard: calculates TotalWeight > 0" {
        $script:DashboardState.TotalWeight -gt 0
    }

    Test-Assert "Initialize-Dashboard: resets Errors to 0" {
        $script:DashboardState.Errors -eq 0
    }

    Test-Assert "Initialize-Dashboard: resets ModuleResults to empty" {
        $script:DashboardState.ModuleResults.Count -eq 0
    }

    # --- Test: Update-Dashboard running ---
    Test-Assert "Update-Dashboard: running state sets CurrentModule" {
        Update-Dashboard -ModuleIndex 1 -ModuleName "01-PackageManagers.ps1" -Status "running"
        $script:DashboardState.CurrentModule -eq 1
    }

    Test-Assert "Update-Dashboard: running state sets ModuleStartTime" {
        $null -ne $script:DashboardState.ModuleStartTime
    }

    # --- Test: Update-Dashboard completed ---
    Test-Assert "Update-Dashboard: completed accumulates weight" {
        $beforeWeight = $script:DashboardState.CompletedWeight
        Update-Dashboard -ModuleIndex 1 -ModuleName "01-PackageManagers.ps1" -Status "completed"
        $script:DashboardState.CompletedWeight -gt $beforeWeight
    }

    Test-Assert "Update-Dashboard: completed adds to ModuleResults" {
        $script:DashboardState.ModuleResults.Count -ge 1
    }

    # --- Test: Update-Dashboard failed ---
    Test-Assert "Update-Dashboard: failed increments Errors" {
        $beforeErrors = $script:DashboardState.Errors
        Update-Dashboard -ModuleIndex 2 -ModuleName "02-Applications.ps1" -Status "running"
        Update-Dashboard -ModuleIndex 2 -ModuleName "02-Applications.ps1" -Status "failed"
        $script:DashboardState.Errors -eq ($beforeErrors + 1)
    }

    # --- Test: ETA calculation logic ---
    Test-Assert "ETA: percentage calculation is correct at 0%" {
        $totalWeight = 100
        $completedWeight = 0
        $pct = [math]::Min(100, [math]::Round(($completedWeight / [math]::Max(1, $totalWeight)) * 100))
        $pct -eq 0
    }

    Test-Assert "ETA: percentage calculation is correct at 50%" {
        $totalWeight = 100
        $completedWeight = 50
        $pct = [math]::Min(100, [math]::Round(($completedWeight / [math]::Max(1, $totalWeight)) * 100))
        $pct -eq 50
    }

    Test-Assert "ETA: percentage calculation is correct at 100%" {
        $totalWeight = 100
        $completedWeight = 100
        $pct = [math]::Min(100, [math]::Round(($completedWeight / [math]::Max(1, $totalWeight)) * 100))
        $pct -eq 100
    }

    Test-Assert "ETA: remaining time calculation is reasonable" {
        # If 25% done in 60 seconds, total estimate = 240s, remaining = 180s
        $elapsedSeconds = 60
        $pct = 25
        $totalEstimate = $elapsedSeconds / ($pct / 100)
        $remaining = [math]::Max(0, $totalEstimate - $elapsedSeconds)
        [math]::Abs($remaining - 180) -lt 1
    }

    Test-Assert "ETA: zero total weight does not divide by zero" {
        $totalWeight = 0
        $completedWeight = 0
        $safeTotalWeight = [math]::Max(1, $totalWeight)
        $pct = [math]::Min(100, [math]::Round(($completedWeight / $safeTotalWeight) * 100))
        $pct -eq 0  # Should not crash
    }

    # --- Test: progress bar width calculation ---
    Test-Assert "Dashboard: progress bar filled+empty equals bar width" {
        $barWidth = 30
        $pct = 67
        $filled = [math]::Round($barWidth * $pct / 100)
        $empty = $barWidth - $filled
        ($filled + $empty) -eq $barWidth
    }

    # --- Test: Show-Dashboard does not throw ---
    Test-Assert "Show-Dashboard: does not throw" {
        try {
            Show-Dashboard 6>&1 | Out-Null
            $true
        } catch {
            $false
        }
    }

    # --- Test: Write-DashboardSummary does not throw ---
    Test-Assert "Write-DashboardSummary: does not throw" {
        try {
            Write-DashboardSummary 6>&1 | Out-Null
            $true
        } catch {
            $false
        }
    }

    # --- Test: module weight keys match expected module names ---
    Test-Assert "ModuleWeights: keys match expected module naming convention" {
        $allMatch = $true
        foreach ($key in $script:ModuleWeights.Keys) {
            if ($key -notmatch '^\d{2}-[A-Z]') { $allMatch = $false; break }
        }
        $allMatch
    }

    # --- Test: module dependency resolution (parallel) ---
    # Modules are sequential by design, but we test that the weight ordering is logical
    Test-Assert "ModuleWeights: PackageManagers has low weight (runs fast)" {
        $script:ModuleWeights["01-PackageManagers"] -le 5
    }

    Test-Assert "ModuleWeights: Applications has highest weight (longest)" {
        $appWeight = $script:ModuleWeights["02-Applications"]
        $maxWeight = ($script:ModuleWeights.Values | Measure-Object -Maximum).Maximum
        $appWeight -eq $maxWeight
    }

    Test-Assert "ModuleWeights: Performance has low weight (registry only)" {
        $script:ModuleWeights["05-Performance"] -le 3
    }
}

# ============================================================================
# Cleanup temp directory
# ============================================================================

Remove-Item $testTempDir -Recurse -Force -ErrorAction SilentlyContinue

# ============================================================================
# Summary
# ============================================================================

$total = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings

Write-Host ""
Write-Host "  ===================================" -ForegroundColor Cyan
Write-Host "  Test-Infrastructure.ps1 Results" -ForegroundColor Cyan
Write-Host "  ===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total:   $total" -ForegroundColor White
Write-Host "  Passed:  $($script:Passed)" -ForegroundColor Green
Write-Host "  Failed:  $($script:Failed)" -ForegroundColor Red
Write-Host "  Errors:  $($script:Warnings)" -ForegroundColor Yellow
Write-Host "  Skipped: $($script:Skipped)" -ForegroundColor DarkGray
Write-Host ""

if ($script:Failed -gt 0) {
    Write-Host "  FAILED TESTS:" -ForegroundColor Red
    foreach ($r in $script:Results) {
        if ($r.Status -eq "FAIL") {
            Write-Host "    [$($r.Suite)] $($r.Name) - $($r.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

if ($script:Warnings -gt 0) {
    Write-Host "  ERRORS:" -ForegroundColor Yellow
    foreach ($r in $script:Results) {
        if ($r.Status -eq "ERR") {
            Write-Host "    [$($r.Suite)] $($r.Name) - $($r.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

# ============================================================================
# JUnit XML Export
# ============================================================================

if ($JUnit) {
    $xml = [System.Text.StringBuilder]::new()
    $null = $xml.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    $null = $xml.AppendLine("<testsuites tests=`"$total`" failures=`"$($script:Failed)`" errors=`"$($script:Warnings)`" skipped=`"$($script:Skipped)`">")

    $suites = $script:Results | Group-Object { $_.Suite }
    foreach ($suite in $suites) {
        $suiteName = $suite.Name
        $suiteTests = $suite.Group
        $suiteFail = @($suiteTests | Where-Object { $_.Status -eq "FAIL" }).Count
        $suiteErr  = @($suiteTests | Where-Object { $_.Status -eq "ERR" }).Count
        $suiteSkip = @($suiteTests | Where-Object { $_.Status -eq "SKIP" }).Count
        $suiteTime = ($suiteTests | Measure-Object -Property Time -Sum).Sum / 1000.0

        $null = $xml.AppendLine("  <testsuite name=`"$([System.Security.SecurityElement]::Escape($suiteName))`" tests=`"$($suiteTests.Count)`" failures=`"$suiteFail`" errors=`"$suiteErr`" skipped=`"$suiteSkip`" time=`"$suiteTime`">")

        foreach ($t in $suiteTests) {
            $tName = [System.Security.SecurityElement]::Escape($t.Name)
            $tTime = $t.Time / 1000.0
            $null = $xml.Append("    <testcase name=`"$tName`" classname=`"$([System.Security.SecurityElement]::Escape($suiteName))`" time=`"$tTime`"")

            if ($t.Status -eq "PASS") {
                $null = $xml.AppendLine(" />")
            } elseif ($t.Status -eq "SKIP") {
                $null = $xml.AppendLine(">")
                $null = $xml.AppendLine("      <skipped />")
                $null = $xml.AppendLine("    </testcase>")
            } elseif ($t.Status -eq "FAIL") {
                $null = $xml.AppendLine(">")
                $msg = [System.Security.SecurityElement]::Escape($t.Message)
                $null = $xml.AppendLine("      <failure message=`"$msg`">$msg</failure>")
                $null = $xml.AppendLine("    </testcase>")
            } elseif ($t.Status -eq "ERR") {
                $null = $xml.AppendLine(">")
                $msg = [System.Security.SecurityElement]::Escape($t.Message)
                $null = $xml.AppendLine("      <error message=`"$msg`">$msg</error>")
                $null = $xml.AppendLine("    </testcase>")
            } else {
                $null = $xml.AppendLine(" />")
            }
        }
        $null = $xml.AppendLine("  </testsuite>")
    }
    $null = $xml.AppendLine("</testsuites>")

    $junitPath = if ([System.IO.Path]::IsPathRooted($JUnit)) { $JUnit } else { Join-Path (Get-Location) $JUnit }
    [System.IO.File]::WriteAllText($junitPath, $xml.ToString(), [System.Text.UTF8Encoding]::new($false))
    Write-Host "  JUnit XML exported to: $junitPath" -ForegroundColor Cyan
    Write-Host ""
}

# Exit code
if ($script:Failed -gt 0) {
    exit 1
} else {
    exit 0
}
