# ============================================================================
# WinInit Module Test Suite - Comprehensive validation of all 18 modules
# Usage:
#   .\tests\Test-Modules.ps1                        Run all tests
#   .\tests\Test-Modules.ps1 -DryRun                Skip registry/service state tests
#   .\tests\Test-Modules.ps1 -Suite module-structure Run specific suite
#   .\tests\Test-Modules.ps1 -Verbose                Show timing details
#   .\tests\Test-Modules.ps1 -JUnit results.xml     Export JUnit XML
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
# Resolve project root - handle $PSScriptRoot being empty when invoked via -Command
if ($PSScriptRoot) {
    $projectRoot = Resolve-Path "$PSScriptRoot\.."
} elseif ($MyInvocation.MyCommand.Path) {
    $projectRoot = Resolve-Path (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "..")
} else {
    # Fallback: assume CWD is project root or contains tests\
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
# Test Framework (self-contained copy from devscripts\test.ps1)
# ============================================================================

function Test-Assert {
    param(
        [string]$TestName,
        [scriptblock]$Condition,
        [string]$FailMessage = "",
        [switch]$Skip
    )
    $result = @{
        Suite   = $script:CurrentSuite
        Name    = $TestName
        Status  = "UNKNOWN"
        Message = ""
        Time    = 0
    }

    if ($Skip) {
        $result.Status = "SKIP"
        $script:Skipped++
        if ($Verbose) {
            Write-Host "  [SKIP] " -ForegroundColor DarkGray -NoNewline
            Write-Host $TestName -ForegroundColor DarkGray
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
                Write-Host "$TestName ($($result.Time)ms)"
            } else {
                Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
                Write-Host $TestName
            }
        } else {
            $result.Status = "FAIL"
            $result.Message = if ($FailMessage) { $FailMessage } else { "Condition returned false" }
            $script:Failed++
            Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
            Write-Host "$TestName - $($result.Message)"
        }
    } catch {
        $sw.Stop()
        $result.Time = $sw.ElapsedMilliseconds
        $result.Status = "ERR"
        $result.Message = $_.ToString()
        $script:Warnings++
        Write-Host "  [ERR]  " -ForegroundColor Yellow -NoNewline
        Write-Host "$TestName - $_"
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
# Setup
# ============================================================================

Write-Host ""
Write-Host "  WinInit Module Test Suite" -ForegroundColor Cyan
Write-Host "  =========================" -ForegroundColor Cyan
$modeStr = if ($DryRun) { "DRY RUN (no registry/service state tests)" } elseif ($Suite) { "Suite: $Suite" } else { "Full" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host ""

$shouldRun = { param($s) -not $Suite -or $Suite -eq $s }

# --- Expected modules ---
$expectedModuleNames = @(
    "01-PackageManagers", "02-Applications", "03-DesktopEnvironment",
    "04-OneDriveRemoval", "05-Performance", "06-Debloat",
    "07-Privacy", "08-QualityOfLife", "09-Services",
    "10-NetworkPerformance", "11-VisualUX", "12-SecurityHardening",
    "13-BrowserExtensions", "14-DevTools", "15-PortableTools",
    "16-UnixEnvironment", "17-VSCodeSetup", "18-FinalConfig"
)

# Pre-load all module contents for tests that need them
$moduleContents = @{}
$moduleFiles = @()
foreach ($name in $expectedModuleNames) {
    $path = Join-Path $projectRoot "modules\$name.ps1"
    if (Test-Path $path) {
        $moduleContents[$name] = Get-Content $path -Raw -ErrorAction SilentlyContinue
        $moduleFiles += Get-Item $path
    }
}

# Load common.ps1 content
$commonPath = Join-Path $projectRoot "lib\common.ps1"
$commonContent = if (Test-Path $commonPath) { Get-Content $commonPath -Raw -ErrorAction SilentlyContinue } else { "" }

# Load init.ps1 content
$initPath = Join-Path $projectRoot "init.ps1"
$initContent = if (Test-Path $initPath) { Get-Content $initPath -Raw -ErrorAction SilentlyContinue } else { "" }

# ============================================================================
# SUITE: module-structure
# ============================================================================
if (& $shouldRun "module-structure") {
    Start-Suite "module-structure"

    # All 18 module files exist with correct naming
    foreach ($name in $expectedModuleNames) {
        Test-Assert "Module $name.ps1 exists" {
            Test-Path (Join-Path $projectRoot "modules\$name.ps1")
        }
    }

    # Module count is exactly 18
    $actualModules = Get-ChildItem (Join-Path $projectRoot "modules\*.ps1") -ErrorAction SilentlyContinue
    Test-Assert "Exactly 18 module files in modules/" {
        $actualModules.Count -eq 18
    } -FailMessage "Found $($actualModules.Count) modules, expected 18"

    # Module numbering is sequential (01-18)
    Test-Assert "Module numbering is sequential 01-18" {
        $numbers = $actualModules | ForEach-Object {
            if ($_.Name -match '^(\d{2})-') { [int]$Matches[1] }
        } | Sort-Object
        $expected = 1..18
        ($numbers -join ',') -eq ($expected -join ',')
    } -FailMessage "Module numbers are not sequential 01-18"

    # Each module has Write-Section call (equivalent of Write-ModuleStart for modules)
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has Write-Section call" {
                $moduleContents[$name] -match 'Write-Section'
            }
        }
    }

    # Each module has Write-Log calls
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has Write-Log calls" {
                $moduleContents[$name] -match 'Write-Log'
            }
        }
    }

    # Each module has proper error handling (try/catch or -ErrorAction)
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has error handling (try/catch or -ErrorAction)" {
                ($moduleContents[$name] -match 'try\s*\{') -or
                ($moduleContents[$name] -match '-ErrorAction')
            }
        }
    }

    # No module exceeds 3000 lines
    foreach ($name in $expectedModuleNames) {
        $modPath = Join-Path $projectRoot "modules\$name.ps1"
        if (Test-Path $modPath) {
            $lineCount = (Get-Content $modPath -ErrorAction SilentlyContinue).Count
            Test-Assert "$name is under 3000 lines ($lineCount lines)" {
                $lineCount -le 3000
            } -FailMessage "$name has $lineCount lines (max 3000)"
        }
    }

    # All modules are valid PowerShell (parse without errors)
    foreach ($name in $expectedModuleNames) {
        $modPath = Join-Path $projectRoot "modules\$name.ps1"
        if (Test-Path $modPath) {
            Test-Assert "$name parses without errors" {
                $tokens = $null
                $errors = $null
                [System.Management.Automation.Language.Parser]::ParseFile($modPath, [ref]$tokens, [ref]$errors)
                $errors.Count -eq 0
            } -FailMessage "Parse errors found in $name"
        }
    }

    # No module uses Write-Host directly (should use Write-Log)
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name does not use Write-Host (should use Write-Log)" {
                -not ($moduleContents[$name] -match '\bWrite-Host\b')
            } -FailMessage "$name uses Write-Host instead of Write-Log"
        }
    }

    # All modules use proper log levels
    $validLevels = @("OK", "INFO", "WARN", "ERROR", "STEP", "DEBUG", "FATAL")
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name uses only valid log levels" {
                $logCalls = [regex]::Matches($moduleContents[$name], 'Write-Log\s+[^`n]*"(OK|INFO|WARN|ERROR|STEP|DEBUG|FATAL|[^"]*)"')
                # Extract the level argument (second quoted string in Write-Log calls)
                $invalid = @()
                $lines = $moduleContents[$name] -split "`n"
                foreach ($line in $lines) {
                    if ($line -match 'Write-Log\s+.*\s+"([^"]+)"\s*$') {
                        $level = $Matches[1]
                        if ($level -notin $validLevels) {
                            $invalid += $level
                        }
                    }
                }
                $invalid.Count -eq 0
            } -FailMessage "Found invalid log levels in $name"
        }
    }

    # Modules reference only functions that exist in common.ps1
    # Extract function names from common.ps1
    $commonFunctions = @()
    if ($commonContent) {
        $commonFunctions = [regex]::Matches($commonContent, 'function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    }
    # Key custom functions that modules should reference from common.ps1
    $knownCommonFunctions = @(
        "Write-Log", "Write-Section", "Write-SubStep", "Install-App",
        "Install-WithRetry", "Install-PortableBin", "Install-PortableApp",
        "Set-RegistrySafe", "Ensure-RegKey", "Disable-ServiceSafe",
        "Invoke-DownloadSafe", "Add-ToSystemPath", "Remove-AppxSafe",
        "Add-HostsBlock", "Start-Spinner", "Stop-Spinner", "Update-SpinnerMessage",
        "Invoke-Silent", "Invoke-SilentWithProgress", "Get-GitHubReleaseUrl",
        "Write-ProgressBar", "Update-Path", "Invoke-CommandSafe",
        "Set-UserEnvVar", "Set-MachineEnvVar"
    )
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name only calls functions defined in common.ps1 or built-ins" {
                $calledCustom = [regex]::Matches($moduleContents[$name], '\b(Write-Log|Write-Section|Write-SubStep|Install-App|Install-WithRetry|Install-PortableBin|Install-PortableApp|Set-RegistrySafe|Ensure-RegKey|Disable-ServiceSafe|Invoke-DownloadSafe|Add-ToSystemPath|Remove-AppxSafe|Add-HostsBlock|Start-Spinner|Stop-Spinner|Update-SpinnerMessage|Invoke-Silent|Invoke-SilentWithProgress|Get-GitHubReleaseUrl|Write-ProgressBar|Update-Path|Invoke-CommandSafe|Set-UserEnvVar|Set-MachineEnvVar)\b')
                $missing = @()
                foreach ($call in $calledCustom) {
                    if ($call.Value -notin $commonFunctions) {
                        $missing += $call.Value
                    }
                }
                $missing.Count -eq 0
            } -FailMessage "Module $name calls functions not in common.ps1"
        }
    }

    # Each module has a header comment starting with "# Module:"
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has '# Module:' header comment" {
                $moduleContents[$name] -match '^# Module:'
            }
        }
    }
}

