# ============================================================================
# WinInit DevScript: Comprehensive Test Suite
# Usage:
#   .\devscripts\test.ps1                    Run all tests
#   .\devscripts\test.ps1 -DryRun            Structure + syntax only (no admin needed)
#   .\devscripts\test.ps1 -Suite encoding    Run only encoding tests
#   .\devscripts\test.ps1 -Suite structure   Run only structure tests
#   .\devscripts\test.ps1 -Suite syntax      Run only syntax tests
#   .\devscripts\test.ps1 -Suite state       Run only system state tests
#   .\devscripts\test.ps1 -Suite registry    Run only registry tests
#   .\devscripts\test.ps1 -Suite services    Run only service tests
#   .\devscripts\test.ps1 -Suite path        Run only PATH tests
#   .\devscripts\test.ps1 -Suite apps        Run only app availability tests
#   .\devscripts\test.ps1 -Suite output      Run only output/formatting tests
#   .\devscripts\test.ps1 -Verbose           Show all test details
#   .\devscripts\test.ps1 -List              List all test suites
#   .\devscripts\test.ps1 -JUnit out.xml     Export results as JUnit XML
# ============================================================================

param(
    [string]$Suite = "",
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$List,
    [string]$JUnit = ""
)

$ErrorActionPreference = "Continue"
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0
$script:Warnings = 0
$script:Results = @()
$script:CurrentSuite = ""
$projectRoot = Resolve-Path "$PSScriptRoot\.."

function Test-ContainsCodePointRange {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$Start,
        [int]$End
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

    foreach ($ch in $Text.ToCharArray()) {
        $codePoint = [int][char]$ch
        if ($codePoint -ge $Start -and $codePoint -le $End) {
            return $true
        }
    }

    return $false
}

# --- Test Framework ---
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

# --- List mode ---
if ($List) {
    Write-Host ""
    Write-Host "  Available Test Suites:" -ForegroundColor Cyan
    Write-Host "    structure    File/folder structure validation"
    Write-Host "    syntax       PowerShell parse validation"
    Write-Host "    encoding     UTF-8 BOM and character encoding"
    Write-Host "    output       Module output format validation"
    Write-Host "    functions    Common library function validation"
    Write-Host "    state        System state (dark mode, explorer, etc.)"
    Write-Host "    registry     Registry key validation"
    Write-Host "    services     Service state validation"
    Write-Host "    path         PATH environment variable checks"
    Write-Host "    apps         Application availability"
    Write-Host "    dirs         Directory structure"
    Write-Host "    hosts        Hosts file block validation"
    Write-Host "    defender     Defender exclusion validation"
    Write-Host ""
    exit 0
}

