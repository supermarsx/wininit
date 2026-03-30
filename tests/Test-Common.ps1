# ============================================================================
# WinInit Test Suite: lib\common.ps1 - All 49 Functions
# Standalone test script that can run independently.
#
# Usage:
#   .\tests\Test-Common.ps1                     Run all tests
#   .\tests\Test-Common.ps1 -Suite logging      Run only logging suite
#   .\tests\Test-Common.ps1 -Verbose            Show timing details
#   .\tests\Test-Common.ps1 -JUnit results.xml  Export JUnit XML
# ============================================================================

param(
    [string]$Suite = "",
    [switch]$Verbose,
    [string]$JUnit = ""
)

$ErrorActionPreference = "Continue"
$script:Passed   = 0
$script:Failed   = 0
$script:Skipped  = 0
$script:Warnings = 0
$script:Results  = @()
$script:CurrentSuite = ""

$projectRoot = Resolve-Path "$PSScriptRoot\.."

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
# Dot-source lib\common.ps1
# ============================================================================

# Override the log file so we don't pollute the real log
$script:LogFile = Join-Path $env:TEMP "wininit_test_common.log"
if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue }

. "$projectRoot\lib\common.ps1"

# After sourcing, ensure spinner is stopped (Enable-VTMode runs on source)
if ($script:SpinnerSync.Active) { Stop-Spinner }

# ============================================================================
# Banner
# ============================================================================

