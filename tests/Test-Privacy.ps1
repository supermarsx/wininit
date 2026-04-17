# ============================================================================
# WinInit Test Suite: Privacy Module (07-Privacy.ps1) Validation
# Validates registry paths, telemetry hosts, privacy categories, and risk levels
# Standalone test script that can run independently.
#
# Usage:
#   .\tests\Test-Privacy.ps1                     Run all tests
#   .\tests\Test-Privacy.ps1 -Suite structure    Run structure validation
#   .\tests\Test-Privacy.ps1 -Suite categories   Run privacy category tests
#   .\tests\Test-Privacy.ps1 -Suite hosts        Run telemetry hosts tests
#   .\tests\Test-Privacy.ps1 -Suite risk         Run risk level tests
#   .\tests\Test-Privacy.ps1 -Verbose            Show timing details
#   .\tests\Test-Privacy.ps1 -JUnit results.xml  Export JUnit XML
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
# Banner
# ============================================================================

Write-Host ""
Write-Host "  WinInit Privacy Module Test Suite" -ForegroundColor Cyan
Write-Host "  ==================================" -ForegroundColor Cyan
$modeStr = if ($DryRun) { "DRY RUN" } elseif ($Suite) { "Suite: $Suite" } else { "Full" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Load module content for static analysis (we do NOT execute the module)
# ============================================================================

$privacyModulePath = Join-Path $projectRoot "modules\07-Privacy.ps1"
$privacyContent = ""
if (Test-Path $privacyModulePath) {
    $privacyContent = Get-Content $privacyModulePath -Raw -ErrorAction SilentlyContinue
}

# ============================================================================
# SUITE: structure
# ============================================================================
if (& $shouldRun "structure") {
    Start-Suite "structure"

    Test-Assert "07-Privacy.ps1 exists" {
        Test-Path $privacyModulePath
    }

    Test-Assert "07-Privacy.ps1 is non-empty" {
        $privacyContent.Length -gt 100
    }

    Test-Assert "07-Privacy.ps1 has Write-Section call" {
        $privacyContent -match 'Write-Section'
    }

    Test-Assert "07-Privacy.ps1 has Write-Log calls" {
        $privacyContent -match 'Write-Log'
    }

    Test-Assert "07-Privacy.ps1 has Write-RiskLog calls" {
        $privacyContent -match 'Write-RiskLog'
    }

    Test-Assert "07-Privacy.ps1 has module completion message" {
        $privacyContent -match 'Module 07-Privacy completed|07-Privacy.*completed|Privacy.*completed'
    }

    Test-Assert "07-Privacy.ps1 has BlockTelemetryHosts flag" {
        $privacyContent -match '\$script:BlockTelemetryHosts'
    }

    Test-Assert "07-Privacy.ps1 defines Block-TelemetryHosts function" {
        $privacyContent -match 'function Block-TelemetryHosts'
    }
}

# ============================================================================
# SUITE: categories
# ============================================================================
if (& $shouldRun "categories") {
    Start-Suite "categories"

    # Each privacy category should be present in the module
    $expectedCategories = @{
        "Wi-Fi Sense"           = "Wi-?Fi.?Sense|WifiSense|AutoConnectAllowedOEM"
        "Clipboard sync"        = "Clipboard|AllowCrossDeviceClipboard|ClipboardHistory"
        "Timeline"              = "Timeline|EnableActivityFeed|PublishUserActivities"
        "SmartScreen"           = "SmartScreen|EnableSmartScreen"
        "Delivery Optimization" = "DeliveryOptimization|DODownloadMode"
        "Telemetry"             = "telemetry|AllowTelemetry|DataCollection"
        "DiagTrack service"     = "DiagTrack"
        "WAP Push service"      = "dmwappushservice|WAP Push"
        "CEIP"                  = "CEIP|CEIPEnable|SQMClient"
        "App Impact Telemetry"  = "AITEnable|AppCompat"
        "Steps Recorder"        = "StepsRecorder|DisableStepsRecorder"
        "Inventory Collector"   = "DisableInventory|Inventory"
        "Advertising ID"        = "AdvertisingInfo|AdvertisingId"
        "Location tracking"     = "DisableLocation|LocationAndSensors"
        "Camera defaults"       = "webcam|camera"
        "Microphone defaults"   = "microphone"
        "Inking and typing"     = "InkCollection|InputPersonalization|TextCollection"
        "Handwriting data"      = "HandwritingDataSharing|TabletPC"
        "Tailored experiences"  = "TailoredExperiences|CloudContent"
        "Windows tips"          = "DisableSoftLanding|tips"
        "Windows Spotlight"     = "WindowsSpotlight|Spotlight"
        "Error Reporting"       = "ErrorReporting|WerSvc|WER"
        "Cortana"               = "AllowCortana|Cortana"
        "Web search"            = "DisableWebSearch|WebSearch"
        "Copilot"               = "Copilot|WindowsCopilot"
        "Windows Recall"        = "Recall|WindowsAI|DisableAIDataAnalysis"
        "Feedback"              = "Feedback|SIUF|NumberOfSIUFInPeriod"
        "Telemetry hosts"       = "telemetryHosts|hosts file|vortex\.data\.microsoft"
    }

    foreach ($category in $expectedCategories.Keys) {
        $pattern = $expectedCategories[$category]
        Test-Assert "Privacy category: $category is covered" {
            $privacyContent -match $pattern
        }
    }

    # --- Test: total privacy tweak count ---
    Test-Assert "Privacy: total Write-RiskLog calls >= 30" {
        $matches = [regex]::Matches($privacyContent, 'Write-RiskLog')
        $matches.Count -ge 30
    } -FailMessage "Found $([regex]::Matches($privacyContent, 'Write-RiskLog').Count) Write-RiskLog calls, expected >= 30"

    # --- Test: total Set-ItemProperty calls (registry tweaks) ---
    Test-Assert "Privacy: total Set-ItemProperty calls >= 25" {
        $matches = [regex]::Matches($privacyContent, 'Set-ItemProperty')
        $matches.Count -ge 25
    } -FailMessage "Found $([regex]::Matches($privacyContent, 'Set-ItemProperty').Count) Set-ItemProperty calls, expected >= 25"
}

# ============================================================================
# SUITE: registry-paths
# ============================================================================
if (& $shouldRun "registry-paths") {
    Start-Suite "registry-paths"

    # Extract all registry paths from the module (HKLM and HKCU paths)
    $regPathMatches = [regex]::Matches($privacyContent, '(HK(?:LM|CU):\\[^"''\s]+)')
    $regPaths = @($regPathMatches | ForEach-Object { $_.Value } | Select-Object -Unique)

    Test-Assert "Privacy: contains HKLM registry paths" {
        ($regPaths | Where-Object { $_ -like "HKLM:*" }).Count -gt 0
    }

    Test-Assert "Privacy: contains HKCU registry paths" {
        ($regPaths | Where-Object { $_ -like "HKCU:*" }).Count -gt 0
    }

    Test-Assert "Privacy: registry paths total >= 15 unique" {
        $regPaths.Count -ge 15
    } -FailMessage "Found $($regPaths.Count) unique registry paths, expected >= 15"

    # Validate specific critical registry paths are targeted
    $criticalPaths = @(
        "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
        "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Windows Search",
        "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo",
        "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\LocationAndSensors"
    )

    foreach ($path in $criticalPaths) {
        $escapedPath = [regex]::Escape($path)
        Test-Assert "Privacy: targets path $path" {
            $privacyContent -match $escapedPath
        }
    }

    # --- Test: all registry paths use proper PowerShell drive format ---
    Test-Assert "Privacy: all paths use HKLM: or HKCU: format (not reg.exe)" {
        # Should NOT use reg.exe or HKEY_LOCAL_MACHINE raw paths
        -not ($privacyContent -match 'reg\.exe|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER')
    }

    # --- Test: New-Item -Force is used for paths that may not exist ---
    Test-Assert "Privacy: uses New-Item for paths that may not exist" {
        $privacyContent -match 'New-Item.*-Force'
    }

    # --- Test: ErrorAction SilentlyContinue used on sensitive operations ---
    Test-Assert "Privacy: uses ErrorAction SilentlyContinue on services" {
        $privacyContent -match 'Stop-Service.*-ErrorAction SilentlyContinue'
    }
}

# ============================================================================
# SUITE: hosts
# ============================================================================
if (& $shouldRun "hosts") {
    Start-Suite "hosts"

    # Extract telemetry hosts from the module
    $hostsMatches = [regex]::Matches($privacyContent, '0\.0\.0\.0\s+(\S+)')
    $telemetryHosts = @($hostsMatches | ForEach-Object { $_.Groups[1].Value })

    Test-Assert "Telemetry hosts: list is defined" {
        $telemetryHosts.Count -gt 0
    }

    Test-Assert "Telemetry hosts: at least 15 domains blocked" {
        $telemetryHosts.Count -ge 15
    } -FailMessage "Found $($telemetryHosts.Count) telemetry hosts, expected >= 15"

    Test-Assert "Telemetry hosts: all use 0.0.0.0 format (not 127.0.0.1)" {
        # The module should use 0.0.0.0 which is faster than 127.0.0.1
        $privacyContent -match '0\.0\.0\.0' -and -not ($privacyContent -match '127\.0\.0\.1')
    }

    # Validate key telemetry domains are present
    $expectedHosts = @(
        "vortex.data.microsoft.com",
        "telecommand.telemetry.microsoft.com",
        "telemetry.microsoft.com",
        "watson.telemetry.microsoft.com",
        "settings-win.data.microsoft.com"
    )

    foreach ($host_ in $expectedHosts) {
        Test-Assert "Telemetry hosts: blocks $host_" {
            $host_ -in $telemetryHosts
        }
    }

    # --- Test: hosts file marker is defined ---
    Test-Assert "Telemetry hosts: marker comment is defined" {
        $privacyContent -match 'WinInit Telemetry Block'
    }

    # --- Test: duplicate check is implemented ---
    Test-Assert "Telemetry hosts: checks for existing entries before adding" {
        $privacyContent -match 'Contains.*marker|already present'
    }

    # --- Test: hosts uses correct path ---
    Test-Assert "Telemetry hosts: uses SystemRoot hosts file path" {
        $privacyContent -match 'SystemRoot.*System32.*drivers.*etc.*hosts'
    }

    # --- Test: all hosts are valid domain names ---
    Test-Assert "Telemetry hosts: all entries are valid domain names" {
        $allValid = $true
        foreach ($h in $telemetryHosts) {
            if ($h -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$') {
                $allValid = $false
                break
            }
        }
        $allValid
    }
}

# ============================================================================
# SUITE: risk
# ============================================================================
if (& $shouldRun "risk") {
    Start-Suite "risk"

    # Count risk levels used in the module
    $safeCount = [regex]::Matches($privacyContent, 'Write-RiskLog\s+[^"]*"[^"]*"\s+"safe"').Count
    $moderateCount = [regex]::Matches($privacyContent, 'Write-RiskLog\s+[^"]*"[^"]*"\s+"moderate"').Count
    $aggressiveCount = [regex]::Matches($privacyContent, 'Write-RiskLog\s+[^"]*"[^"]*"\s+"aggressive"').Count

    Test-Assert "Risk: safe tweaks are the majority" {
        $safeCount -gt $moderateCount -and $safeCount -gt $aggressiveCount
    } -FailMessage "Safe=$safeCount, Moderate=$moderateCount, Aggressive=$aggressiveCount"

    Test-Assert "Risk: safe tweak count >= 20" {
        $safeCount -ge 20
    } -FailMessage "Found $safeCount safe tweaks, expected >= 20"

    Test-Assert "Risk: moderate tweak count >= 3" {
        $moderateCount -ge 3
    } -FailMessage "Found $moderateCount moderate tweaks, expected >= 3"

    Test-Assert "Risk: aggressive tweak count >= 2" {
        $aggressiveCount -ge 2
    } -FailMessage "Found $aggressiveCount aggressive tweaks, expected >= 2"

    # --- Test: specific risk assignments are correct ---
    # DiagTrack should be aggressive (disables core Windows telemetry service)
    Test-Assert "Risk: DiagTrack is marked aggressive" {
        $privacyContent -match 'DiagTrack.*"aggressive"|"aggressive".*DiagTrack'
    }

    # Advertising ID should be safe (user preference, easily reversed)
    Test-Assert "Risk: Advertising ID is marked safe" {
        $privacyContent -match 'Advertising.*"safe"|dvertising.*safe'
    }

    # SmartScreen disabling should be moderate (security feature)
    Test-Assert "Risk: SmartScreen is marked moderate" {
        $privacyContent -match 'SmartScreen.*"moderate"|smartscreen.*moderate'
    }

    # Camera/Mic defaults should be moderate
    Test-Assert "Risk: Camera default is marked moderate" {
        $privacyContent -match '[Cc]amera.*"moderate"|camera.*moderate'
    }

    # Cortana should be safe (can be re-enabled)
    Test-Assert "Risk: Cortana is marked safe" {
        $privacyContent -match 'Cortana.*"safe"|cortana.*safe'
    }

    # --- Test: all Write-RiskLog calls use valid risk levels ---
    Test-Assert "Risk: no invalid risk levels used" {
        $allRiskLogs = [regex]::Matches($privacyContent, 'Write-RiskLog\s+"[^"]*"\s+"([^"]+)"')
        $allValid = $true
        foreach ($m in $allRiskLogs) {
            $level = $m.Groups[1].Value
            if ($level -notin @("safe", "moderate", "aggressive")) {
                $allValid = $false
                break
            }
        }
        $allValid
    }

    # --- Test: services marked aggressive have Stop-Service ---
    Test-Assert "Risk: services disabled aggressively also have Stop-Service" {
        # DiagTrack and dmwappushservice should be stopped before disabling
        $privacyContent -match 'Stop-Service.*DiagTrack' -and
        $privacyContent -match 'Stop-Service.*dmwappushservice'
    }
}

# ============================================================================
# Summary
# ============================================================================

$total = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings

Write-Host ""
Write-Host "  ==================================" -ForegroundColor Cyan
Write-Host "  Test-Privacy.ps1 Results" -ForegroundColor Cyan
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