# --- Banner ---
Write-Host ""
Write-Host "  WinInit Test Suite" -ForegroundColor Cyan
Write-Host "  ==================" -ForegroundColor Cyan
$modeStr = if ($DryRun) { "DRY RUN (no admin/state tests)" } elseif ($Suite) { "Suite: $Suite" } else { "Full" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

$shouldRun = { param($s) -not $Suite -or $Suite -eq $s }

# ============================================================================
# SUITE: Structure
# ============================================================================
if (& $shouldRun "structure") {
    Start-Suite "Structure"

    Test-Assert "init.ps1 exists" { Test-Path "$projectRoot\init.ps1" }
    Test-Assert "launch.bat exists" { Test-Path "$projectRoot\launch.bat" }
    Test-Assert "lib\common.ps1 exists" { Test-Path "$projectRoot\lib\common.ps1" }
    Test-Assert "modules\ directory exists" { Test-Path "$projectRoot\modules" }
    Test-Assert "devscripts\ directory exists" { Test-Path "$projectRoot\devscripts" }

    $moduleFiles = Get-ChildItem "$projectRoot\modules\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name
    Test-Assert "Module count is 18" { $moduleFiles.Count -eq 18 }

    # Verify sequential numbering
    $expectedModules = @(
        "01-PackageManagers", "02-Applications", "03-DesktopEnvironment",
        "04-OneDriveRemoval", "05-Performance", "06-Debloat",
        "07-Privacy", "08-QualityOfLife", "09-Services",
        "10-NetworkPerformance", "11-VisualUX", "12-SecurityHardening",
        "13-BrowserExtensions", "14-DevTools", "15-PortableTools",
        "16-UnixEnvironment", "17-VSCodeSetup", "18-FinalConfig"
    )
    foreach ($expected in $expectedModules) {
        Test-Assert "Module $expected.ps1 exists" {
            Test-Path "$projectRoot\modules\$expected.ps1"
        }
    }

    # Verify devscripts
    $expectedDevscripts = @("ci", "format", "lint", "typecheck", "test", "package", "run-module", "bump-version")
    foreach ($ds in $expectedDevscripts) {
        Test-Assert "Devscript $ds.ps1 exists" {
            Test-Path "$projectRoot\devscripts\$ds.ps1"
        }
    }

    # Verify each module is non-empty and has required structure
    foreach ($mod in $moduleFiles) {
        $content = Get-Content $mod.FullName -Raw
        Test-Assert "$($mod.Name) is not empty (>100 bytes)" { $content.Length -gt 100 }
        Test-Assert "$($mod.Name) calls Write-Section" { $content -match "Write-Section" }
        Test-Assert "$($mod.Name) has completion Write-Log" { $content -match "Write-Log.*completed" }
        Test-Assert "$($mod.Name) has module header comment" { $content -match "^# Module:" }
    }

    # Verify init.ps1 structure
    $initContent = Get-Content "$projectRoot\init.ps1" -Raw
    Test-Assert "init.ps1 has preflight checks" { $initContent -match "Preflight" }
    Test-Assert "init.ps1 has module execution loop" {
        $initContent -match "foreach.*\`$mod.*in.*\`$modules" -or
        $initContent -match "for\s*\(\s*\`$i\s*=\s*0;\s*\`$i\s*-lt\s*\`$modules\.Count;\s*\`$i\+\+\s*\)"
    }
    Test-Assert "init.ps1 has error handling (try/catch)" { $initContent -match "try\s*\{" }
    Test-Assert "init.ps1 has summary section" { $initContent -match "Final Summary" }

    # Verify common.ps1 exports
    $commonContent = Get-Content "$projectRoot\lib\common.ps1" -Raw
    $requiredFunctions = @(
        "Write-Log", "Write-Section", "Write-ProgressBar", "Write-SubStep",
        "Install-WithRetry", "Install-App", "Install-PortableBin", "Install-PortableApp",
        "Update-Path", "Ensure-RegKey", "Write-SummaryBox",
        "Set-RegistrySafe", "Disable-ServiceSafe", "Invoke-DownloadSafe",
        "Add-ToSystemPath", "Remove-AppxSafe", "Add-HostsBlock"
    )
    foreach ($func in $requiredFunctions) {
        Test-Assert "common.ps1 defines $func" {
            $commonContent -match "function\s+$func\b"
        }
    }
}

# ============================================================================
# SUITE: Syntax
# ============================================================================
if (& $shouldRun "syntax") {
    Start-Suite "Syntax Validation"

    $allScripts = @()
    $allScripts += Get-ChildItem "$projectRoot\*.ps1" -ErrorAction SilentlyContinue
    $allScripts += Get-ChildItem "$projectRoot\lib\*.ps1" -ErrorAction SilentlyContinue
    $allScripts += Get-ChildItem "$projectRoot\modules\*.ps1" -ErrorAction SilentlyContinue
    $allScripts += Get-ChildItem "$projectRoot\devscripts\*.ps1" -ErrorAction SilentlyContinue

    foreach ($s in $allScripts) {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errors)
        Test-Assert "Syntax: $($s.Name)" { $errors.Count -eq 0 } `
            -FailMessage "$($errors.Count) parse error(s): $(($errors | Select-Object -First 3 | ForEach-Object { "L$($_.Extent.StartLineNumber)" }) -join ', ')"
    }
}

# ============================================================================
# SUITE: Encoding (UTF-8 BOM, Mojibake, bad characters)
# ============================================================================
if (& $shouldRun "encoding") {
    Start-Suite "Encoding & Character Validation"

    $allFiles = @()
    $allFiles += Get-ChildItem "$projectRoot\*.ps1" -ErrorAction SilentlyContinue
    $allFiles += Get-ChildItem "$projectRoot\lib\*.ps1" -ErrorAction SilentlyContinue
    $allFiles += Get-ChildItem "$projectRoot\modules\*.ps1" -ErrorAction SilentlyContinue
    $allFiles += Get-ChildItem "$projectRoot\devscripts\*.ps1" -ErrorAction SilentlyContinue

    foreach ($f in $allFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)

        # Check UTF-8 BOM
        $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        Test-Assert "BOM: $($f.Name) has UTF-8 BOM" { $hasBOM }

        # Check for em-dash (U+2014 = E2 80 94) - should not exist
        $hasEmDash = $false
        for ($i = 0; $i -lt $bytes.Length - 2; $i++) {
            if ($bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80 -and $bytes[$i+2] -eq 0x94) {
                $hasEmDash = $true
                break
            }
        }
        Test-Assert "No em-dash: $($f.Name)" { -not $hasEmDash } `
            -FailMessage "Contains U+2014 em-dash (use ASCII hyphen instead)"

        # Check for common mojibake patterns (double-encoded em-dash)
        $hasMojibake = $false
        for ($i = 0; $i -lt $bytes.Length - 6; $i++) {
            if ($bytes[$i] -eq 0xC3 -and $bytes[$i+1] -eq 0xA2 -and
                $bytes[$i+2] -eq 0xE2 -and $bytes[$i+3] -eq 0x82) {
                $hasMojibake = $true
                break
            }
        }
        Test-Assert "No mojibake: $($f.Name)" { -not $hasMojibake } `
            -FailMessage "Contains double-encoded UTF-8 mojibake"

        # Check for other problematic Unicode (box-drawing, block elements)
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        $hasBoxDrawing = Test-ContainsCodePointRange -Text $content -Start 0x2500 -End 0x257F
        $hasBlockElements = Test-ContainsCodePointRange -Text $content -Start 0x2580 -End 0x259F
        # These are OK in devscripts (display only) but not in modules
        if ($f.FullName -match "\\modules\\") {
            Test-Assert "No box-drawing chars: $($f.Name)" { -not $hasBoxDrawing }
            Test-Assert "No block elements: $($f.Name)" { -not $hasBlockElements }
        }

        # Check for null bytes (corrupted file)
        $hasNull = $false
        for ($i = 3; $i -lt [Math]::Min($bytes.Length, 10000); $i++) {
            if ($bytes[$i] -eq 0x00) { $hasNull = $true; break }
        }
        Test-Assert "No null bytes: $($f.Name)" { -not $hasNull } `
            -FailMessage "Contains null bytes (file may be corrupted or UTF-16)"

        # Check for CRLF consistency
        $hasCR = $content -match "`r`n"
        $hasLF = $content -match "(?<!\r)`n"
        $mixedLineEndings = $hasCR -and $hasLF
        Test-Assert "Consistent line endings: $($f.Name)" { -not $mixedLineEndings } `
            -FailMessage "Mixed CRLF and LF line endings"
    }

    # Verify launch.bat is ASCII/ANSI safe (no UTF-8 needed for .bat)
    if (Test-Path "$projectRoot\launch.bat") {
        $batBytes = [System.IO.File]::ReadAllBytes("$projectRoot\launch.bat")
        $hasHighBytes = $false
        foreach ($b in $batBytes) {
            if ($b -gt 127) { $hasHighBytes = $true; break }
        }
        Test-Assert "launch.bat is ASCII-safe" { -not $hasHighBytes } `
            -FailMessage "Contains non-ASCII bytes (may break on non-UTF-8 systems)"
    }
}