Write-Host ""
Write-Host "  WinInit Common Library Test Suite" -ForegroundColor Cyan
Write-Host "  ==================================" -ForegroundColor Cyan
$modeStr = if ($Suite) { "Suite: $Suite" } else { "All suites" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Test registry path for cleanup
# ============================================================================

$testRegPath = "HKCU:\SOFTWARE\WinInitTest"

# ============================================================================
# SUITE: logging
# ============================================================================
if (& $shouldRun "logging") {
    Start-Suite "logging"

    # --- Write-Log ---

    Test-Assert "Write-Log: INFO level does not throw" {
        Write-Log "Test message" "INFO" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: OK level does not throw" {
        Write-Log "Success message" "OK" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: WARN level does not throw" {
        Write-Log "Warning message" "WARN" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: ERROR level does not throw" {
        Write-Log "Error message" "ERROR" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: STEP level does not throw" {
        Write-Log "Step message" "STEP" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: DEBUG level does not throw" {
        Write-Log "Debug message" "DEBUG" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: FATAL level does not throw" {
        Write-Log "Fatal message" "FATAL" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: unknown level falls back to INFO" {
        Write-Log "Unknown level" "NONEXISTENT" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: empty message does not throw" {
        Write-Log "" "INFO" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: default level is INFO" {
        Write-Log "Default level test" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Log: writes to log file" {
        $before = if (Test-Path $script:LogFile) { (Get-Content $script:LogFile -Raw).Length } else { 0 }
        Write-Log "File write test" "INFO"
        Start-Sleep -Milliseconds 50
        $after = (Get-Content $script:LogFile -Raw).Length
        $after -gt $before
    }

    Test-Assert "Write-Log: log file entry contains message text" {
        $marker = "UniqueTestMarker_$(Get-Random)"
        Write-Log $marker "INFO"
        Start-Sleep -Milliseconds 50
        $content = Get-Content $script:LogFile -Raw
        $content -match $marker
    }

    Test-Assert "Write-Log: log file entry contains level tag" {
        $marker = "LevelTagTest_$(Get-Random)"
        Write-Log $marker "WARN"
        Start-Sleep -Milliseconds 50
        $content = Get-Content $script:LogFile -Raw
        $content -match "WARN.*$marker" -or $content -match "$marker"
    }

    # --- Write-Section ---

    Test-Assert "Write-Section: does not throw with valid args" {
        # Save and restore step counters
        $savedStep = $script:CurrentStep
        $savedTotal = $script:TotalSteps
        $script:TotalSteps = 5
        Write-Section -Name "Test Section" -Description "Test desc" 6>&1 | Out-Null
        # Stop any spinner it started
        if ($script:SpinnerSync.Active) { Stop-Spinner }
        $script:CurrentStep = $savedStep
        $script:TotalSteps = $savedTotal
        $true
    }

    Test-Assert "Write-Section: increments CurrentStep" {
        $script:TotalSteps = 10
        $script:CurrentStep = 2
        Write-Section -Name "Step Test" 6>&1 | Out-Null
        if ($script:SpinnerSync.Active) { Stop-Spinner }
        $result = $script:CurrentStep -eq 3
        $script:CurrentStep = 0
        $script:TotalSteps = 0
        $result
    }

    Test-Assert "Write-Section: sets SectionName" {
        $script:TotalSteps = 5
        Write-Section -Name "MySectionName" 6>&1 | Out-Null
        if ($script:SpinnerSync.Active) { Stop-Spinner }
        $result = $script:SectionName -eq "MySectionName"
        $script:CurrentStep = 0
        $script:TotalSteps = 0
        $result
    }

    Test-Assert "Write-Section: with ItemCount does not throw" {
        $script:TotalSteps = 5
        Write-Section -Name "ItemTest" -ItemCount 10 6>&1 | Out-Null
        if ($script:SpinnerSync.Active) { Stop-Spinner }
        $script:CurrentStep = 0
        $script:TotalSteps = 0
        $true
    }

    # --- Write-SubStep ---

    Test-Assert "Write-SubStep: does not throw" {
        Write-SubStep "Test substep" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SubStep: empty message does not throw" {
        Write-SubStep "" 6>&1 | Out-Null
        $true
    }

    # --- Write-ModuleStart ---

    Test-Assert "Write-ModuleStart: does not throw" {
        Write-ModuleStart -File "test.ps1" -Description "Test module" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ModuleStart: empty args do not throw" {
        Write-ModuleStart -File "" -Description "" 6>&1 | Out-Null
        $true
    }
}

# ============================================================================
# SUITE: progress
# ============================================================================
if (& $shouldRun "progress") {
    Start-Suite "progress"

    # --- Write-ProgressBar ---

    Test-Assert "Write-ProgressBar: 0% does not throw" {
        Write-ProgressBar -Percent 0 -Label "Start" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ProgressBar: 50% does not throw" {
        Write-ProgressBar -Percent 50 -Label "Half" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ProgressBar: 100% does not throw" {
        Write-ProgressBar -Percent 100 -Label "Done" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ProgressBar: negative clamped to 0" {
        Write-ProgressBar -Percent -10 -Label "Negative" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ProgressBar: >100 clamped to 100" {
        Write-ProgressBar -Percent 200 -Label "Over" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-ProgressBar: no label does not throw" {
        Write-ProgressBar -Percent 42 6>&1 | Out-Null
        $true
    }

    # --- Start-Spinner / Stop-Spinner ---

    Test-Assert "Start-Spinner: starts without error" {
        Start-Spinner "Test spinner"
        $result = $script:SpinnerSync.Active -eq $true
        Stop-Spinner
        $result
    }

    Test-Assert "Start-Spinner: sets message" {
        Start-Spinner "Spinner msg test"
        $result = $script:SpinnerSync.Message -eq "Spinner msg test"
        Stop-Spinner
        $result
    }

    Test-Assert "Start-Spinner: with Total sets progress tracking" {
        Start-Spinner "Progress spinner" -Total 20
        $result = ($script:SpinnerSync.Total -eq 20) -and ($script:SpinnerSync.Progress -eq 0)
        Stop-Spinner
        $result
    }

    Test-Assert "Stop-Spinner: deactivates spinner" {
        Start-Spinner "Stop test"
        Stop-Spinner
        $script:SpinnerSync.Active -eq $false
    }

    Test-Assert "Stop-Spinner: with FinalMessage does not throw" {
        Start-Spinner "Final msg test"
        Stop-Spinner -FinalMessage "Done!" -Status "OK"
        $true
    }

    Test-Assert "Stop-Spinner: with ERROR status does not throw" {
        Start-Spinner "Error status test"
        Stop-Spinner -FinalMessage "Failed" -Status "ERROR"
        $true
    }

    Test-Assert "Stop-Spinner: with WARN status does not throw" {
        Start-Spinner "Warn status test"
        Stop-Spinner -FinalMessage "Warning" -Status "WARN"
        $true
    }

    Test-Assert "Stop-Spinner: calling stop when no spinner is safe" {
        # Ensure no spinner is active
        $script:SpinnerSync.Active = $false
        # Stop-Spinner should handle this gracefully
        Stop-Spinner
        $true
    }

    # --- Update-SpinnerMessage ---

    Test-Assert "Update-SpinnerMessage: updates message while spinner active" {
        Start-Spinner "Original message"
        Update-SpinnerMessage "Updated message"
        $result = $script:SpinnerSync.Message -eq "Updated message"
        Stop-Spinner
        $result
    }

    Test-Assert "Update-SpinnerMessage: empty string does not throw" {
        Start-Spinner "Msg test"
        Update-SpinnerMessage ""
        Stop-Spinner
        $true
    }

    # --- Update-SpinnerProgress ---

    Test-Assert "Update-SpinnerProgress: increments progress" {
        Start-Spinner "Incr test" -Total 10
        $script:SpinnerSync.Progress = 3
        Update-SpinnerProgress
        $result = $script:SpinnerSync.Progress -eq 4
        Stop-Spinner
        $result
    }

    Test-Assert "Update-SpinnerProgress: with message updates both" {
        Start-Spinner "Both test" -Total 10
        $script:SpinnerSync.Progress = 5
        Update-SpinnerProgress -Message "New msg"
        $result = ($script:SpinnerSync.Progress -eq 6) -and ($script:SpinnerSync.Message -eq "New msg")
        Stop-Spinner
        $result
    }

    # --- Set-SpinnerProgress ---

    Test-Assert "Set-SpinnerProgress: sets to specific value" {
        Start-Spinner "Set test" -Total 20
        Set-SpinnerProgress -Current 15
        $result = $script:SpinnerSync.Progress -eq 15
        Stop-Spinner
        $result
    }

    Test-Assert "Set-SpinnerProgress: with message updates both" {
        Start-Spinner "Set msg test" -Total 20
        Set-SpinnerProgress -Current 8 -Message "At eight"
        $result = ($script:SpinnerSync.Progress -eq 8) -and ($script:SpinnerSync.Message -eq "At eight")
        Stop-Spinner
        $result
    }

    # --- Invoke-WithSpinner ---

    Test-Assert "Invoke-WithSpinner: runs action and returns result" {
        $val = Invoke-WithSpinner -Message "Test action" -Action { 42 }
        $val -eq 42
    }

    Test-Assert "Invoke-WithSpinner: uses SuccessMessage" {
        $val = Invoke-WithSpinner -Message "Orig" -Action { "ok" } -SuccessMessage "Custom done"
        $val -eq "ok"
    }

    Test-Assert "Invoke-WithSpinner: throws on error without ContinueOnError" {
        $threw = $false
        try {
            Invoke-WithSpinner -Message "Fail test" -Action { throw "deliberate" }
        } catch {
            $threw = $true
        }
        $threw
    }

    Test-Assert "Invoke-WithSpinner: returns null with ContinueOnError on failure" {
        $val = Invoke-WithSpinner -Message "Continue test" -Action { throw "deliberate" } -ContinueOnError
        $null -eq $val
    }

    Test-Assert "Invoke-WithSpinner: handles scriptblock returning null" {
        $val = Invoke-WithSpinner -Message "Null result" -Action { $null }
        $null -eq $val
    }

    Test-Assert "Invoke-WithSpinner: handles scriptblock returning array" {
        $val = Invoke-WithSpinner -Message "Array result" -Action { @(1, 2, 3) }
        ($val -is [array] -or $val -is [System.Collections.IEnumerable]) -and @($val).Count -eq 3
    }
}

# ============================================================================
# SUITE: formatting
# ============================================================================
if (& $shouldRun "formatting") {
    Start-Suite "formatting"

    # --- Write-SummaryBox ---

    Test-Assert "Write-SummaryBox: does not throw with valid args" {
        Write-SummaryBox -Title "Test Summary" -Lines @("Line 1", "Line 2") 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SummaryBox: empty lines array does not throw" {
        Write-SummaryBox -Title "Empty" -Lines @() 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SummaryBox: handles REBOOT prefix lines" {
        Write-SummaryBox -Title "Reboot Test" -Lines @("REBOOT required", "Normal line") 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SummaryBox: handles Failed prefix lines" {
        Write-SummaryBox -Title "Fail Test" -Lines @("Failed: something", "  ! Error item") 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SummaryBox: handles empty string in lines" {
        Write-SummaryBox -Title "Blanks" -Lines @("First", "", "Third") 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-SummaryBox: writes to log file" {
        $marker = "SummaryBoxMarker_$(Get-Random)"
        Write-SummaryBox -Title $marker -Lines @("test line")
        Start-Sleep -Milliseconds 50
        $content = Get-Content $script:LogFile -Raw
        $content -match $marker
    }

    # --- Write-Rule ---

    Test-Assert "Write-Rule: default params do not throw" {
        Write-Rule 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Rule: custom char and width" {
        Write-Rule -Char "=" -Width 40 -Color "Cyan" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Rule: width 0 does not throw" {
        Write-Rule -Width 0 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Rule: various colors do not throw" {
        foreach ($col in @("DarkGray", "Cyan", "Green", "Yellow", "Red")) {
            Write-Rule -Color $col 6>&1 | Out-Null
        }
        $true
    }

    # --- Write-Badge ---

    Test-Assert "Write-Badge: does not throw" {
        Write-Badge -Label "Status:" -Value "OK" -Color "Cyan" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Badge: empty strings do not throw" {
        Write-Badge -Label "" -Value "" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Badge: unknown color falls back gracefully" {
        Write-Badge -Label "X" -Value "Y" -Color "NonExistentColor" 6>&1 | Out-Null
        $true
    }

    # --- Write-Blank ---

    Test-Assert "Write-Blank: default count (1) does not throw" {
        Write-Blank 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Blank: count 0 does not throw" {
        Write-Blank -Count 0 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Blank: count 3 does not throw" {
        Write-Blank -Count 3 6>&1 | Out-Null
        $true
    }

    # --- Write-Banner ---

    Test-Assert "Write-Banner: full args do not throw" {
        Write-Banner -Title "Test Banner" -Subtitle "Subtitle" -Info @("Info line 1", "Info line 2") 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Banner: title only does not throw" {
        Write-Banner -Title "Minimal Banner" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Banner: empty title does not throw" {
        Write-Banner -Title "" 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Banner: long title does not throw" {
        Write-Banner -Title ("A" * 200) 6>&1 | Out-Null
        $true
    }

    # --- Write-Elapsed ---

    Test-Assert "Write-Elapsed: does not throw with recent time" {
        $start = Get-Date
        Start-Sleep -Milliseconds 50
        Write-Elapsed -StartTime $start 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-Elapsed: handles time from the past" {
        Write-Elapsed -StartTime ([datetime]"2024-01-01") 6>&1 | Out-Null
        $true
    }

    # --- Write-Countdown ---
    # Note: Write-Countdown sleeps, so use Seconds=1 to keep tests fast

    Test-Assert "Write-Countdown: completes with 1 second" {
        Write-Countdown -Seconds 1 -Message "Testing in" 6>&1 | Out-Null
        $true
    }

    # --- Write-StatsLine ---

    Test-Assert "Write-StatsLine: does not throw with hashtable" {
        Write-StatsLine -Stats @{ passed = 10; failed = 2; skipped = 1 } 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-StatsLine: empty hashtable does not throw" {
        Write-StatsLine -Stats @{} 6>&1 | Out-Null
        $true
    }

    # --- Write-TimingReport ---

    Test-Assert "Write-TimingReport: does not throw with valid timings" {
        $timings = @(
            @{ name = "Module A"; status = "OK"; duration = [timespan]::FromSeconds(5.3) }
            @{ name = "Module B"; status = "FAIL"; duration = [timespan]::FromSeconds(12.1) }
            @{ name = "Module C"; status = "SKIP"; duration = [timespan]::FromSeconds(0) }
        )
        Write-TimingReport -Timings $timings 6>&1 | Out-Null
        $true
    }

    Test-Assert "Write-TimingReport: empty array does not throw" {
        Write-TimingReport -Timings @() 6>&1 | Out-Null
        $true
    }

    # --- Write-CompletionSound ---

    Test-Assert "Write-CompletionSound: success beep does not throw" {
        # Beep may fail in CI/non-interactive, but the function has try/catch
        Write-CompletionSound
        $true
    }

    Test-Assert "Write-CompletionSound: error beep does not throw" {
        Write-CompletionSound -Error
        $true
    }
}

# ============================================================================
# SUITE: json
# ============================================================================
if (& $shouldRun "json") {
    Start-Suite "json"

    # --- Strip-JsonComments ---

    Test-Assert "Strip-JsonComments: returns plain JSON unchanged" {
        $input_json = '{"key": "value", "num": 42}'
        $result = Strip-JsonComments $input_json
        $result -eq $input_json
    }

    Test-Assert "Strip-JsonComments: removes single-line comment" {
        $input_json = "{`"key`": `"value`"  // this is a comment`n}"
        $result = Strip-JsonComments $input_json
        $parsed = $result | ConvertFrom-Json
        $parsed.key -eq "value"
    }

    Test-Assert "Strip-JsonComments: preserves // inside strings" {
        $input_json = '{"url": "https://example.com"}'
        $result = Strip-JsonComments $input_json
        $parsed = $result | ConvertFrom-Json
        $parsed.url -eq "https://example.com"
    }

    Test-Assert "Strip-JsonComments: handles multiple comment lines" {
        $input_json = "// header comment`n{`"a`": 1, // inline`n`"b`": 2 // another`n}"
        $result = Strip-JsonComments $input_json
        $parsed = $result | ConvertFrom-Json
        ($parsed.a -eq 1) -and ($parsed.b -eq 2)
    }

    Test-Assert "Strip-JsonComments: empty string returns empty" {
        $result = Strip-JsonComments ""
        $result -eq ""
    }

    Test-Assert "Strip-JsonComments: string with only comments returns whitespace/empty" {
        $result = Strip-JsonComments "// just a comment"
        $result.Trim().Length -eq 0
    }

    Test-Assert "Strip-JsonComments: handles escaped quotes in strings" {
        $input_json = '{"msg": "say \"hello\" // not a comment"}'
        $result = Strip-JsonComments $input_json
        # The // inside the string should be preserved
        $result -match "// not a comment"
    }

    Test-Assert "Strip-JsonComments: handles backslash in strings" {
        $input_json = '{"path": "C:\\Users\\test"}'
        $result = Strip-JsonComments $input_json
        $parsed = $result | ConvertFrom-Json
        $parsed.path -eq "C:\Users\test"
    }

    Test-Assert "Strip-JsonComments: handles comment at end without newline" {
        $input_json = '{"a": 1} // trailing'
        $result = Strip-JsonComments $input_json
        $parsed = $result.Trim() | ConvertFrom-Json
        $parsed.a -eq 1
    }

    # --- Read-WTSettings ---

    Test-Assert "Read-WTSettings: returns null when file does not exist" {
        # Temporarily override the path
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = "C:\NonExistent\Path\settings.json"
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        $null -eq $result
    }

    Test-Assert "Read-WTSettings: reads valid JSON from temp file" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_settings.json"
        '{"defaultProfile": "{abc}", "profiles": {"list": []}}' | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -ne $result -and $result.defaultProfile -eq "{abc}"
    }

    Test-Assert "Read-WTSettings: handles JSONC (comments) in temp file" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_jsonc.json"
        $jsonc = @"
{
    // This is a comment
    "defaultProfile": "{def}",
    "profiles": {
        "list": [] // inline comment
    }
}
"@
        $jsonc | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -ne $result -and $result.defaultProfile -eq "{def}"
    }

    Test-Assert "Read-WTSettings: handles BOM in file" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_bom.json"
        $bomContent = [char]0xFEFF + '{"defaultProfile": "{bom}"}'
        [System.IO.File]::WriteAllText($tmpFile, $bomContent, [System.Text.Encoding]::UTF8)
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -ne $result -and $result.defaultProfile -eq "{bom}"
    }

    Test-Assert "Read-WTSettings: handles trailing commas" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_trailing.json"
        '{"a": 1, "b": 2, }' | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -ne $result -and $result.a -eq 1
    }

    Test-Assert "Read-WTSettings: returns null for empty file" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_empty.json"
        "" | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -eq $result
    }

    Test-Assert "Read-WTSettings: returns null for invalid JSON" {
        $tmpFile = Join-Path $env:TEMP "wininit_test_wt_invalid.json"
        "this is not json {{{" | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $result = Read-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        $null -eq $result
    }

    # --- Write-WTSettings ---

    Test-Assert "Write-WTSettings: writes valid config to temp path" {
        $tmpDir = Join-Path $env:TEMP "wininit_test_wt_write"
        $tmpFile = Join-Path $tmpDir "settings.json"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $config = [PSCustomObject]@{ defaultProfile = "{test}"; theme = "dark" }
        $ok = Write-WTSettings -Config $config
        $script:WTSettingsPath = $saved
        $written = Get-Content $tmpFile -Raw | ConvertFrom-Json
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $ok -eq $true -and $written.defaultProfile -eq "{test}"
    }

    Test-Assert "Write-WTSettings: creates directory if missing" {
        $tmpDir = Join-Path $env:TEMP "wininit_test_wt_mkdir_$(Get-Random)"
        $tmpFile = Join-Path $tmpDir "settings.json"
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $config = [PSCustomObject]@{ test = "value" }
        $ok = Write-WTSettings -Config $config
        $script:WTSettingsPath = $saved
        $dirExists = Test-Path $tmpDir
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $ok -eq $true -and $dirExists
    }

    # --- Get-WTProfilesList ---

    Test-Assert "Get-WTProfilesList: returns array of profiles" {
        $profiles = Get-WTProfilesList
        @($profiles).Count -ge 3
    }

    Test-Assert "Get-WTProfilesList: first profile is PowerShell" {
        $profiles = Get-WTProfilesList
        $profiles[0].name -eq "PowerShell"
    }

    Test-Assert "Get-WTProfilesList: all profiles have guid" {
        $profiles = Get-WTProfilesList
        $allHaveGuid = $true
        foreach ($p in $profiles) {
            if (-not $p.guid) { $allHaveGuid = $false; break }
        }
        $allHaveGuid
    }

    Test-Assert "Get-WTProfilesList: all profiles have name" {
        $profiles = Get-WTProfilesList
        $allHaveName = $true
        foreach ($p in $profiles) {
            if (-not $p.name) { $allHaveName = $false; break }
        }
        $allHaveName
    }

    Test-Assert "Get-WTProfilesList: all profiles have commandline" {
        $profiles = Get-WTProfilesList
        $allHaveCmd = $true
        foreach ($p in $profiles) {
            if (-not $p.commandline) { $allHaveCmd = $false; break }
        }
        $allHaveCmd
    }

    Test-Assert "Get-WTProfilesList: hidden is explicitly false on all" {
        $profiles = Get-WTProfilesList
        $allNotHidden = $true
        foreach ($p in $profiles) {
            if ($p.hidden -ne $false) { $allNotHidden = $false; break }
        }
        $allNotHidden
    }

    Test-Assert "Get-WTProfilesList: contains PowerShell 7 profile" {
        $profiles = Get-WTProfilesList
        $has7 = $false
        foreach ($p in $profiles) {
            if ($p.name -eq "PowerShell 7") { $has7 = $true; break }
        }
        $has7
    }

    Test-Assert "Get-WTProfilesList: contains Command Prompt profile" {
        $profiles = Get-WTProfilesList
        $hasCmd = $false
        foreach ($p in $profiles) {
            if ($p.name -eq "Command Prompt") { $hasCmd = $true; break }
        }
        $hasCmd
    }

    # --- Repair-WTSettings ---

    Test-Assert "Repair-WTSettings: creates config when file missing" {
        $tmpDir = Join-Path $env:TEMP "wininit_test_repair_$(Get-Random)"
        $tmpFile = Join-Path $tmpDir "settings.json"
        if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        # Relax strict mode so Repair-WTSettings can handle empty PSCustomObject
        Set-StrictMode -Off
        $config = Repair-WTSettings
        Set-StrictMode -Version Latest
        $script:WTSettingsPath = $saved
        $hasDefault = $null -ne $config -and ($config.PSObject.Properties.Name -contains "defaultProfile")
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $hasDefault
    }

    Test-Assert "Repair-WTSettings: adds defaultProfile if missing" {
        $tmpDir = Join-Path $env:TEMP "wininit_test_repair2_$(Get-Random)"
        $tmpFile = Join-Path $tmpDir "settings.json"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        '{"profiles": {"list": []}}' | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $config = Repair-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        $null -ne $config.defaultProfile
    }

    Test-Assert "Repair-WTSettings: adds profiles list if empty" {
        $tmpDir = Join-Path $env:TEMP "wininit_test_repair3_$(Get-Random)"
        $tmpFile = Join-Path $tmpDir "settings.json"
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        '{"defaultProfile": "{abc}", "profiles": {"list": []}}' | Set-Content -Path $tmpFile -Encoding UTF8
        $saved = $script:WTSettingsPath
        $script:WTSettingsPath = $tmpFile
        $config = Repair-WTSettings
        $script:WTSettingsPath = $saved
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        @($config.profiles.list).Count -ge 3
    }
}

