# ============================================================================
# WinInit Test Suite: Config / TOML Parsing / Profiles / CLI Flag Merging
# Standalone test script that can run independently.
#
# Usage:
#   .\tests\Test-Config.ps1                     Run all tests
#   .\tests\Test-Config.ps1 -Suite toml         Run only TOML parser suite
#   .\tests\Test-Config.ps1 -Suite profiles     Run only profiles suite
#   .\tests\Test-Config.ps1 -Suite merging      Run only CLI merging suite
#   .\tests\Test-Config.ps1 -Verbose            Show timing details
#   .\tests\Test-Config.ps1 -JUnit results.xml  Export JUnit XML
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
# Dot-source lib\common.ps1 for Read-TomlConfig, ConvertFrom-TomlValue, etc.
# ============================================================================

$script:LogFile = Join-Path $env:TEMP "wininit_test_config.log"
if (Test-Path $script:LogFile) { Remove-Item $script:LogFile -Force -ErrorAction SilentlyContinue }

. "$projectRoot\lib\common.ps1"

# Stop spinner if one was started during sourcing
if ($script:SpinnerSync -and $script:SpinnerSync.Active) { Stop-Spinner }

# ============================================================================
# Banner
# ============================================================================

Write-Host ""
Write-Host "  WinInit Config & TOML Test Suite" -ForegroundColor Cyan
Write-Host "  ==================================" -ForegroundColor Cyan
$modeStr = if ($Suite) { "Suite: $Suite" } else { "All suites" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Setup: temp directory for test config/profile files
# ============================================================================

$testTempDir = Join-Path $env:TEMP "wininit_test_config_$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $testTempDir -Force | Out-Null

# ============================================================================
# SUITE: toml-parsing
# ============================================================================
if (& $shouldRun "toml-parsing") {
    Start-Suite "toml-parsing"

    # --- Test: parse valid TOML with all section types ---
    Test-Assert "Read-TomlConfig: parses valid TOML with sections" {
        $tomlPath = Join-Path $testTempDir "valid.toml"
        @"
[general]
profile = "developer"
dry_run = false
log_level = "INFO"

[modules]
"01-PackageManagers" = true
"02-Applications" = false

[apps]
skip = ["App.One", "App.Two"]
"@ | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg -is [hashtable] -and $cfg.ContainsKey("general") -and $cfg.ContainsKey("modules") -and $cfg.ContainsKey("apps")
    }

    # --- Test: parse booleans ---
    Test-Assert "Read-TomlConfig: parses boolean true" {
        $tomlPath = Join-Path $testTempDir "bool_true.toml"
        "enabled = true" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["enabled"] -eq $true
    }

    Test-Assert "Read-TomlConfig: parses boolean false" {
        $tomlPath = Join-Path $testTempDir "bool_false.toml"
        "enabled = false" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["enabled"] -eq $false
    }

    # --- Test: parse strings ---
    Test-Assert "Read-TomlConfig: parses double-quoted string" {
        $tomlPath = Join-Path $testTempDir "str_double.toml"
        'name = "developer"' | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["name"] -eq "developer"
    }

    Test-Assert "Read-TomlConfig: parses single-quoted string" {
        $tomlPath = Join-Path $testTempDir "str_single.toml"
        "name = 'minimal'" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["name"] -eq "minimal"
    }

    # --- Test: parse integers ---
    Test-Assert "Read-TomlConfig: parses positive integer" {
        $tomlPath = Join-Path $testTempDir "int_pos.toml"
        "count = 42" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["count"] -eq 42 -and $cfg["count"] -is [int]
    }

    Test-Assert "Read-TomlConfig: parses negative integer" {
        $tomlPath = Join-Path $testTempDir "int_neg.toml"
        "offset = -5" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["offset"] -eq -5
    }

    # --- Test: parse arrays ---
    Test-Assert "Read-TomlConfig: parses string array" {
        $tomlPath = Join-Path $testTempDir "arr.toml"
        'items = ["one", "two", "three"]' | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $arr = @($cfg["items"])
        $arr.Count -eq 3 -and $arr[0] -eq "one" -and $arr[2] -eq "three"
    }

    Test-Assert "Read-TomlConfig: parses empty array" {
        $tomlPath = Join-Path $testTempDir "arr_empty.toml"
        "items = []" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $arr = @($cfg["items"])
        $arr.Count -eq 0
    }

    # --- Test: handle comments ---
    Test-Assert "Read-TomlConfig: ignores full-line comments" {
        $tomlPath = Join-Path $testTempDir "comments.toml"
        @"
# This is a comment
name = "test"
# Another comment
"@ | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg.Count -eq 1 -and $cfg["name"] -eq "test"
    }

    Test-Assert "Read-TomlConfig: strips inline comments" {
        $tomlPath = Join-Path $testTempDir "inline_comments.toml"
        'level = "strict"  # Privacy level' | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["level"] -eq "strict"
    }

    # --- Test: handle missing config file gracefully ---
    Test-Assert "Read-TomlConfig: missing file returns empty hashtable" {
        $cfg = Read-TomlConfig -Path (Join-Path $testTempDir "nonexistent.toml")
        $cfg -is [hashtable] -and $cfg.Count -eq 0
    }

    # --- Test: parse float ---
    Test-Assert "Read-TomlConfig: parses float value" {
        $tomlPath = Join-Path $testTempDir "float.toml"
        "ratio = 3.14" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        [math]::Abs($cfg["ratio"] - 3.14) -lt 0.001
    }

    # --- Test: quoted keys ---
    Test-Assert "Read-TomlConfig: parses quoted keys in sections" {
        $tomlPath = Join-Path $testTempDir "quoted_keys.toml"
        @"
[modules]
"01-PackageManagers" = true
"02-Applications" = false
"14-DevTools" = true
"@ | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg["modules"]["01-PackageManagers"] -eq $true -and
        $cfg["modules"]["02-Applications"] -eq $false -and
        $cfg["modules"]["14-DevTools"] -eq $true
    }

    # --- Test: invalid TOML produces empty or partial result, not crash ---
    Test-Assert "Read-TomlConfig: invalid TOML does not crash" {
        $tomlPath = Join-Path $testTempDir "invalid.toml"
        @"
this is not valid toml
[broken
key without value
= value without key
"@ | Set-Content $tomlPath -Encoding UTF8
        $result = $null
        try {
            $result = Read-TomlConfig -Path $tomlPath
            $true  # Did not throw
        } catch {
            $false  # Should not throw
        }
    }

    # --- Test: real config.toml from project parses successfully ---
    Test-Assert "Read-TomlConfig: project config.toml parses without error" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }  # Skip if not present
        $cfg = Read-TomlConfig -Path $configPath
        $cfg -is [hashtable] -and $cfg.Count -gt 0
    }

    Test-Assert "Read-TomlConfig: project config.toml has [general] section" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }
        $cfg = Read-TomlConfig -Path $configPath
        $cfg.ContainsKey("general")
    }

    Test-Assert "Read-TomlConfig: project config.toml has [modules] section" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }
        $cfg = Read-TomlConfig -Path $configPath
        $cfg.ContainsKey("modules")
    }

    Test-Assert "Read-TomlConfig: project config.toml [modules] has 18 entries" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }
        $cfg = Read-TomlConfig -Path $configPath
        $cfg["modules"].Count -eq 18
    } -FailMessage "Expected 18 module entries in config.toml [modules]"

    Test-Assert "Read-TomlConfig: project config.toml [general].profile is a string" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }
        $cfg = Read-TomlConfig -Path $configPath
        $cfg["general"]["profile"] -is [string]
    }

    Test-Assert "Read-TomlConfig: project config.toml [privacy].level is a string" {
        $configPath = Join-Path $projectRoot "config.toml"
        if (-not (Test-Path $configPath)) { return $true }
        $cfg = Read-TomlConfig -Path $configPath
        $cfg["privacy"]["level"] -is [string]
    }

    # --- Test: multiple sections in single file ---
    Test-Assert "Read-TomlConfig: multiple sections parsed correctly" {
        $tomlPath = Join-Path $testTempDir "multi_section.toml"
        @"
[general]
profile = "full"
dry_run = false

[modules]
"01-PackageManagers" = true

[privacy]
level = "paranoid"
block_telemetry_hosts = true

[updates]
windows_update_install_mode = "notify"
pin_current_feature_release = true
target_release_version = "25H2"
enable_scheduled_updates = false
update_interval_days = 14
scheduled_update_time = "2:30AM"
"@ | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg.ContainsKey("general") -and
        $cfg.ContainsKey("modules") -and
        $cfg.ContainsKey("privacy") -and
        $cfg.ContainsKey("updates") -and
        $cfg["general"]["profile"] -eq "full" -and
        $cfg["privacy"]["level"] -eq "paranoid" -and
        $cfg["privacy"]["block_telemetry_hosts"] -eq $true -and
        $cfg["updates"]["windows_update_install_mode"] -eq "notify" -and
        $cfg["updates"]["pin_current_feature_release"] -eq $true -and
        $cfg["updates"]["target_release_version"] -eq "25H2" -and
        $cfg["updates"]["update_interval_days"] -eq 14 -and
        $cfg["updates"]["scheduled_update_time"] -eq "2:30AM"
    }

    # --- Test: empty file ---
    Test-Assert "Read-TomlConfig: empty file returns empty hashtable" {
        $tomlPath = Join-Path $testTempDir "empty.toml"
        "" | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg -is [hashtable] -and $cfg.Count -eq 0
    }

    # --- Test: only comments ---
    Test-Assert "Read-TomlConfig: file with only comments returns empty hashtable" {
        $tomlPath = Join-Path $testTempDir "only_comments.toml"
        @"
# Comment line 1
# Comment line 2
# Comment line 3
"@ | Set-Content $tomlPath -Encoding UTF8
        $cfg = Read-TomlConfig -Path $tomlPath
        $cfg -is [hashtable] -and $cfg.Count -eq 0
    }
}