# ============================================================================
# SUITE: Output & Formatting
# ============================================================================
if (& $shouldRun "output") {
    Start-Suite "Output & Formatting"

    $moduleFiles = Get-ChildItem "$projectRoot\modules\*.ps1" -ErrorAction SilentlyContinue

    foreach ($mod in $moduleFiles) {
        $content = Get-Content $mod.FullName -Raw

        # Every module should log its start
        Test-Assert "$($mod.Name) logs section start" {
            $content -match 'Write-Section\s+"[^"]*"'
        }

        # Every module should log completion
        Test-Assert "$($mod.Name) logs completion" {
            $content -match 'Write-Log.*completed.*"OK"'
        }

        # No bare Write-Host without color in modules (should use Write-Log)
        $lines = Get-Content $mod.FullName
        $bareWriteHost = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*Write-Host\s+"' -and
                $line -notmatch 'ForegroundColor' -and
                $line -notmatch 'NoNewline' -and
                $line -notmatch '^\s*#') {
                $bareWriteHost = $true
                break
            }
        }
        Test-Assert "$($mod.Name) no bare Write-Host" { -not $bareWriteHost } `
            -FailMessage "Uses Write-Host without color - use Write-Log instead"

        # Check Write-Log calls have valid levels
        # Pattern: Write-Log "message" "LEVEL" -- level is always the last quoted arg on a simple call
        $logCalls = [regex]::Matches($content, 'Write-Log\s+(?:"[^"]*"|''[^'']*''|\$[^\s]+)\s+"(OK|INFO|WARN|ERROR|STEP|DEBUG|FATAL|[A-Z]{2,6})"')
        $validLevels = @("OK", "INFO", "WARN", "ERROR", "STEP", "DEBUG", "FATAL")
        foreach ($call in $logCalls) {
            $level = $call.Groups[1].Value
            if ($level -notin $validLevels) {
                Test-Assert "$($mod.Name) valid log level: $level" { $false } `
                    -FailMessage "Invalid log level '$level' (valid: $($validLevels -join ', '))"
            }
        }
    }

    # Verify common.ps1 Write-Log handles all levels
    $commonContent = Get-Content "$projectRoot\lib\common.ps1" -Raw
    foreach ($level in @("OK", "INFO", "WARN", "ERROR", "STEP")) {
        Test-Assert "common.ps1 handles log level '$level'" {
            $commonContent -match [regex]::Escape($level)
        }
    }
}