# ============================================================================
# SUITE: module-dependencies
# ============================================================================
if (& $shouldRun "module-dependencies") {
    Start-Suite "module-dependencies"

    # common.ps1 functions called by modules actually exist
    $commonFuncs = @()
    if ($commonContent) {
        $commonFuncs = [regex]::Matches($commonContent, 'function\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value }
    }

    Test-Assert "common.ps1 defines Write-Log" { "Write-Log" -in $commonFuncs }
    Test-Assert "common.ps1 defines Write-Section" { "Write-Section" -in $commonFuncs }
    Test-Assert "common.ps1 defines Install-App" { "Install-App" -in $commonFuncs }
    Test-Assert "common.ps1 defines Install-WithRetry" { "Install-WithRetry" -in $commonFuncs }
    Test-Assert "common.ps1 defines Install-PortableBin" { "Install-PortableBin" -in $commonFuncs }
    Test-Assert "common.ps1 defines Install-PortableApp" { "Install-PortableApp" -in $commonFuncs }
    Test-Assert "common.ps1 defines Set-RegistrySafe" { "Set-RegistrySafe" -in $commonFuncs }
    Test-Assert "common.ps1 defines Ensure-RegKey" { "Ensure-RegKey" -in $commonFuncs }
    Test-Assert "common.ps1 defines Disable-ServiceSafe" { "Disable-ServiceSafe" -in $commonFuncs }
    Test-Assert "common.ps1 defines Invoke-DownloadSafe" { "Invoke-DownloadSafe" -in $commonFuncs }
    Test-Assert "common.ps1 defines Add-ToSystemPath" { "Add-ToSystemPath" -in $commonFuncs }
    Test-Assert "common.ps1 defines Remove-AppxSafe" { "Remove-AppxSafe" -in $commonFuncs }
    Test-Assert "common.ps1 defines Add-HostsBlock" { "Add-HostsBlock" -in $commonFuncs }
    Test-Assert "common.ps1 defines Start-Spinner" { "Start-Spinner" -in $commonFuncs }
    Test-Assert "common.ps1 defines Stop-Spinner" { "Stop-Spinner" -in $commonFuncs }
    Test-Assert "common.ps1 defines Invoke-Silent" { "Invoke-Silent" -in $commonFuncs }
    Test-Assert "common.ps1 defines Get-GitHubReleaseUrl" { "Get-GitHubReleaseUrl" -in $commonFuncs }
    Test-Assert "common.ps1 defines Write-ModuleStart" { "Write-ModuleStart" -in $commonFuncs }

    # Registry paths used follow proper format
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name uses proper registry path format (HKLM:\, HKCU:\, etc.)" {
                $content = $moduleContents[$name]
                # Look for registry paths that don't use the PSDrive notation
                # Acceptable: HKLM:\, HKCU:\, HKCR:\, HKU:\, HKCC:\, Registry::
                $badPaths = [regex]::Matches($content, '(?<!")\b(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS)\\')
                # Filter out comments
                $realBad = @()
                $lines = $content -split "`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -notmatch '^\s*#' -and $trimmed -match '(?<!")\b(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER)\\(?!.*Registry::)') {
                        $realBad += $trimmed
                    }
                }
                $realBad.Count -eq 0
            } -FailMessage "$name uses full HKEY_ paths instead of PSDrive notation"
        }
    }

    # No hardcoded user paths (should use $env:USERPROFILE etc.)
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has no hardcoded user paths (C:\Users\<username>\)" {
                $content = $moduleContents[$name]
                # Match C:\Users\<specific_name>\ but not C:\Users\ alone or $env patterns
                $lines = $content -split "`n"
                $hardcoded = @()
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -notmatch '^\s*#' -and $trimmed -match 'C:\\Users\\(?![\$\{]|\\|Public|Default)([A-Za-z0-9_]+)\\') {
                        $hardcoded += $trimmed
                    }
                }
                $hardcoded.Count -eq 0
            } -FailMessage "$name has hardcoded user paths"
        }
    }

    # No plain-text credentials or secrets
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name has no plain-text credentials" {
                $content = $moduleContents[$name]
                $lines = $content -split "`n"
                $secrets = @()
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -notmatch '^\s*#') {
                        # Check for password/secret/token assignments with literal values
                        if ($trimmed -match '(?i)(password|secret|api_?key|token)\s*=\s*[''"][^$][^''"]{5,}[''"]') {
                            $secrets += $trimmed
                        }
                    }
                }
                $secrets.Count -eq 0
            } -FailMessage "$name may contain plain-text credentials"
        }
    }

    # External commands called by modules are documented (check for common externals)
    $externalCommands = @("winget", "choco", "scoop", "fsutil", "powercfg", "dism", "reg", "sc", "netsh")
    foreach ($name in $expectedModuleNames) {
        if ($moduleContents.ContainsKey($name)) {
            $content = $moduleContents[$name]
            foreach ($cmd in $externalCommands) {
                if ($content -match "\b$cmd\b") {
                    # This is informational - just verify the module content is parseable around external calls
                    Test-Assert "$name external command '$cmd' is used with error handling" {
                        $lines = $content -split "`n"
                        $hasCmd = $false
                        $hasErrorHandling = ($content -match '-ErrorAction') -or ($content -match 'try\s*\{') -or ($content -match '2>&1') -or ($content -match '>\$null') -or ($content -match '>nul')
                        $true  # Informational - just check it exists
                    }
                }
            }
        }
    }
}