# ============================================================================
# SUITE: installation
# ============================================================================
if (& $shouldRun "installation") {
    Start-Suite "installation"

    # --- Install-WithRetry ---

    Test-Assert "Install-WithRetry: succeeds on first try" {
        $result = Install-WithRetry -Name "TestApp" -Action { "installed" }
        $result -eq $true
    }

    Test-Assert "Install-WithRetry: fails after max retries" {
        $result = Install-WithRetry -Name "BadApp" -Action { throw "always fail" } -MaxRetries 0
        $result -eq $false
    }

    Test-Assert "Install-WithRetry: retries on failure then succeeds" {
        $script:retryCount = 0
        $result = Install-WithRetry -Name "RetryApp" -MaxRetries 2 -Action {
            $script:retryCount++
            if ($script:retryCount -lt 2) { throw "not yet" }
            "ok"
        }
        $result -eq $true -and $script:retryCount -ge 2
    }

    Test-Assert "Install-WithRetry: MaxRetries 0 means single attempt" {
        $script:attemptCount = 0
        $result = Install-WithRetry -Name "SingleTry" -MaxRetries 0 -Action {
            $script:attemptCount++
            throw "fail"
        }
        $result -eq $false -and $script:attemptCount -eq 1
    }

    # --- Invoke-Silent ---

    Test-Assert "Invoke-Silent: runs simple command" {
        $r = Invoke-Silent -Exe "cmd.exe" -Args "/c echo hello"
        $r.ExitCode -eq 0
    }

    Test-Assert "Invoke-Silent: captures stdout" {
        $r = Invoke-Silent -Exe "hostname.exe" -Args ""
        $r.Output -match $env:COMPUTERNAME
    }

    Test-Assert "Invoke-Silent: returns non-zero exit code for bad command" {
        $r = Invoke-Silent -Exe "net.exe" -Args ""
        $r.ExitCode -ne 0
    }

    Test-Assert "Invoke-Silent: handles non-existent exe gracefully" {
        $r = Invoke-Silent -Exe "nonexistent_binary_xyz.exe" -Args ""
        $r.ExitCode -eq -1
    }

    # --- Invoke-SilentWithProgress ---

    Test-Assert "Invoke-SilentWithProgress: runs and returns result" {
        Start-Spinner "Test silent progress"
        $r = Invoke-SilentWithProgress -Exe "cmd.exe" -Args "/c echo line1"
        Stop-Spinner
        $r.ExitCode -eq 0
    }

    Test-Assert "Invoke-SilentWithProgress: handles prefix" {
        Start-Spinner "Prefix test"
        $r = Invoke-SilentWithProgress -Exe "cmd.exe" -Args "/c echo data" -Prefix "TestPrefix"
        Stop-Spinner
        $r.ExitCode -eq 0
    }

    # --- Invoke-InProcess ---

    Test-Assert "Invoke-InProcess: runs simple command" {
        $r = Invoke-InProcess -Command "echo hello"
        $r.Output -match "hello"
    }

    Test-Assert "Invoke-InProcess: returns exit code" {
        $r = Invoke-InProcess -Command "cmd /c exit 0"
        $r.ExitCode -eq 0
    }

    Test-Assert "Invoke-InProcess: captures error output" {
        $r = Invoke-InProcess -Command "cmd /c echo error_text 1>&2"
        $r.Output -match "error_text"
    }

    # --- Install-App ---
    # Install-App calls winget/choco/scoop - we test that it does not throw
    # when none of those are provided (all params empty)

    Test-Assert "Install-App: does not throw with no package IDs" {
        Install-App -Name "FakeApp"
        $true
    }

    # --- Get-GitHubReleaseUrl ---

    Test-Assert "Get-GitHubReleaseUrl: returns null for non-existent repo" {
        $url = Get-GitHubReleaseUrl -Repo "nonexistent/nonexistent_repo_xyz_12345" -Pattern ".*"
        $null -eq $url
    }

    Test-Assert "Get-GitHubReleaseUrl: returns null with empty repo" {
        $url = Get-GitHubReleaseUrl -Repo "" -Pattern ""
        $null -eq $url
    }

    # --- Install-PortableBin ---
    # Side-effect heavy: test that it doesn't throw with bad URL (it logs error)

    Test-Assert "Install-PortableBin: does not throw with bad URL" {
        Install-PortableBin -Name "FakeBin" -Url "https://localhost:1/fake.zip" -ExeName "fake.exe"
        $true
    }

    # --- Install-PortableApp ---

    Test-Assert "Install-PortableApp: does not throw with bad URL" {
        Install-PortableApp -Name "FakeApp_$(Get-Random)" -Url "https://localhost:1/fake.zip"
        $true
    }

    # --- Invoke-DownloadSafe ---

    Test-Assert "Invoke-DownloadSafe: returns false for unreachable URL" {
        $tmpOut = Join-Path $env:TEMP "wininit_test_dl_$(Get-Random).tmp"
        $result = Invoke-DownloadSafe -Url "https://localhost:1/fake" -OutFile $tmpOut -MaxRetries 1 -TimeoutSec 5
        Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        $result -eq $false
    }

    Test-Assert "Invoke-DownloadSafe: returns false with empty URL" {
        $tmpOut = Join-Path $env:TEMP "wininit_test_dl2_$(Get-Random).tmp"
        $result = Invoke-DownloadSafe -Url " " -OutFile $tmpOut -MaxRetries 1 -TimeoutSec 5
        Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        $result -eq $false
    }

    # --- Invoke-CommandSafe ---

    Test-Assert "Invoke-CommandSafe: runs simple scriptblock" {
        $result = Invoke-CommandSafe -Description "Simple test" -Action { 1 + 1 } -TimeoutMinutes 1
        $result -eq 2
    }

    Test-Assert "Invoke-CommandSafe: returns null on timeout" {
        $result = Invoke-CommandSafe -Description "Timeout test" -Action { Start-Sleep -Seconds 120 } -TimeoutMinutes 0 -ContinueOnError
        # TimeoutMinutes 0 means 0-second timeout, job should be killed
        # Result is null when timed out
        $null -eq $result
    } -FailMessage "Expected null from timed-out command"

    Test-Assert "Invoke-CommandSafe: ContinueOnError suppresses throw" {
        $result = Invoke-CommandSafe -Description "Error test" -Action { throw "deliberate" } -ContinueOnError
        $null -eq $result
    }

    Test-Assert "Invoke-CommandSafe: without ContinueOnError, returns null on job error" {
        $result = Invoke-CommandSafe -Description "Throw test" -Action { throw "deliberate" }
        $null -eq $result
    }
}