# ============================================================================
# SUITE: Functions (common.ps1 unit tests)
# ============================================================================
if (& $shouldRun "functions") {
    Start-Suite "Common Library Functions"

    # Load the library
    . "$projectRoot\lib\common.ps1"
    $script:TotalSteps = 1
    $script:CurrentStep = 0

    # Test Write-Log doesn't throw
    Test-Assert "Write-Log OK level" {
        try { Write-Log "test message" "OK"; $true } catch { $false }
    }
    Test-Assert "Write-Log WARN level" {
        try { Write-Log "test warning" "WARN"; $true } catch { $false }
    }
    Test-Assert "Write-Log ERROR level" {
        try { Write-Log "test error" "ERROR"; $true } catch { $false }
    }
    Test-Assert "Write-Log INFO level" {
        try { Write-Log "test info" "INFO"; $true } catch { $false }
    }

    # Test Ensure-RegKey
    Test-Assert "Ensure-RegKey creates key" {
        $testKey = "HKCU:\Software\WinInitTest_$(Get-Random)"
        try {
            Ensure-RegKey $testKey
            $exists = Test-Path $testKey
            Remove-Item $testKey -Force -ErrorAction SilentlyContinue
            $exists
        } catch { $false }
    }

    # Test Update-Path doesn't throw
    Test-Assert "Update-Path succeeds" {
        try { Update-Path; $true } catch { $false }
    }

    # Test Write-Section doesn't throw
    Test-Assert "Write-Section succeeds" {
        try { Write-Section "Test Section" "Test description"; $true } catch { $false }
    }

    # Test Write-ProgressBar doesn't throw
    Test-Assert "Write-ProgressBar 0%" {
        try { Write-ProgressBar -Percent 0 -Label "test"; $true } catch { $false }
    }
    Test-Assert "Write-ProgressBar 50%" {
        try { Write-ProgressBar -Percent 50 -Label "test"; $true } catch { $false }
    }
    Test-Assert "Write-ProgressBar 100%" {
        try { Write-ProgressBar -Percent 100 -Label "test"; $true } catch { $false }
    }

    # Test Write-SubStep doesn't throw
    Test-Assert "Write-SubStep succeeds" {
        try { Write-SubStep "Test step"; $true } catch { $false }
    }

    # Test Write-SummaryBox doesn't throw
    Test-Assert "Write-SummaryBox succeeds" {
        try { Write-SummaryBox "Test" @("Line 1", "Line 2"); $true } catch { $false }
    }

    # Test Set-RegistrySafe
    Test-Assert "Set-RegistrySafe creates and sets value" {
        $testKey = "HKCU:\Software\WinInitTest_$(Get-Random)"
        try {
            Set-RegistrySafe -Path $testKey -Name "TestVal" -Value 42 -Type "DWord"
            $val = (Get-ItemProperty $testKey -ErrorAction SilentlyContinue).TestVal
            Remove-Item $testKey -Force -ErrorAction SilentlyContinue
            $val -eq 42
        } catch { $false }
    }

    # Test Add-ToSystemPath with non-existent dir (should warn, not crash)
    Test-Assert "Add-ToSystemPath handles missing dir" {
        try {
            $result = Add-ToSystemPath "C:\WinInitTestNonExistent_$(Get-Random)"
            $result -eq $false
        } catch { $false }
    }

    # Cleanup test log entries
    if (Test-Path $script:LogFile) {
        $logContent = Get-Content $script:LogFile -Raw
        if ($logContent -match "test message|test warning|test error|test info") {
            # Don't clean up - it's fine to have test entries in the log
        }
    }
}