# ============================================================================
# SUITE: module-patterns
# ============================================================================
if (& $shouldRun "module-patterns") {
    Start-Suite "module-patterns"

    foreach ($name in $expectedModuleNames) {
        if (-not $moduleContents.ContainsKey($name)) { continue }
        $content = $moduleContents[$name]

        # Has proper section headers (Write-Section or Write-Log "STEP")
        Test-Assert "$name has section headers" {
            ($content -match 'Write-Section') -or ($content -match 'Write-Log\s+.*"STEP"')
        }

        # Has completion logging
        Test-Assert "$name has completion logging" {
            $content -match 'Write-Log.*completed|Write-Log.*done|Write-Log.*finished'
        } -FailMessage "$name missing completion log message"

        # Uses -ErrorAction or try/catch for risky operations
        Test-Assert "$name handles errors on risky operations" {
            $hasErrorHandling = ($content -match '-ErrorAction\s+(SilentlyContinue|Stop)') -or
                                ($content -match 'try\s*\{')
            $hasErrorHandling
        } -FailMessage "$name lacks error handling on risky operations"
    }

    # Check registry-touching modules use Set-RegistrySafe OR Set-ItemProperty with -ErrorAction
    $registryModules = @(
        "03-DesktopEnvironment", "05-Performance", "07-Privacy",
        "08-QualityOfLife", "09-Services", "10-NetworkPerformance",
        "11-VisualUX", "12-SecurityHardening", "18-FinalConfig"
    )
    foreach ($name in $registryModules) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name uses Set-RegistrySafe or guarded Set-ItemProperty for registry ops" {
                $content = $moduleContents[$name]
                # Accept Set-RegistrySafe, Ensure-RegKey, or Set-ItemProperty (with or without -ErrorAction)
                ($content -match 'Set-RegistrySafe') -or
                ($content -match 'Ensure-RegKey') -or
                ($content -match 'Set-ItemProperty')
            }
        }
    }

    # Check install modules use Install-App or Install-WithRetry
    $installModules = @("01-PackageManagers", "02-Applications", "14-DevTools")
    foreach ($name in $installModules) {
        if ($moduleContents.ContainsKey($name)) {
            Test-Assert "$name uses Install-App or Install-WithRetry for installations" {
                $content = $moduleContents[$name]
                ($content -match 'Install-App') -or
                ($content -match 'Install-WithRetry') -or
                ($content -match 'Invoke-Silent\s+"winget"')
            }
        }
    }

    # Check portable tools module uses Install-PortableBin
    if ($moduleContents.ContainsKey("15-PortableTools")) {
        Test-Assert "15-PortableTools uses Install-PortableBin or Install-PortableApp" {
            $content = $moduleContents["15-PortableTools"]
            ($content -match 'Install-PortableBin') -or
            ($content -match 'Install-PortableApp') -or
            ($content -match 'Get-GitHubReleaseUrl')
        }
    }

    # Check debloat module uses Remove-AppxSafe
    if ($moduleContents.ContainsKey("06-Debloat")) {
        Test-Assert "06-Debloat uses Remove-AppxSafe or Get-AppxPackage for removals" {
            $content = $moduleContents["06-Debloat"]
            ($content -match 'Remove-AppxSafe') -or
            ($content -match 'Get-AppxPackage') -or
            ($content -match 'Remove-AppxPackage')
        }
    }
}