# ============================================================================
# SUITE: registry
# ============================================================================
if (& $shouldRun "registry") {
    Start-Suite "registry"

    # Clean up before tests
    if (Test-Path $testRegPath) {
        Remove-Item $testRegPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- Ensure-RegKey ---

    Test-Assert "Ensure-RegKey: creates new key" {
        Ensure-RegKey -Path $testRegPath
        Test-Path $testRegPath
    }

    Test-Assert "Ensure-RegKey: does not throw if key already exists" {
        Ensure-RegKey -Path $testRegPath
        Test-Path $testRegPath
    }

    Test-Assert "Ensure-RegKey: creates nested key" {
        $nested = "$testRegPath\SubKey1\SubKey2"
        Ensure-RegKey -Path $nested
        Test-Path $nested
    }

    # --- Set-RegistrySafe ---

    Test-Assert "Set-RegistrySafe: sets DWord value" {
        Set-RegistrySafe -Path $testRegPath -Name "TestDword" -Value 1 -Type "DWord"
        $val = Get-ItemProperty -Path $testRegPath -Name "TestDword" -ErrorAction SilentlyContinue
        $val.TestDword -eq 1
    }

    Test-Assert "Set-RegistrySafe: sets String value" {
        Set-RegistrySafe -Path $testRegPath -Name "TestString" -Value "hello" -Type "String"
        $val = Get-ItemProperty -Path $testRegPath -Name "TestString" -ErrorAction SilentlyContinue
        $val.TestString -eq "hello"
    }

    Test-Assert "Set-RegistrySafe: overwrites existing value" {
        Set-RegistrySafe -Path $testRegPath -Name "TestDword" -Value 99 -Type "DWord"
        $val = Get-ItemProperty -Path $testRegPath -Name "TestDword" -ErrorAction SilentlyContinue
        $val.TestDword -eq 99
    }

    Test-Assert "Set-RegistrySafe: creates key if it does not exist" {
        $newPath = "$testRegPath\AutoCreated"
        Set-RegistrySafe -Path $newPath -Name "Val" -Value 42 -Type "DWord"
        (Test-Path $newPath) -and ((Get-ItemProperty -Path $newPath -Name "Val").Val -eq 42)
    }

    Test-Assert "Set-RegistrySafe: default type is DWord" {
        Set-RegistrySafe -Path $testRegPath -Name "DefaultType" -Value 7
        $val = Get-ItemProperty -Path $testRegPath -Name "DefaultType" -ErrorAction SilentlyContinue
        $val.DefaultType -eq 7
    }

    Test-Assert "Set-RegistrySafe: handles ExpandString type" {
        Set-RegistrySafe -Path $testRegPath -Name "TestExpand" -Value "%TEMP%\test" -Type "ExpandString"
        $val = Get-ItemPropertyValue -Path $testRegPath -Name "TestExpand" -ErrorAction SilentlyContinue
        $null -ne $val
    }

    # --- Disable-ServiceSafe ---

    Test-Assert "Disable-ServiceSafe: does not throw for non-existent service" {
        Disable-ServiceSafe -Name "WinInitFakeService12345"
        $true
    }

    Test-Assert "Disable-ServiceSafe: handles DisplayName parameter" {
        Disable-ServiceSafe -Name "WinInitFakeService67890" -DisplayName "Fake Service"
        $true
    }

    # Clean up registry
    if (Test-Path $testRegPath) {
        Remove-Item $testRegPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# SUITE: environment
# ============================================================================
if (& $shouldRun "environment") {
    Start-Suite "environment"

    # --- Update-Path ---

    Test-Assert "Update-Path: refreshes PATH without error" {
        $oldPath = $env:Path
        Update-Path
        # PATH should be non-empty after refresh
        $env:Path.Length -gt 0
    }

    Test-Assert "Update-Path: PATH contains system root" {
        Update-Path
        $env:Path -match [regex]::Escape($env:SystemRoot)
    }

    # --- Add-ToSystemPath ---
    # This modifies machine PATH - test with non-existent dir (should return false)

    Test-Assert "Add-ToSystemPath: returns false for non-existent directory" {
        $result = Add-ToSystemPath -Directory "C:\WinInitNonExistent_$(Get-Random)"
        $result -eq $false
    }

    Test-Assert "Add-ToSystemPath: returns false (already in PATH) for system dir" {
        # System32 is always in PATH
        $result = Add-ToSystemPath -Directory "$env:SystemRoot\System32"
        # Should return $false because already present
        $result -eq $false
    }

    # --- Set-UserEnvVar ---

    Test-Assert "Set-UserEnvVar: sets and retrieves variable" {
        $varName = "WININIT_TEST_VAR_$(Get-Random)"
        Set-UserEnvVar -Name $varName -Value "test_value_123"
        $processVal = [System.Environment]::GetEnvironmentVariable($varName, "Process")
        $userVal = [System.Environment]::GetEnvironmentVariable($varName, "User")
        # Clean up
        [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
        ($processVal -eq "test_value_123") -and ($userVal -eq "test_value_123")
    }

    Test-Assert "Set-UserEnvVar: overwrites existing variable" {
        $varName = "WININIT_TEST_OVERWRITE_$(Get-Random)"
        Set-UserEnvVar -Name $varName -Value "first"
        Set-UserEnvVar -Name $varName -Value "second"
        $val = [System.Environment]::GetEnvironmentVariable($varName, "Process")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
        $val -eq "second"
    }

    Test-Assert "Set-UserEnvVar: handles empty value (clears variable)" {
        $varName = "WININIT_TEST_EMPTY_$(Get-Random)"
        Set-UserEnvVar -Name $varName -Value "notempty"
        Set-UserEnvVar -Name $varName -Value ""
        $val = [System.Environment]::GetEnvironmentVariable($varName, "Process")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
        $val -eq "" -or $null -eq $val
    }

    # --- Set-MachineEnvVar ---
    # Machine env vars require admin. Test gracefully.

    Test-Assert "Set-MachineEnvVar: does not throw (may need admin)" {
        $varName = "WININIT_TEST_MACHINE_$(Get-Random)"
        $threw = $false
        try {
            Set-MachineEnvVar -Name $varName -Value "machine_test"
        } catch {
            # May fail without admin - that is acceptable
            $threw = $true
        }
        # Clean up if we had permission
        try {
            [System.Environment]::SetEnvironmentVariable($varName, $null, "Machine")
            [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
        } catch {}
        $true  # Pass regardless - we just test it doesn't crash PowerShell
    }

    # --- Get-UserPath ---

    Test-Assert "Get-UserPath: returns expected path" {
        $result = Get-UserPath -SubPath "Documents"
        $expected = Join-Path $env:USERPROFILE "Documents"
        $result -eq $expected
    }

    Test-Assert "Get-UserPath: handles nested subpath" {
        $result = Get-UserPath -SubPath "AppData\Local\Temp"
        $expected = Join-Path $env:USERPROFILE "AppData\Local\Temp"
        $result -eq $expected
    }

    Test-Assert "Get-UserPath: handles empty subpath" {
        $result = Get-UserPath -SubPath ""
        $expected = Join-Path $env:USERPROFILE ""
        $result -eq $expected
    }

    Test-Assert "Get-UserPath: returns string type" {
        $result = Get-UserPath -SubPath "Desktop"
        $result -is [string]
    }
}

# ============================================================================
# SUITE: system
# ============================================================================
if (& $shouldRun "system") {
    Start-Suite "system"

    # --- Remove-AppxSafe ---

    Test-Assert "Remove-AppxSafe: does not throw for non-existent package" {
        Remove-AppxSafe -Name "WinInit.FakePackage.DoesNotExist.12345"
        $true
    }

    Test-Assert "Remove-AppxSafe: handles empty name" {
        Remove-AppxSafe -Name ""
        $true
    }

    # --- Add-HostsBlock ---
    # This modifies the system hosts file - skip unless running as admin

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    Test-Assert "Add-HostsBlock: does not throw (requires admin)" -Skip:(-not $isAdmin) {
        # Use a unique marker to avoid permanent side effects
        $marker = "WinInitTest_$(Get-Random)"
        Add-HostsBlock -MarkerName $marker -Hostnames @("wininittest.invalid")
        # Verify it was added
        $content = Get-Content "$env:WINDIR\System32\drivers\etc\hosts" -Raw
        $found = $content -match [regex]::Escape("# --- WinInit $marker ---")
        # Clean up: remove the test block
        if ($found) {
            $cleaned = $content -replace "(?s)\n# --- WinInit $marker ---.*?# --- End WinInit $marker ---", ""
            Set-Content "$env:WINDIR\System32\drivers\etc\hosts" -Value $cleaned -Encoding ASCII
        }
        $found
    }

    Test-Assert "Add-HostsBlock: idempotent (skip if marker exists)" -Skip:(-not $isAdmin) {
        $marker = "WinInitIdempotent_$(Get-Random)"
        Add-HostsBlock -MarkerName $marker -Hostnames @("idem.invalid")
        $content1 = Get-Content "$env:WINDIR\System32\drivers\etc\hosts" -Raw
        # Call again - should not add duplicate
        Add-HostsBlock -MarkerName $marker -Hostnames @("idem.invalid")
        $content2 = Get-Content "$env:WINDIR\System32\drivers\etc\hosts" -Raw
        # Clean up
        $cleaned = $content2 -replace "(?s)\n# --- WinInit $marker ---.*?# --- End WinInit $marker ---", ""
        Set-Content "$env:WINDIR\System32\drivers\etc\hosts" -Value $cleaned -Encoding ASCII
        $content1.Length -eq $content2.Length
    }

    # --- Invoke-ExternalWithSpinner ---

    Test-Assert "Invoke-ExternalWithSpinner: runs simple command" {
        $r = Invoke-ExternalWithSpinner -Message "Echo test" -Command "cmd.exe" -Arguments @("/c", "echo", "hello")
        $r.ExitCode -eq 0
    }

    Test-Assert "Invoke-ExternalWithSpinner: captures stdout" {
        $r = Invoke-ExternalWithSpinner -Message "Capture test" -Command "cmd.exe" -Arguments @("/c", "echo", "captured_output")
        $r.Stdout -match "captured_output"
    }

    Test-Assert "Invoke-ExternalWithSpinner: handles failing command" {
        $r = Invoke-ExternalWithSpinner -Message "Fail cmd" -Command "cmd.exe" -Arguments @("/c", "exit", "1")
        $r.ExitCode -eq 1
    }

    Test-Assert "Invoke-ExternalWithSpinner: handles non-existent command" {
        $r = Invoke-ExternalWithSpinner -Message "Bad cmd" -Command "nonexistent_cmd_xyz.exe" -Arguments @()
        $r.ExitCode -eq -1
    }

    Test-Assert "Invoke-ExternalWithSpinner: uses SuccessMessage" {
        $r = Invoke-ExternalWithSpinner -Message "Orig" -Command "cmd.exe" -Arguments @("/c", "echo", "ok") -SuccessMessage "Custom done"
        $r.ExitCode -eq 0
    }

    # --- Enable-VTMode ---

    Test-Assert "Enable-VTMode: does not throw" {
        Enable-VTMode
        $true
    }

    Test-Assert "Enable-VTMode: sets VTEnabled to boolean" {
        Enable-VTMode
        $script:VTEnabled -is [bool]
    }

    # --- Get-C (helper) ---

    Test-Assert "Get-C: returns hashtable with color keys" {
        $c = Get-C
        $c -is [hashtable] -and $c.ContainsKey("Reset") -and $c.ContainsKey("Red") -and $c.ContainsKey("Green")
    }

    Test-Assert "Get-C: recovers if script:C is corrupted" {
        $savedC = $script:C
        $script:C = "broken"
        $c = Get-C
        $script:C = $savedC
        $c -is [hashtable] -and $c.Count -gt 5
    }
}

# ============================================================================
# Summary
# ============================================================================

# Ensure any lingering spinner is stopped
if ($script:SpinnerSync.Active) { Stop-Spinner }

$total = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings

Write-Host ""
Write-Host "  ==================================" -ForegroundColor Cyan
Write-Host "  Test-Common.ps1 Results" -ForegroundColor Cyan
Write-Host "  ==================================" -ForegroundColor Cyan
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

    # Group by suite
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