# ============================================================================
# SUITE: System State (requires admin + post-install)
# ============================================================================
if (-not $DryRun -and (& $shouldRun "state")) {
    Start-Suite "System State"

    # Dark mode
    $theme = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -ErrorAction SilentlyContinue
    Test-Assert "Dark mode (apps)" { $theme.AppsUseLightTheme -eq 0 }
    Test-Assert "Dark mode (system)" { $theme.SystemUsesLightTheme -eq 0 }

    # File Explorer
    $exp = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ErrorAction SilentlyContinue
    Test-Assert "File extensions visible" { $exp.HideFileExt -eq 0 }
    Test-Assert "Hidden files visible" { $exp.Hidden -eq 1 }
    Test-Assert "Super hidden files visible" { $exp.ShowSuperHidden -eq 1 }
    Test-Assert "Explorer opens to This PC" { $exp.LaunchTo -eq 1 }
    Test-Assert "Task View button hidden" { $exp.ShowTaskViewButton -eq 0 }

    # Quick Access
    $qa = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -ErrorAction SilentlyContinue
    Test-Assert "Recent files disabled" { $qa.ShowRecent -eq 0 }
    Test-Assert "Frequent folders disabled" { $qa.ShowFrequent -eq 0 }

    # Search
    $search = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ErrorAction SilentlyContinue
    Test-Assert "Search box hidden" { $search.SearchboxTaskbarMode -eq 0 }
    Test-Assert "Bing search disabled" { $search.BingSearchEnabled -eq 0 }

    # OneDrive policy
    $odPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -ErrorAction SilentlyContinue
    Test-Assert "OneDrive sync disabled by policy" { $odPolicy.DisableFileSyncNGSC -eq 1 }

    # Telemetry
    $telemetry = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ErrorAction SilentlyContinue
    Test-Assert "Telemetry set to 0" { $telemetry.AllowTelemetry -eq 0 }

    # Ink workspace
    $ink = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace" -ErrorAction SilentlyContinue
    Test-Assert "Ink Workspace disabled" { $ink.AllowWindowsInkWorkspace -eq 0 }
}

# ============================================================================
# SUITE: Registry
# ============================================================================
if (-not $DryRun -and (& $shouldRun "registry")) {
    Start-Suite "Registry Keys"

    $registryChecks = @(
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Name = "LongPathsEnabled"; Expected = 1; Desc = "Long paths enabled" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"; Name = "SMB1"; Expected = 0; Desc = "SMBv1 disabled" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"; Name = "EnableMulticast"; Expected = 0; Desc = "LLMNR disabled" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "DisallowShaking"; Expected = 1; Desc = "Aero Shake disabled" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideIcons"; Expected = 1; Desc = "Desktop icons hidden" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SilentInstalledAppsEnabled"; Expected = 0; Desc = "Store auto-install disabled" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Desc = "Consumer features disabled" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"; Name = "ScoobeSystemSettingEnabled"; Expected = 0; Desc = "Setup nag disabled" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Expected = 1; Desc = "Web search disabled" },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Expected = 0; Desc = "Game DVR disabled" }
    )

    foreach ($check in $registryChecks) {
        Test-Assert "Registry: $($check.Desc)" {
            $prop = Get-ItemProperty -Path $check.Path -Name $check.Name -ErrorAction SilentlyContinue
            $prop.$($check.Name) -eq $check.Expected
        }
    }
}