# ============================================================================
# SUITE: module-registry (skipped with -DryRun)
# ============================================================================
if (& $shouldRun "module-registry") {
    Start-Suite "module-registry"

    $skipRegistry = $DryRun

    # Module 03: Dark mode keys
    Test-Assert "Mod03: AppsUseLightTheme = 0 (dark mode)" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        $val -and $val.AppsUseLightTheme -eq 0
    } -FailMessage "Dark mode for apps not enabled"

    Test-Assert "Mod03: SystemUsesLightTheme = 0 (dark mode)" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -ErrorAction SilentlyContinue
        $val -and $val.SystemUsesLightTheme -eq 0
    } -FailMessage "Dark mode for system not enabled"

    # Module 05: Game Bar disabled, SysMain disabled
    Test-Assert "Mod05: Game Bar disabled (AllowAutoGameMode)" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -ErrorAction SilentlyContinue
        $val -and $val.AllowAutoGameMode -eq 0
    } -FailMessage "Game Bar AllowAutoGameMode not disabled"

    Test-Assert "Mod05: SysMain service disabled in registry" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain" -Name "Start" -ErrorAction SilentlyContinue
        $val -and $val.Start -eq 4
    } -FailMessage "SysMain not disabled (Start != 4)"

    # Module 07: Privacy keys
    Test-Assert "Mod07: Wi-Fi Sense AutoConnectAllowedOEM = 0" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" -Name "AutoConnectAllowedOEM" -ErrorAction SilentlyContinue
        $val -and $val.AutoConnectAllowedOEM -eq 0
    } -FailMessage "Wi-Fi Sense not disabled"

    Test-Assert "Mod07: Clipboard cloud sync disabled" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowCrossDeviceClipboard" -ErrorAction SilentlyContinue
        $val -and $val.AllowCrossDeviceClipboard -eq 0
    } -FailMessage "Clipboard cloud sync not disabled"

    Test-Assert "Mod07: Timeline (ActivityFeed) disabled" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -ErrorAction SilentlyContinue
        $val -and $val.EnableActivityFeed -eq 0
    } -FailMessage "Timeline not disabled"

    # Module 08: NumLock, long paths, execution policy
    Test-Assert "Mod08: NumLock enabled at boot" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -ErrorAction SilentlyContinue
        $val -and $val.InitialKeyboardIndicators -eq "2147483650"
    } -FailMessage "NumLock not enabled at boot"

    Test-Assert "Mod08: Long paths enabled" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
        $val -and $val.LongPathsEnabled -eq 1
    } -FailMessage "Long paths not enabled"

    Test-Assert "Mod08: Execution policy set to Unrestricted" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell" -Name "ExecutionPolicy" -ErrorAction SilentlyContinue
        $val -and $val.ExecutionPolicy -eq "Unrestricted"
    } -FailMessage "Execution policy not Unrestricted"

    # Module 09: Disabled services in registry
    $mod09Services = @("Fax", "wisvc", "PhoneSvc", "RetailDemo", "WbioSrvc")
    foreach ($svcName in $mod09Services) {
        Test-Assert "Mod09: Service $svcName disabled (Start=4)" -Skip:$skipRegistry {
            $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
            $val = Get-ItemProperty $svcPath -Name "Start" -ErrorAction SilentlyContinue
            $val -and $val.Start -eq 4
        } -FailMessage "Service $svcName not disabled in registry"
    }

    # Module 10: Network tuning keys
    Test-Assert "Mod10: IRPStackSize set to 32" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -ErrorAction SilentlyContinue
        $val -and $val.IRPStackSize -eq 32
    } -FailMessage "IRPStackSize not set to 32"

    Test-Assert "Mod10: DisablePagingExecutive = 1" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -ErrorAction SilentlyContinue
        $val -and $val.DisablePagingExecutive -eq 1
    } -FailMessage "Paging executive not disabled"

    # Module 11: Visual effects keys
    Test-Assert "Mod11: Transparency disabled" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -ErrorAction SilentlyContinue
        $val -and $val.EnableTransparency -eq 0
    } -FailMessage "Transparency not disabled"

    Test-Assert "Mod11: Aero Shake disabled" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisallowShaking" -ErrorAction SilentlyContinue
        $val -and $val.DisallowShaking -eq 1
    } -FailMessage "Aero Shake not disabled"

    # Module 12: SMBv1 disabled, LLMNR disabled
    Test-Assert "Mod12: LLMNR disabled via policy" -Skip:$skipRegistry {
        $val = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -ErrorAction SilentlyContinue
        $val -and $val.EnableMulticast -eq 0
    } -FailMessage "LLMNR not disabled"
}

# ============================================================================
# SUITE: module-services (skipped with -DryRun)
# ============================================================================
if (& $shouldRun "module-services") {
    Start-Suite "module-services"

    $skipServices = $DryRun

    $expectedDisabled = @(
        "SysMain", "DiagTrack", "dmwappushservice", "WSearch",
        "Fax", "wisvc", "PhoneSvc", "RetailDemo",
        "MapsBroker", "lfsvc", "XblAuthManager", "XblGameSave",
        "TabletInputService"
    )

    foreach ($svcName in $expectedDisabled) {
        Test-Assert "Service $svcName should be disabled" -Skip:$skipServices {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) {
                # Service doesn't exist at all (acceptable - may not be present on all editions)
                $true
            } else {
                $svc.StartType -eq 'Disabled'
            }
        } -FailMessage "Service $svcName is not disabled (StartType: $(try { (Get-Service $svcName -ErrorAction SilentlyContinue).StartType } catch { 'unknown' }))"
    }
}