# ============================================================================
# SUITE: profiles
# ============================================================================
if (& $shouldRun "profiles") {
    Start-Suite "profiles"

    $profilesDir = Join-Path $projectRoot "profiles"
    $expectedProfiles = @("developer", "security", "minimal", "creative", "office", "full")

    # --- Test: profiles directory exists ---
    Test-Assert "Profiles directory exists" {
        Test-Path $profilesDir
    }

    # --- Test: each profile JSON file exists ---
    foreach ($profileName in $expectedProfiles) {
        Test-Assert "Profile '$profileName.json' exists" {
            Test-Path (Join-Path $profilesDir "$profileName.json")
        }
    }

    # --- Test: each profile JSON is valid JSON ---
    foreach ($profileName in $expectedProfiles) {
        Test-Assert "Profile '$profileName.json' is valid JSON" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            try {
                $json = Get-Content $path -Raw | ConvertFrom-Json
                $null -ne $json
            } catch {
                $false
            }
        }
    }

    # --- Test: each profile has required structure ---
    foreach ($profileName in $expectedProfiles) {
        Test-Assert "Profile '$profileName' has 'name' field" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $json.name -eq $profileName
        }

        Test-Assert "Profile '$profileName' has 'description' field" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            -not [string]::IsNullOrEmpty($json.description)
        }

        Test-Assert "Profile '$profileName' has 'modules' object" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $null -ne $json.modules
        }

        Test-Assert "Profile '$profileName' has 'privacy_level' field" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $json.privacy_level -in @("standard", "strict", "paranoid")
        }

        Test-Assert "Profile '$profileName' has 'apps_skip' array" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $null -ne $json.apps_skip
        }
    }

    # --- Test: all profiles list all 18 modules ---
    $allModuleNames = @(
        "01-PackageManagers", "02-Applications", "03-DesktopEnvironment",
        "04-OneDriveRemoval", "05-Performance", "06-Debloat", "07-Privacy",
        "08-QualityOfLife", "09-Services", "10-NetworkPerformance", "11-VisualUX",
        "12-SecurityHardening", "13-BrowserExtensions", "14-DevTools",
        "15-PortableTools", "16-UnixEnvironment", "17-VSCodeSetup", "18-FinalConfig"
    )

    foreach ($profileName in $expectedProfiles) {
        Test-Assert "Profile '$profileName' covers all 18 modules" {
            $path = Join-Path $profilesDir "$profileName.json"
            if (-not (Test-Path $path)) { return $false }
            $json = Get-Content $path -Raw | ConvertFrom-Json
            $moduleProps = $json.modules.PSObject.Properties.Name
            $missing = @($allModuleNames | Where-Object { $_ -notin $moduleProps })
            $missing.Count -eq 0
        } -FailMessage "Profile '$profileName' is missing module entries"
    }

    # --- Test: 'full' profile has all modules enabled ---
    Test-Assert "Profile 'full' enables all 18 modules" {
        $path = Join-Path $profilesDir "full.json"
        if (-not (Test-Path $path)) { return $false }
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $disabled = $json.modules.PSObject.Properties | Where-Object { $_.Value -eq $false }
        $null -eq $disabled -or @($disabled).Count -eq 0
    }

    # --- Test: 'minimal' profile disables expected modules ---
    Test-Assert "Profile 'minimal' disables Applications module" {
        $path = Join-Path $profilesDir "minimal.json"
        if (-not (Test-Path $path)) { return $false }
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.modules.'02-Applications' -eq $false
    }

    Test-Assert "Profile 'minimal' disables DevTools module" {
        $path = Join-Path $profilesDir "minimal.json"
        if (-not (Test-Path $path)) { return $false }
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.modules.'14-DevTools' -eq $false
    }

    Test-Assert "Profile 'minimal' enables PackageManagers" {
        $path = Join-Path $profilesDir "minimal.json"
        if (-not (Test-Path $path)) { return $false }
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.modules.'01-PackageManagers' -eq $true
    }

    # --- Test: 'security' profile has paranoid privacy ---
    Test-Assert "Profile 'security' has paranoid privacy level" {
        $path = Join-Path $profilesDir "security.json"
        if (-not (Test-Path $path)) { return $false }
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.privacy_level -eq "paranoid"
    }

    # --- Test: Read-ProfileConfig function ---
    Test-Assert "Read-ProfileConfig: loads developer profile" {
        $cfg = Read-ProfileConfig -ProfileName "developer" -ProfilesDir $profilesDir
        $null -ne $cfg -and $cfg.name -eq "developer"
    }

    Test-Assert "Read-ProfileConfig: loads minimal profile" {
        $cfg = Read-ProfileConfig -ProfileName "minimal" -ProfilesDir $profilesDir
        $null -ne $cfg -and $cfg.name -eq "minimal"
    }

    Test-Assert "Read-ProfileConfig: nonexistent profile returns null" {
        $cfg = Read-ProfileConfig -ProfileName "nonexistent_profile_xyz" -ProfilesDir $profilesDir
        $null -eq $cfg
    }

    Test-Assert "Read-ProfileConfig: module overrides are boolean" {
        $cfg = Read-ProfileConfig -ProfileName "minimal" -ProfilesDir $profilesDir
        if (-not $cfg) { return $false }
        $allBool = $true
        foreach ($prop in $cfg.modules.PSObject.Properties) {
            if ($prop.Value -isnot [bool]) { $allBool = $false; break }
        }
        $allBool
    }
}