# ============================================================================
# SUITE: Services
# ============================================================================
if (-not $DryRun -and (& $shouldRun "services")) {
    Start-Suite "Disabled Services"

    $disabledServices = @(
        @{ Name = "DiagTrack"; Desc = "Diagnostics Tracking" },
        @{ Name = "dmwappushservice"; Desc = "WAP Push Message Routing" },
        @{ Name = "SysMain"; Desc = "SysMain/Superfetch" },
        @{ Name = "WSearch"; Desc = "Windows Search" },
        @{ Name = "Fax"; Desc = "Fax Service" },
        @{ Name = "wisvc"; Desc = "Windows Insider" },
        @{ Name = "PhoneSvc"; Desc = "Phone Service" },
        @{ Name = "RetailDemo"; Desc = "Retail Demo" },
        @{ Name = "MapsBroker"; Desc = "Downloaded Maps Manager" },
        @{ Name = "lfsvc"; Desc = "Geolocation" },
        @{ Name = "XblAuthManager"; Desc = "Xbox Live Auth" },
        @{ Name = "XblGameSave"; Desc = "Xbox Live Game Save" },
        @{ Name = "TabletInputService"; Desc = "Touch Keyboard/Handwriting" }
    )

    foreach ($svc in $disabledServices) {
        Test-Assert "Service disabled: $($svc.Desc)" {
            $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($s) { $s.StartType -eq "Disabled" } else { $true }  # OK if not installed
        }
    }
}

# ============================================================================
# SUITE: PATH
# ============================================================================
if (-not $DryRun -and (& $shouldRun "path")) {
    Start-Suite "PATH Environment"

    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

    $expectedInPath = @(
        @{ Dir = "C:\bin"; Desc = "C:\bin (portable tools)" },
        @{ Dir = "C:\apps"; Desc = "C:\apps (portable apps)" },
        @{ Dir = "C:\Program Files\7-Zip"; Desc = "7-Zip" },
        @{ Dir = "C:\msys64\mingw64\bin"; Desc = "MinGW-w64" },
        @{ Dir = "C:\vcpkg"; Desc = "vcpkg" }
    )

    foreach ($entry in $expectedInPath) {
        Test-Assert "PATH contains: $($entry.Desc)" {
            $machinePath -match [regex]::Escape($entry.Dir)
        }
    }

    # Check env vars
    $expectedEnvVars = @(
        @{ Name = "VCPKG_ROOT"; Desc = "VCPKG_ROOT" },
        @{ Name = "ANDROID_HOME"; Desc = "ANDROID_HOME" },
        @{ Name = "DOTNET_CLI_TELEMETRY_OPTOUT"; Desc = "dotnet telemetry opt-out" },
        @{ Name = "POWERSHELL_TELEMETRY_OPTOUT"; Desc = "PowerShell telemetry opt-out" }
    )

    foreach ($ev in $expectedEnvVars) {
        Test-Assert "Env var set: $($ev.Desc)" {
            [System.Environment]::GetEnvironmentVariable($ev.Name, "Machine") -or
            [System.Environment]::GetEnvironmentVariable($ev.Name, "User")
        }
    }
}

# ============================================================================
# SUITE: Apps
# ============================================================================
if (-not $DryRun -and (& $shouldRun "apps")) {
    Start-Suite "Application Availability"

    $keyApps = @(
        "git", "python", "node", "npm", "code", "pwsh",
        "cargo", "rustc", "go", "ruby", "perl",
        "gcc", "cmake", "make",
        "docker", "kubectl",
        "7z", "curl", "ssh", "jq"
    )

    foreach ($app in $keyApps) {
        Test-Assert "$app in PATH" {
            $null -ne (Get-Command $app -ErrorAction SilentlyContinue)
        }
    }
}

# ============================================================================
# SUITE: Directories
# ============================================================================
if (-not $DryRun -and (& $shouldRun "dirs")) {
    Start-Suite "Directory Structure"

    $expectedDirs = @(
        "C:\bin", "C:\apps", "C:\vcpkg", "C:\venv",
        "C:\android-sdk"
    )
    foreach ($dir in $expectedDirs) {
        Test-Assert "Directory exists: $dir" { Test-Path $dir }
    }

    # C:\bin should have tools
    Test-Assert "C:\bin has executables" {
        (Get-ChildItem "C:\bin" -Filter "*.exe" -ErrorAction SilentlyContinue).Count -gt 5
    }

    # C:\apps should have folders
    Test-Assert "C:\apps has app folders" {
        (Get-ChildItem "C:\apps" -Directory -ErrorAction SilentlyContinue).Count -gt 5
    }
}