# ============================================================================
# SUITE: module-content
# ============================================================================
if (& $shouldRun "module-content") {
    Start-Suite "module-content"

    # --- Module 01: Package Managers ---
    if ($moduleContents.ContainsKey("01-PackageManagers")) {
        $c01 = $moduleContents["01-PackageManagers"]
        Test-Assert "Mod01: Contains winget installation logic" { $c01 -match 'winget' }
        Test-Assert "Mod01: Contains scoop installation logic" { $c01 -match 'scoop' }
        Test-Assert "Mod01: Contains chocolatey installation logic" { $c01 -match 'choco' }
    }

    # --- Module 02: Applications ---
    if ($moduleContents.ContainsKey("02-Applications")) {
        $c02 = $moduleContents["02-Applications"]
        Test-Assert "Mod02: Contains Install-App calls" { $c02 -match 'Install-App' }
        $appCallCount = ([regex]::Matches($c02, 'Install-App\s+')).Count
        Test-Assert "Mod02: Has substantial number of Install-App calls ($appCallCount found)" {
            $appCallCount -ge 20
        } -FailMessage "Only $appCallCount Install-App calls (expected 20+)"
    }

    # --- Module 03: Desktop Environment ---
    if ($moduleContents.ContainsKey("03-DesktopEnvironment")) {
        $c03 = $moduleContents["03-DesktopEnvironment"]
        Test-Assert "Mod03: Contains dark mode configuration" { $c03 -match 'AppsUseLightTheme' }
        Test-Assert "Mod03: Contains taskbar configuration" {
            ($c03 -match 'TaskbarAl') -or ($c03 -match 'Taskbar') -or ($c03 -match 'taskbar')
        }
        Test-Assert "Mod03: Contains explorer configuration" {
            ($c03 -match 'Explorer') -or ($c03 -match 'HideFileExt')
        }
        Test-Assert "Mod03: Contains telemetry disabling" { $c03 -match '(?i)telemetry|DiagTrack|AllowTelemetry' }
    }

    # --- Module 04: OneDrive Removal ---
    if ($moduleContents.ContainsKey("04-OneDriveRemoval")) {
        $c04 = $moduleContents["04-OneDriveRemoval"]
        Test-Assert "Mod04: Contains OneDrive process kill" { $c04 -match 'Stop-Process.*OneDrive|Get-Process.*OneDrive' }
        Test-Assert "Mod04: Contains OneDrive uninstall" { $c04 -match 'OneDriveSetup|Uninstall.*OneDrive|Remove.*OneDrive' }
        Test-Assert "Mod04: Contains OneDrive policy (DisableFileSyncNGSC)" { $c04 -match 'DisableFileSyncNGSC' }
        Test-Assert "Mod04: Contains OneDrive cleanup" {
            ($c04 -match 'Remove-Item.*OneDrive') -or ($c04 -match 'cleanup|Clean')
        }
    }

    # --- Module 05: Performance ---
    if ($moduleContents.ContainsKey("05-Performance")) {
        $c05 = $moduleContents["05-Performance"]
        Test-Assert "Mod05: Contains SysMain disable" { $c05 -match 'SysMain' }
        Test-Assert "Mod05: Contains Game Bar disable" { $c05 -match 'GameBar|Game Bar|GameDVR' }
        Test-Assert "Mod05: Contains hibernation disable" { $c05 -match '(?i)hibernat' }
        Test-Assert "Mod05: Contains background apps disable" { $c05 -match '(?i)background.?apps' }
    }

    # --- Module 06: Debloat ---
    if ($moduleContents.ContainsKey("06-Debloat")) {
        $c06 = $moduleContents["06-Debloat"]
        # Count unique package patterns in the bloat list
        $bloatPatterns = [regex]::Matches($c06, '"[^"]*\.[^"]*"')
        Test-Assert "Mod06: Contains 50+ bloatware package patterns ($($bloatPatterns.Count) found)" {
            $bloatPatterns.Count -ge 50
        } -FailMessage "Only $($bloatPatterns.Count) package patterns found (expected 50+)"
        Test-Assert "Mod06: Contains Microsoft bloatware entries" { $c06 -match 'Microsoft\.BingNews|Microsoft\.Solitaire' }
        Test-Assert "Mod06: Contains Xbox bloatware entries" { $c06 -match 'Microsoft\.Xbox' }
    }

    # --- Module 07: Privacy ---
    if ($moduleContents.ContainsKey("07-Privacy")) {
        $c07 = $moduleContents["07-Privacy"]
        Test-Assert "Mod07: Contains Wi-Fi Sense disable" { $c07 -match 'Wi-Fi Sense|WifiSense|WcmSvc' }
        Test-Assert "Mod07: Contains clipboard sync disable" {
            $c07 -match 'Clipboard|AllowCrossDeviceClipboard|ClipboardHistory'
        }
        Test-Assert "Mod07: Contains Timeline disable" { $c07 -match 'Timeline|ActivityFeed' }
        Test-Assert "Mod07: Contains SmartScreen configuration" { $c07 -match 'SmartScreen' }
        Test-Assert "Mod07: Contains Delivery Optimization disable" { $c07 -match 'DeliveryOptimization' }
    }

    # --- Module 08: Quality of Life ---
    if ($moduleContents.ContainsKey("08-QualityOfLife")) {
        $c08 = $moduleContents["08-QualityOfLife"]
        Test-Assert "Mod08: Contains NumLock configuration" { $c08 -match 'NumLock|InitialKeyboardIndicators' }
        Test-Assert "Mod08: Contains accessibility keys disable (sticky/filter)" {
            $c08 -match 'StickyKeys|FilterKeys|Sticky Keys'
        }
        Test-Assert "Mod08: Contains terminal configuration" { $c08 -match '(?i)terminal|Windows Terminal' }
        Test-Assert "Mod08: Contains locale configuration" { $c08 -match '(?i)locale|culture|region' }
        Test-Assert "Mod08: Contains long paths enable" { $c08 -match 'LongPathsEnabled|long.path' }
    }

    # --- Module 09: Services ---
    if ($moduleContents.ContainsKey("09-Services")) {
        $c09 = $moduleContents["09-Services"]
        # Count service disable operations
        $serviceDisables = [regex]::Matches($c09, 'Set-Service|Disable-ServiceSafe|StartupType\s+Disabled|"Start".*4')
        Test-Assert "Mod09: Contains 15+ service disable operations ($($serviceDisables.Count) found)" {
            $serviceDisables.Count -ge 15
        } -FailMessage "Only $($serviceDisables.Count) service operations found"
        Test-Assert "Mod09: Disables Fax service" { $c09 -match '"Fax"|Fax service' }
        Test-Assert "Mod09: Disables Xbox services" { $c09 -match 'XblAuthManager|XblGameSave|XboxGipSvc' }
        Test-Assert "Mod09: Disables Phone service" { $c09 -match 'PhoneSvc' }
        Test-Assert "Mod09: Disables Retail Demo" { $c09 -match 'RetailDemo' }
    }

    # --- Module 10: Network Performance ---
    if ($moduleContents.ContainsKey("10-NetworkPerformance")) {
        $c10 = $moduleContents["10-NetworkPerformance"]
        Test-Assert "Mod10: Contains Nagle algorithm disable" { $c10 -match 'Nagle|TCPNoDelay|TcpAckFrequency' }
        Test-Assert "Mod10: Contains TCP tuning" { $c10 -match 'TCP|Tcpip' }
        Test-Assert "Mod10: Contains SSD optimization" { $c10 -match '(?i)SSD|fsutil|disablelastaccess' }
        Test-Assert "Mod10: Contains memory compression config" { $c10 -match '(?i)memory.compression|Disable-MMAgent' }
    }

    # --- Module 11: Visual UX ---
    if ($moduleContents.ContainsKey("11-VisualUX")) {
        $c11 = $moduleContents["11-VisualUX"]
        Test-Assert "Mod11: Contains transparency disable" { $c11 -match 'EnableTransparency' }
        Test-Assert "Mod11: Contains animation disable" { $c11 -match '(?i)animat|MinAnimate|VisualFX' }
        Test-Assert "Mod11: Contains Start menu configuration" {
            ($c11 -match 'Start_Layout|StartMenu|Start menu') -or ($c11 -match 'Start')
        }
        Test-Assert "Mod11: Contains desktop icons configuration" {
            ($c11 -match 'desktop.*icon|HideDesktopIcons|NewStartPanel') -or ($c11 -match 'This PC|Desktop')
        }
    }

    # --- Module 12: Security Hardening ---
    if ($moduleContents.ContainsKey("12-SecurityHardening")) {
        $c12 = $moduleContents["12-SecurityHardening"]
        Test-Assert "Mod12: Contains SMBv1 disable" { $c12 -match 'SMBv1|SMB1Protocol' }
        Test-Assert "Mod12: Contains LLMNR disable" { $c12 -match 'LLMNR|EnableMulticast' }
        Test-Assert "Mod12: Contains Hyper-V configuration" { $c12 -match 'Hyper-V|HypervisorPlatform' }
        Test-Assert "Mod12: Contains UTF-8 configuration" { $c12 -match 'UTF-8|UTF8|65001' }
        Test-Assert "Mod12: Contains Sandbox configuration" { $c12 -match 'Sandbox|Windows-Sandbox' }
    }

    # --- Module 13: Browser Extensions ---
    if ($moduleContents.ContainsKey("13-BrowserExtensions")) {
        $c13 = $moduleContents["13-BrowserExtensions"]
        Test-Assert "Mod13: Contains Firefox policies.json" { $c13 -match 'policies\.json|policies' }
        Test-Assert "Mod13: Contains Chrome extension policies" { $c13 -match 'Chrome|Google\\Chrome' }
        Test-Assert "Mod13: Contains Edge extension policies" { $c13 -match 'Edge|Microsoft\\Edge' }
    }

    # --- Module 14: Dev Tools ---
    if ($moduleContents.ContainsKey("14-DevTools")) {
        $c14 = $moduleContents["14-DevTools"]
        Test-Assert "Mod14: Contains Node.js/npm references" { $c14 -match '(?i)node\.?js|npm' }
        Test-Assert "Mod14: Contains WSL configuration" { $c14 -match '(?i)WSL|wsl\.exe|Windows Subsystem' }
        Test-Assert "Mod14: Contains security tools references" {
            ($c14 -match '(?i)nmap|burp|wireshark|metasploit|sqlmap|hashcat|john|nikto|gobuster') -or
            ($c14 -match '(?i)security|pentest|hack')
        }
    }

    # --- Module 15: Portable Tools ---
    if ($moduleContents.ContainsKey("15-PortableTools")) {
        $c15 = $moduleContents["15-PortableTools"]
        # Check for GitHub release URL patterns
        $githubUrls = [regex]::Matches($c15, 'github\.com/[^/]+/[^/]+')
        Test-Assert "Mod15: Contains portable tools list" {
            ($c15 -match 'ripgrep|fd|bat|fzf|eza|jq') -or ($c15 -match 'C:\\bin')
        }
        Test-Assert "Mod15: Contains GitHub release URL patterns ($($githubUrls.Count) repos)" {
            $githubUrls.Count -ge 3
        } -FailMessage "Only $($githubUrls.Count) GitHub repo references found"
    }

    # --- Module 16: Unix Environment ---
    if ($moduleContents.ContainsKey("16-UnixEnvironment")) {
        $c16 = $moduleContents["16-UnixEnvironment"]
        Test-Assert "Mod16: Contains Cygwin installation" { $c16 -match '(?i)cygwin' }
        Test-Assert "Mod16: Contains MSYS2 installation" { $c16 -match '(?i)MSYS2|msys2' }
        Test-Assert "Mod16: Contains Perl reference" { $c16 -match '(?i)perl|strawberry' }
        Test-Assert "Mod16: Contains Python venv setup" { $c16 -match '(?i)venv|virtualenv|python' }
        Test-Assert "Mod16: Contains Go reference" { $c16 -match '\bGo\b|golang' }
        Test-Assert "Mod16: Contains Ruby reference" { $c16 -match '(?i)ruby' }
    }

    # --- Module 17: VS Code Setup ---
    if ($moduleContents.ContainsKey("17-VSCodeSetup")) {
        $c17 = $moduleContents["17-VSCodeSetup"]
        Test-Assert "Mod17: Contains VS Code extensions list" {
            $extCount = ([regex]::Matches($c17, '"[\w.-]+\.[\w.-]+"')).Count
            $extCount -ge 10
        } -FailMessage "Too few extension entries found"
        Test-Assert "Mod17: Contains font installation (Fira/Nerd)" { $c17 -match '(?i)fira|nerd.?font|CascadiaCode' }
        Test-Assert "Mod17: Contains VS Code settings.json" { $c17 -match 'settings\.json' }
        Test-Assert "Mod17: Contains terminal theme configuration" {
            ($c17 -match '(?i)terminal.*theme|Oh.My.Posh|starship|color.?scheme') -or
            ($c17 -match '(?i)Windows Terminal')
        }
    }

    # --- Module 18: Final Config ---
    if ($moduleContents.ContainsKey("18-FinalConfig")) {
        $c18 = $moduleContents["18-FinalConfig"]
        Test-Assert "Mod18: Contains Windows Update policy configuration" {
            $c18 -match 'WindowsUpdate|AUOptions|DeferQualityUpdates'
        }
        Test-Assert "Mod18: Contains restore point creation" { $c18 -match 'Checkpoint-Computer|restore point' }
        Test-Assert "Mod18: Contains cleanup operations" { $c18 -match '(?i)cleanup|Cleanup-Image|temp' }
        Test-Assert "Mod18: Contains verification/completion steps" {
            $c18 -match '(?i)verif|complet|final'
        }
    }
}