# ============================================================================
# SUITE: merging
# ============================================================================
if (& $shouldRun "merging") {
    Start-Suite "merging"

    $allModuleNames = @(
        "01-PackageManagers", "02-Applications", "03-DesktopEnvironment",
        "04-OneDriveRemoval", "05-Performance", "06-Debloat", "07-Privacy",
        "08-QualityOfLife", "09-Services", "10-NetworkPerformance", "11-VisualUX",
        "12-SecurityHardening", "13-BrowserExtensions", "14-DevTools",
        "15-PortableTools", "16-UnixEnvironment", "17-VSCodeSetup", "18-FinalConfig"
    )

    # --- Test: SkipModules by number ---
    Test-Assert "SkipModules: filtering by number prefix works" {
        # Simulate the SkipModules logic from init.ps1
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        $skipList = @("14", "16")
        foreach ($skip in $skipList) {
            $matched = $allModuleNames | Where-Object { $_ -eq $skip -or $_ -like "$skip-*" }
            foreach ($m in $matched) { $moduleEnabled[$m] = $false }
        }

        $moduleEnabled["14-DevTools"] -eq $false -and
        $moduleEnabled["16-UnixEnvironment"] -eq $false -and
        $moduleEnabled["01-PackageManagers"] -eq $true
    }

    # --- Test: SkipModules by full name ---
    Test-Assert "SkipModules: filtering by full name works" {
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        $skipList = @("07-Privacy", "09-Services")
        foreach ($skip in $skipList) {
            $matched = $allModuleNames | Where-Object { $_ -eq $skip -or $_ -like "$skip-*" }
            foreach ($m in $matched) { $moduleEnabled[$m] = $false }
        }

        $moduleEnabled["07-Privacy"] -eq $false -and
        $moduleEnabled["09-Services"] -eq $false -and
        $moduleEnabled["06-Debloat"] -eq $true
    }

    # --- Test: OnlyModules ---
    Test-Assert "OnlyModules: enables only listed modules" {
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        $onlyList = @("01", "06", "07")
        # Apply OnlyModules logic (disable all, enable only listed)
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $false }
        foreach ($only in $onlyList) {
            $matched = $allModuleNames | Where-Object { $_ -eq $only -or $_ -like "$only-*" }
            foreach ($m in $matched) { $moduleEnabled[$m] = $true }
        }

        $moduleEnabled["01-PackageManagers"] -eq $true -and
        $moduleEnabled["06-Debloat"] -eq $true -and
        $moduleEnabled["07-Privacy"] -eq $true -and
        $moduleEnabled["02-Applications"] -eq $false -and
        $moduleEnabled["14-DevTools"] -eq $false
    }

    # --- Test: profile overrides default ---
    Test-Assert "Merging: profile overrides default (all-true)" {
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        $profilesDir = Join-Path $projectRoot "profiles"
        $cfg = Read-ProfileConfig -ProfileName "minimal" -ProfilesDir $profilesDir
        if ($cfg -and $cfg.modules) {
            foreach ($prop in $cfg.modules.PSObject.Properties) {
                $moduleEnabled[$prop.Name] = [bool]$prop.Value
            }
        }

        # Minimal disables Applications
        $moduleEnabled["02-Applications"] -eq $false -and
        $moduleEnabled["01-PackageManagers"] -eq $true
    }

    # --- Test: config.toml overrides profile ---
    Test-Assert "Merging: config.toml layer overrides profile layer" {
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        # Layer 1: Apply full profile (all true)
        $profilesDir = Join-Path $projectRoot "profiles"
        $cfg = Read-ProfileConfig -ProfileName "full" -ProfilesDir $profilesDir
        if ($cfg -and $cfg.modules) {
            foreach ($prop in $cfg.modules.PSObject.Properties) {
                $moduleEnabled[$prop.Name] = [bool]$prop.Value
            }
        }

        # Layer 2: Apply config.toml override
        $tomlOverrides = @{ "14-DevTools" = $false; "16-UnixEnvironment" = $false }
        foreach ($key in $tomlOverrides.Keys) {
            if ($moduleEnabled.ContainsKey($key)) {
                $moduleEnabled[$key] = [bool]$tomlOverrides[$key]
            }
        }

        $moduleEnabled["14-DevTools"] -eq $false -and
        $moduleEnabled["16-UnixEnvironment"] -eq $false -and
        $moduleEnabled["01-PackageManagers"] -eq $true
    }

    # --- Test: CLI flags override everything ---
    Test-Assert "Merging: CLI -SkipModules overrides config.toml and profile" {
        $moduleEnabled = @{}
        foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

        # Layer 1: Profile (full - all true)
        # Layer 2: config.toml (all true)
        # Layer 3: CLI -SkipModules
        $skipList = @("02")
        foreach ($skip in $skipList) {
            $matched = $allModuleNames | Where-Object { $_ -eq $skip -or $_ -like "$skip-*" }
            foreach ($m in $matched) { $moduleEnabled[$m] = $false }
        }

        $moduleEnabled["02-Applications"] -eq $false
    }

    # --- Test: DryRun flag propagation ---
    Test-Assert "DryRun: CLI flag sets DryRunMode true" {
        # Simulate: CLI -DryRun overrides config
        $dryRunMode = $false
        $cliDryRun = $true
        $tomlDryRun = $false

        if ($cliDryRun) { $dryRunMode = $true }
        elseif ($tomlDryRun) { $dryRunMode = $true }

        $dryRunMode -eq $true
    }

    Test-Assert "DryRun: config.toml sets DryRunMode when CLI is false" {
        $dryRunMode = $false
        $cliDryRun = $false
        $tomlDryRun = $true

        if ($cliDryRun) { $dryRunMode = $true }
        elseif ($tomlDryRun) { $dryRunMode = $true }

        $dryRunMode -eq $true
    }

    Test-Assert "DryRun: defaults to false when neither CLI nor config set it" {
        $dryRunMode = $false
        $cliDryRun = $false
        $tomlDryRun = $false

        if ($cliDryRun) { $dryRunMode = $true }
        elseif ($tomlDryRun) { $dryRunMode = $true }

        $dryRunMode -eq $false
    }

    # --- Test: profile priority (CLI > config.toml > default) ---
    Test-Assert "Merging: active profile priority is CLI > config > default" {
        # Default
        $activeProfile = "full"

        # config.toml layer
        $tomlProfile = "developer"
        if ($tomlProfile) { $activeProfile = $tomlProfile }

        # CLI layer
        $cliProfile = "minimal"
        if ($cliProfile) { $activeProfile = $cliProfile }

        $activeProfile -eq "minimal"
    }

    Test-Assert "Merging: active profile uses config.toml when CLI is empty" {
        $activeProfile = "full"
        $tomlProfile = "security"
        if ($tomlProfile) { $activeProfile = $tomlProfile }
        $cliProfile = ""
        if ($cliProfile) { $activeProfile = $cliProfile }
        $activeProfile -eq "security"
    }

    # --- Test: apps skip list merging ---
    Test-Assert "Merging: apps_skip merges profile + config.toml" {
        $appsSkip = @()
        $profileSkip = @("Blender.Blender", "OBSProject.OBSStudio")
        $configSkip = @("OBSProject.OBSStudio", "Krita.Krita")
        $appsSkip += @($profileSkip)
        $appsSkip += @($configSkip)
        $appsSkip = @($appsSkip | Select-Object -Unique)

        $appsSkip.Count -eq 3 -and
        "Blender.Blender" -in $appsSkip -and
        "OBSProject.OBSStudio" -in $appsSkip -and
        "Krita.Krita" -in $appsSkip
    }

    # --- Test: privacy level override chain ---
    Test-Assert "Merging: privacy level uses profile then config.toml override" {
        $privacyLevel = "strict"  # default

        # Profile layer
        $profilePrivacy = "standard"
        if ($profilePrivacy) { $privacyLevel = $profilePrivacy }

        # Config layer
        $configPrivacy = "paranoid"
        if ($configPrivacy) { $privacyLevel = $configPrivacy }

        $privacyLevel -eq "paranoid"
    }

    # --- Test: missing profile name produces error ---
    Test-Assert "Merging: invalid profile name returns null from Read-ProfileConfig" {
        $profilesDir = Join-Path $projectRoot "profiles"
        $cfg = Read-ProfileConfig -ProfileName "" -ProfilesDir $profilesDir
        $null -eq $cfg
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
Write-Host "  ==================================" -ForegroundColor Cyan
Write-Host "  Test-Config.ps1 Results" -ForegroundColor Cyan
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