# ============================================================================
# SUITE: Hosts File
# ============================================================================
if (-not $DryRun -and (& $shouldRun "hosts")) {
    Start-Suite "Hosts File Blocks"

    $hostsContent = Get-Content "$env:WINDIR\System32\drivers\etc\hosts" -Raw -ErrorAction SilentlyContinue

    $expectedBlocks = @(
        "WinInit Telemetry Block",
        "WinInit Bing/Search Block",
        "WinInit Extended Telemetry Block"
    )

    foreach ($block in $expectedBlocks) {
        Test-Assert "Hosts block present: $block" {
            $hostsContent -match [regex]::Escape($block)
        }
    }

    # Spot-check specific domains
    $blockedDomains = @(
        "telemetry.microsoft.com",
        "vortex.data.microsoft.com",
        "bing.com",
        "data.microsoft.com"
    )
    foreach ($domain in $blockedDomains) {
        Test-Assert "Domain blocked: $domain" {
            $hostsContent -match "0\.0\.0\.0\s+$([regex]::Escape($domain))"
        }
    }
}

# ============================================================================
# SUITE: Defender Exclusions
# ============================================================================
if (-not $DryRun -and (& $shouldRun "defender")) {
    Start-Suite "Defender Exclusions"

    try {
        $prefs = Get-MpPreference -ErrorAction Stop

        $expectedPathExclusions = @("C:\vcpkg", "C:\venv", "C:\bin", "C:\apps")
        foreach ($path in $expectedPathExclusions) {
            Test-Assert "Defender path exclusion: $path" {
                $prefs.ExclusionPath -contains $path
            }
        }

        $expectedProcExclusions = @("node.exe", "cargo.exe", "gcc.exe", "cl.exe")
        foreach ($proc in $expectedProcExclusions) {
            Test-Assert "Defender process exclusion: $proc" {
                $prefs.ExclusionProcess -contains $proc
            }
        }
    } catch {
        Test-Assert "Defender preferences accessible" { $false } -FailMessage $_
    }
}

# ============================================================================
# Summary
# ============================================================================
$totalTests = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings

Write-Host ""
Write-Host "  ==================" -ForegroundColor Cyan
Write-Host "  Total:    $totalTests" -ForegroundColor White
Write-Host "  Passed:   $($script:Passed)" -ForegroundColor Green
Write-Host "  Failed:   $($script:Failed)" -ForegroundColor $(if ($script:Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped:  $($script:Skipped)" -ForegroundColor $(if ($script:Skipped -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Errors:   $($script:Warnings)" -ForegroundColor $(if ($script:Warnings -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# --- JUnit XML Export ---
if ($JUnit) {
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' + "`n"
    $xml += "<testsuites tests=`"$totalTests`" failures=`"$($script:Failed)`" errors=`"$($script:Warnings)`" skipped=`"$($script:Skipped)`">`n"

    $suites = $script:Results | Group-Object Suite
    foreach ($suite in $suites) {
        $suiteFail = ($suite.Group | Where-Object { $_.Status -eq "FAIL" }).Count
        $suiteErr = ($suite.Group | Where-Object { $_.Status -eq "ERR" }).Count
        $suiteSkip = ($suite.Group | Where-Object { $_.Status -eq "SKIP" }).Count
        $suiteTime = ($suite.Group | Measure-Object -Property Time -Sum).Sum / 1000

        $xml += "  <testsuite name=`"$($suite.Name)`" tests=`"$($suite.Group.Count)`" failures=`"$suiteFail`" errors=`"$suiteErr`" skipped=`"$suiteSkip`" time=`"$suiteTime`">`n"

        foreach ($test in $suite.Group) {
            $xml += "    <testcase name=`"$([System.Security.SecurityElement]::Escape($test.Name))`" classname=`"WinInit.$($suite.Name)`" time=`"$($test.Time / 1000)`">"
            if ($test.Status -eq "FAIL") {
                $xml += "<failure message=`"$([System.Security.SecurityElement]::Escape($test.Message))`" />"
            } elseif ($test.Status -eq "ERR") {
                $xml += "<error message=`"$([System.Security.SecurityElement]::Escape($test.Message))`" />"
            } elseif ($test.Status -eq "SKIP") {
                $xml += "<skipped />"
            }
            $xml += "</testcase>`n"
        }
        $xml += "  </testsuite>`n"
    }
    $xml += "</testsuites>"
    Set-Content -Path $JUnit -Value $xml -Encoding UTF8
    Write-Host "  JUnit XML exported to: $JUnit" -ForegroundColor Gray
    Write-Host ""
}

exit $script:Failed