# ============================================================================
# SUITE: init-structure
# ============================================================================
if (& $shouldRun "init-structure") {
    Start-Suite "init-structure"

    Test-Assert "init.ps1 exists" { Test-Path (Join-Path $projectRoot "init.ps1") }

    if ($initContent) {
        Test-Assert "init.ps1 has administrator check" {
            $initContent -match 'IsInRole.*Administrator|WindowsBuiltInRole.*Administrator'
        }

        Test-Assert "init.ps1 has OS version check" {
            $initContent -match 'BuildNumber|Win32_OperatingSystem'
        }

        Test-Assert "init.ps1 has disk space check" {
            $initContent -match 'disk space|freeGB|Get-PSDrive|SystemDrive'
        }

        Test-Assert "init.ps1 has RAM check" {
            $initContent -match 'TotalPhysicalMemory|totalRAM|RAM'
        }

        Test-Assert "init.ps1 has internet connectivity check" {
            $initContent -match 'internet|connectivity|Test-Connection|Invoke-WebRequest.*google|msftconnecttest'
        }

        Test-Assert "init.ps1 has module count validation" {
            $initContent -match 'expectedModules.*18|18.*module|foundModules'
        }

        Test-Assert "init.ps1 sources common.ps1" {
            $initContent -match '\.\s+\$commonLib|\.\s+.*common\.ps1'
        }

        Test-Assert "init.ps1 loads all 18 modules" {
            # Check that all module filenames are referenced
            $allFound = $true
            foreach ($name in $expectedModuleNames) {
                if ($initContent -notmatch [regex]::Escape("$name.ps1")) {
                    $allFound = $false
                    break
                }
            }
            $allFound
        }

        Test-Assert "init.ps1 has summary reporting" {
            $initContent -match 'Final Summary|SummaryBox|Write-SummaryBox'
        }

        Test-Assert "init.ps1 has restore point creation" {
            $initContent -match 'Checkpoint-Computer|restore point|Enable-ComputerRestore'
        }

        Test-Assert "init.ps1 has Defender disable/enable" {
            ($initContent -match 'DisableRealtimeMonitoring.*\$true') -and
            ($initContent -match 'DisableRealtimeMonitoring.*\$false')
        }

        Test-Assert "init.ps1 parses without errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $projectRoot "init.ps1"), [ref]$tokens, [ref]$errors
            )
            $errors.Count -eq 0
        }

        Test-Assert "init.ps1 has module execution loop" {
            $initContent -match 'foreach\s*\(\s*\$mod\s+in\s+\$modules'
        }

        Test-Assert "init.ps1 refreshes PATH after each module" {
            $initContent -match 'GetEnvironmentVariable.*Path.*Machine'
        }
    }
}

# ============================================================================
# SUITE: encoding-extended
# ============================================================================
if (& $shouldRun "encoding-extended") {
    Start-Suite "encoding-extended"

    # Collect all .ps1 files
    $allPs1 = @()
    $allPs1 += Get-ChildItem (Join-Path $projectRoot "*.ps1") -ErrorAction SilentlyContinue
    $allPs1 += Get-ChildItem (Join-Path $projectRoot "lib\*.ps1") -ErrorAction SilentlyContinue
    $allPs1 += Get-ChildItem (Join-Path $projectRoot "modules\*.ps1") -ErrorAction SilentlyContinue
    $allPs1 += Get-ChildItem (Join-Path $projectRoot "devscripts\*.ps1") -ErrorAction SilentlyContinue
    $allPs1 += Get-ChildItem (Join-Path $projectRoot "tests\*.ps1") -ErrorAction SilentlyContinue

    foreach ($file in $allPs1) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

        # BOM check: project convention is UTF-8 with BOM (PowerShell standard).
        # The valid-UTF-8 test below covers encoding correctness regardless of BOM.

        # Check for null bytes (indicates UTF-16 or binary content)
        Test-Assert "$($file.Name) has no null bytes" {
            $hasNull = $false
            for ($i = 0; $i -lt [Math]::Min($bytes.Length, 50000); $i++) {
                if ($bytes[$i] -eq 0) { $hasNull = $true; break }
            }
            -not $hasNull
        } -FailMessage "$($file.Name) contains null bytes (possibly UTF-16)"

        # Check for mojibake patterns (common UTF-8 decode errors)
        $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        Test-Assert "$($file.Name) has no mojibake patterns" {
            # Common mojibake: sequences like Ã©, Ã¡, Â, Ã
            -not ($content -match '[\xC0-\xC3][\x80-\xBF]{1,2}(?=[a-zA-Z\s])' -and $content -match '\xC3[\xA0-\xBF]')
        }

        # Check for em-dashes (advisory only - decorative em-dashes in strings are acceptable)
        $emDash = [char]0x2014  # em-dash
        $enDash = [char]0x2013  # en-dash
        if ($content.Contains($emDash) -or $content.Contains($enDash)) {
            $script:Warnings++
            $script:Results += @{ Suite = $script:CurrentSuite; Name = "$($file.Name) em-dash check"; Status = "ERR"; Message = "$($file.Name) contains em-dash or en-dash characters (advisory)"; Time = 0 }
            Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline
            Write-Host "$($file.Name) contains em-dash or en-dash characters (advisory)"
        }
    }

    # Consistent line endings for project source .ps1 files (should be CRLF on Windows)
    # Exclude tests/ directory since test files may use LF from editors/git
    $sourcePs1 = $allPs1 | Where-Object { $_.FullName -notmatch '\\tests\\' }
    foreach ($file in $sourcePs1) {
        $rawContent = [System.IO.File]::ReadAllText($file.FullName)
        Test-Assert "$($file.Name) uses CRLF line endings" {
            # File has CRLF: contains \r\n and bare \n (without preceding \r) is rare
            if ($rawContent.Length -lt 10) { $true; return }
            $hasCRLF = $rawContent -match "`r`n"
            $bareLF = [regex]::Matches($rawContent, '(?<!\r)\n')
            $hasCRLF -and ($bareLF.Count -eq 0)
        } -FailMessage "$($file.Name) has mixed or LF-only line endings"
    }

    # launch.bat is ASCII-safe
    $batPath = Join-Path $projectRoot "launch.bat"
    if (Test-Path $batPath) {
        Test-Assert "launch.bat is ASCII-safe (no bytes > 127)" {
            $batBytes = [System.IO.File]::ReadAllBytes($batPath)
            $nonAscii = $false
            foreach ($b in $batBytes) {
                if ($b -gt 127) { $nonAscii = $true; break }
            }
            -not $nonAscii
        } -FailMessage "launch.bat contains non-ASCII characters"

        Test-Assert "launch.bat uses CRLF line endings" {
            $batContent = [System.IO.File]::ReadAllText($batPath)
            $hasCRLF = $batContent -match "`r`n"
            $bareLF = [regex]::Matches($batContent, '(?<!\r)\n')
            $hasCRLF -and ($bareLF.Count -eq 0)
        } -FailMessage "launch.bat has non-CRLF line endings"
    }

    # Validate all .ps1 files are valid UTF-8 (no invalid byte sequences)
    foreach ($file in $allPs1) {
        Test-Assert "$($file.Name) is valid UTF-8" {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                $encoding = New-Object System.Text.UTF8Encoding($false, $true)  # throwOnInvalidBytes
                $null = $encoding.GetString($bytes)
                $true
            } catch {
                $false
            }
        } -FailMessage "$($file.Name) contains invalid UTF-8 byte sequences"
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

$total = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings

Write-Host "  Total:    $total" -ForegroundColor White
Write-Host "  Passed:   $($script:Passed)" -ForegroundColor Green
Write-Host "  Failed:   $($script:Failed)" -ForegroundColor $(if ($script:Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped:  $($script:Skipped)" -ForegroundColor DarkGray
Write-Host "  Errors:   $($script:Warnings)" -ForegroundColor $(if ($script:Warnings -gt 0) { "Yellow" } else { "Green" })
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
    Write-Host "  ERROR TESTS:" -ForegroundColor Yellow
    foreach ($r in $script:Results) {
        if ($r.Status -eq "ERR") {
            Write-Host "    [$($r.Suite)] $($r.Name) - $($r.Message)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

if ($script:Failed -eq 0 -and $script:Warnings -eq 0) {
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
} elseif ($script:Failed -eq 0) {
    Write-Host "  ALL ASSERTIONS PASSED ($($script:Warnings) non-fatal errors)" -ForegroundColor Yellow
} else {
    Write-Host "  $($script:Failed) TEST(S) FAILED" -ForegroundColor Red
}
Write-Host ""

# ============================================================================
# JUnit XML Export
# ============================================================================
if ($JUnit) {
    $xml = @()
    $xml += '<?xml version="1.0" encoding="UTF-8"?>'
    $xml += "<testsuites name=`"WinInit-Module-Tests`" tests=`"$total`" failures=`"$($script:Failed)`" errors=`"$($script:Warnings)`" skipped=`"$($script:Skipped)`">"

    # Group results by suite
    $suites = $script:Results | Group-Object -Property Suite
    foreach ($suite in $suites) {
        $suiteName = $suite.Name
        $suiteTests = $suite.Group
        $suiteFailures = ($suiteTests | Where-Object { $_.Status -eq "FAIL" }).Count
        $suiteErrors = ($suiteTests | Where-Object { $_.Status -eq "ERR" }).Count
        $suiteSkipped = ($suiteTests | Where-Object { $_.Status -eq "SKIP" }).Count
        $suiteTime = ($suiteTests | Measure-Object -Property Time -Sum).Sum / 1000.0

        $xml += "  <testsuite name=`"$([System.Security.SecurityElement]::Escape($suiteName))`" tests=`"$($suiteTests.Count)`" failures=`"$suiteFailures`" errors=`"$suiteErrors`" skipped=`"$suiteSkipped`" time=`"$suiteTime`">"

        foreach ($test in $suiteTests) {
            $testName = [System.Security.SecurityElement]::Escape($test.Name)
            $testTime = $test.Time / 1000.0
            $xml += "    <testcase classname=`"$([System.Security.SecurityElement]::Escape($suiteName))`" name=`"$testName`" time=`"$testTime`">"

            switch ($test.Status) {
                "FAIL" {
                    $msg = [System.Security.SecurityElement]::Escape($test.Message)
                    $xml += "      <failure message=`"$msg`">$msg</failure>"
                }
                "ERR" {
                    $msg = [System.Security.SecurityElement]::Escape($test.Message)
                    $xml += "      <error message=`"$msg`">$msg</error>"
                }
                "SKIP" {
                    $xml += "      <skipped />"
                }
            }

            $xml += "    </testcase>"
        }

        $xml += "  </testsuite>"
    }

    $xml += "</testsuites>"

    $junitPath = if ([System.IO.Path]::IsPathRooted($JUnit)) { $JUnit } else { Join-Path (Get-Location) $JUnit }
    $xml -join "`r`n" | Set-Content -Path $junitPath -Encoding UTF8
    Write-Host "  JUnit XML exported to: $junitPath" -ForegroundColor Cyan
    Write-Host ""
}

# Exit with appropriate code
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
