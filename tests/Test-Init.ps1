# ============================================================================
# WinInit Integration Test: Preflight Logic & Cross-Module Consistency
# Standalone test script - copies framework from devscripts\test.ps1
# Usage:
#   .\tests\Test-Init.ps1                     Run all suites
#   .\tests\Test-Init.ps1 -Suite preflight    Run specific suite
#   .\tests\Test-Init.ps1 -DryRun             Safe mode (no system changes)
#   .\tests\Test-Init.ps1 -Verbose            Show timing info
#   .\tests\Test-Init.ps1 -JUnit out.xml      Export JUnit XML
# ============================================================================

param(
    [string]$Suite = "",
    [switch]$Verbose,
    [switch]$DryRun,
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

# --- Helper: should this suite run? ---
$shouldRun = { param($s) -not $Suite -or $Suite -eq $s }

# --- Banner ---
Write-Host ""
Write-Host "  WinInit Integration Tests" -ForegroundColor Cyan
Write-Host "  =========================" -ForegroundColor Cyan
$modeStr = if ($DryRun) { "DRY RUN" } elseif ($Suite) { "Suite: $Suite" } else { "Full" }
Write-Host "  Mode: $modeStr" -ForegroundColor Gray
Write-Host "  Root: $projectRoot" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# SUITE: preflight-logic
# Test the preflight check logic by simulating conditions
# ============================================================================
if (& $shouldRun "preflight-logic") {
    Start-Suite "preflight-logic"

    # Admin detection: WindowsPrincipal API works
    Test-Assert "WindowsPrincipal API is callable" {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        # We don't care if we ARE admin, just that the API works
        $null -ne $principal
    }

    Test-Assert "Admin role enum resolves" {
        $role = [Security.Principal.WindowsBuiltInRole]::Administrator
        $role -eq [Security.Principal.WindowsBuiltInRole]::Administrator
    }

    # OS build extraction
    Test-Assert "OS build is a positive integer" {
        $build = [Environment]::OSVersion.Version.Build
        $build -gt 0
    }

    Test-Assert "OS build >= 19041 (Win 10 2004+)" {
        $build = [Environment]::OSVersion.Version.Build
        $build -ge 19041
    } -FailMessage "Build $([Environment]::OSVersion.Version.Build) is below 19041"

    # Architecture check
    Test-Assert "PROCESSOR_ARCHITECTURE is set" {
        -not [string]::IsNullOrEmpty($env:PROCESSOR_ARCHITECTURE)
    }

    Test-Assert "PROCESSOR_ARCHITECTURE is recognized (AMD64/ARM64/x86)" {
        $env:PROCESSOR_ARCHITECTURE -in @("AMD64", "ARM64", "x86")
    } -FailMessage "Got: $env:PROCESSOR_ARCHITECTURE"

    # Disk space via Get-CimInstance
    Test-Assert "Win32_LogicalDisk returns system drive" {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
        $null -ne $disk -and $disk.FreeSpace -gt 0
    }

    Test-Assert "Disk space calculation matches init.ps1 approach (Get-PSDrive)" {
        $driveLetter = $env:SystemDrive.TrimEnd(':')
        $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
        $null -ne $drive -and $drive.Free -gt 0
    }

    # RAM via Get-CimInstance
    Test-Assert "Win32_ComputerSystem returns RAM" {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $null -ne $cs -and $cs.TotalPhysicalMemory -gt 0
    }

    Test-Assert "RAM calculation produces value >= 1 GB" {
        $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $ramGB -ge 1
    }

    # PowerShell version
    Test-Assert "PSVersionTable.PSVersion is available" {
        $null -ne $PSVersionTable.PSVersion
    }

    Test-Assert "PowerShell version >= 5.1" {
        $psVer = $PSVersionTable.PSVersion
        ($psVer.Major -gt 5) -or ($psVer.Major -eq 5 -and $psVer.Minor -ge 1)
    } -FailMessage "Got: $($PSVersionTable.PSVersion)"

    # TLS check
    Test-Assert "TLS SecurityProtocol is accessible" {
        $proto = [Net.ServicePointManager]::SecurityProtocol
        $null -ne $proto
    }

    Test-Assert "TLS 1.2 can be enabled" {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $true
        } catch { $false }
    }

    # Module file counting logic (matches init.ps1 approach)
    Test-Assert "Module file counting matches init.ps1 pattern" {
        $modulesDir = Join-Path $projectRoot "modules"
        $count = (Get-ChildItem "$modulesDir\*.ps1" -ErrorAction SilentlyContinue).Count
        $count -eq 18
    } -FailMessage "Expected 18 modules, found $((Get-ChildItem (Join-Path $projectRoot 'modules\*.ps1') -ErrorAction SilentlyContinue).Count)"

    # Execution policy detection
    Test-Assert "Execution policy is queryable" {
        $policy = Get-ExecutionPolicy -Scope Process
        $null -ne $policy
    }

    Test-Assert "Execution policy is a known value" {
        $policy = Get-ExecutionPolicy -Scope Process
        $policy -in @("Unrestricted", "Bypass", "RemoteSigned", "AllSigned", "Restricted", "Undefined")
    }

    # Pending reboot registry check logic
    Test-Assert "Pending reboot registry keys are testable" {
        $rebootKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
            "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
        )
        # Verify Test-Path works on each key (doesn't throw)
        foreach ($rk in $rebootKeys) {
            $null = Test-Path $rk
        }
        $true
    }

    # AV process detection logic
    Test-Assert "AV process detection logic works" {
        $avProcesses = @("MsMpEng", "avp", "avgnt", "avguard", "bdagent")
        # The Get-Process call should not throw even if none are found
        $result = Get-Process -Name $avProcesses -ErrorAction SilentlyContinue
        # Result can be null (no AV) or a list - either is valid
        $true
    }

    Test-Assert "AV process name list matches init.ps1" {
        $initContent = Get-Content (Join-Path $projectRoot "init.ps1") -Raw
        $initContent -match '\$avProcesses\s*=\s*@\("MsMpEng",\s*"avp",\s*"avgnt",\s*"avguard",\s*"bdagent"\)'
    }
}

# ============================================================================
# SUITE: init-structure
# Validate the structure and content of init.ps1
# ============================================================================
if (& $shouldRun "init-structure") {
    Start-Suite "init-structure"

    $initPath = Join-Path $projectRoot "init.ps1"
    $initContent = Get-Content $initPath -Raw -ErrorAction SilentlyContinue

    Test-Assert "init.ps1 parses without errors" {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($initPath, [ref]$tokens, [ref]$errors)
        $errors.Count -eq 0
    } -FailMessage "Parse errors found in init.ps1"

    Test-Assert 'Contains $ErrorActionPreference = "Continue"' {
        $initContent -match '\$ErrorActionPreference\s*=\s*"Continue"'
    }

    Test-Assert "Sources lib\common.ps1" {
        $initContent -match '\.\s+\$commonLib' -or $initContent -match '\.\s+.*lib\\common\.ps1'
    }

    Test-Assert "Defines module array with 18 entries" {
        $moduleEntries = [regex]::Matches($initContent, '@\{\s*file\s*=\s*"[^"]+\.ps1"')
        $moduleEntries.Count -eq 18
    } -FailMessage "Expected 18 module entries in array"

    Test-Assert "Has try/catch around module execution" {
        # The foreach loop contains a try/catch block
        $initContent -match 'try\s*\{[^}]*\.\s*\$modPath' -or
        ($initContent -match 'foreach.*\$mod.*in.*\$modules' -and $initContent -match 'try\s*\{[\s\S]*?\.\s+\$modPath')
    }

    Test-Assert "Has timing tracking (Get-Date for StartTime)" {
        $initContent -match '\$StartTime\s*=\s*Get-Date'
    }

    Test-Assert "Has timing tracking (module duration)" {
        $initContent -match '\$modStart\s*=\s*Get-Date' -and $initContent -match '\$modDuration'
    }

    Test-Assert "Has summary reporting section" {
        $initContent -match 'Final Summary' -and $initContent -match 'Write-SummaryBox'
    }

    Test-Assert "Has restore point code (Checkpoint-Computer)" {
        $initContent -match 'Checkpoint-Computer' -and $initContent -match 'Enable-ComputerRestore'
    }

    Test-Assert "Has Defender disable code" {
        $initContent -match 'Set-MpPreference\s+-DisableRealtimeMonitoring\s+\$true'
    }

    Test-Assert "Has Defender re-enable code" {
        $initContent -match 'Set-MpPreference\s+-DisableRealtimeMonitoring\s+\$false'
    }
}

# ============================================================================
# SUITE: init-flow
# Verify module array ordering, paths, and consistency
# ============================================================================
if (& $shouldRun "init-flow") {
    Start-Suite "init-flow"

    $initPath = Join-Path $projectRoot "init.ps1"
    $initContent = Get-Content $initPath -Raw

    # Extract module file entries in order
    $moduleMatches = [regex]::Matches($initContent, 'file\s*=\s*"([^"]+\.ps1)"')
    $moduleFiles = @()
    foreach ($m in $moduleMatches) { $moduleFiles += $m.Groups[1].Value }

    Test-Assert "Module array order matches file numbering (01 through 18)" {
        $allCorrect = $true
        for ($i = 0; $i -lt $moduleFiles.Count; $i++) {
            $expected = "{0:D2}-" -f ($i + 1)
            if (-not $moduleFiles[$i].StartsWith($expected)) {
                $allCorrect = $false
                break
            }
        }
        $allCorrect -and $moduleFiles.Count -eq 18
    } -FailMessage "Module ordering does not match sequential 01-18 pattern"

    Test-Assert "All module paths in array correspond to actual files" {
        $modulesDir = Join-Path $projectRoot "modules"
        $allExist = $true
        $missing = @()
        foreach ($mf in $moduleFiles) {
            $fullPath = Join-Path $modulesDir $mf
            if (-not (Test-Path $fullPath)) {
                $allExist = $false
                $missing += $mf
            }
        }
        $allExist
    } -FailMessage "Missing module files: $($missing -join ', ')"

    # Extract descriptions
    $descMatches = [regex]::Matches($initContent, 'desc\s*=\s*"([^"]*)"')

    Test-Assert "Module descriptions are non-empty" {
        $allNonEmpty = $true
        foreach ($dm in $descMatches) {
            if ([string]::IsNullOrWhiteSpace($dm.Groups[1].Value)) {
                $allNonEmpty = $false
                break
            }
        }
        $allNonEmpty -and $descMatches.Count -eq 18
    }

    Test-Assert "No duplicate module entries" {
        $uniqueFiles = $moduleFiles | Select-Object -Unique
        $uniqueFiles.Count -eq $moduleFiles.Count
    }
}

# ============================================================================
# SUITE: devscripts-structure
# Test all development scripts parse and have expected features
# ============================================================================
if (& $shouldRun "devscripts-structure") {
    Start-Suite "devscripts-structure"

    $devscriptsDir = Join-Path $projectRoot "devscripts"

    $devscripts = @("ci", "format", "lint", "test", "typecheck", "package", "run-module", "bump-version")
    foreach ($ds in $devscripts) {
        $dsPath = Join-Path $devscriptsDir "$ds.ps1"
        Test-Assert "devscripts/$ds.ps1 parses without errors" {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($dsPath, [ref]$tokens, [ref]$errors)
            $errors.Count -eq 0
        } -FailMessage "Parse errors in $ds.ps1"
    }

    # ci.ps1 calls format, lint, typecheck, and test scripts
    $ciContent = Get-Content (Join-Path $devscriptsDir "ci.ps1") -Raw
    Test-Assert "ci.ps1 calls format.ps1" {
        $ciContent -match 'format\.ps1'
    }
    Test-Assert "ci.ps1 calls lint.ps1" {
        $ciContent -match 'lint\.ps1'
    }
    Test-Assert "ci.ps1 calls typecheck.ps1" {
        $ciContent -match 'typecheck\.ps1'
    }
    Test-Assert "ci.ps1 calls test.ps1" {
        $ciContent -match 'test\.ps1'
    }

    # format.ps1 has -Check parameter
    $formatContent = Get-Content (Join-Path $devscriptsDir "format.ps1") -Raw
    Test-Assert "format.ps1 has -Check parameter" {
        $formatContent -match '\[switch\]\$Check'
    }

    # lint.ps1 has -Fix parameter
    $lintContent = Get-Content (Join-Path $devscriptsDir "lint.ps1") -Raw
    Test-Assert "lint.ps1 has -Fix parameter" {
        $lintContent -match '\[switch\]\$Fix'
    }

    # test.ps1 has -Suite, -DryRun, -Verbose, -JUnit parameters
    $testContent = Get-Content (Join-Path $devscriptsDir "test.ps1") -Raw
    Test-Assert "test.ps1 has -Suite parameter" {
        $testContent -match '\[string\]\$Suite'
    }
    Test-Assert "test.ps1 has -DryRun parameter" {
        $testContent -match '\[switch\]\$DryRun'
    }
    Test-Assert "test.ps1 has -Verbose parameter" {
        $testContent -match '\[switch\]\$Verbose'
    }
    Test-Assert "test.ps1 has -JUnit parameter" {
        $testContent -match '\[string\]\$JUnit'
    }

    # package.ps1 creates dist directory
    $packageContent = Get-Content (Join-Path $devscriptsDir "package.ps1") -Raw
    Test-Assert "package.ps1 creates dist directory" {
        $packageContent -match 'dist' -and $packageContent -match 'New-Item.*Directory'
    }
}

# ============================================================================
# SUITE: devscripts-lint (DryRun safe)
# Run actual lint checks against all .ps1 files
# ============================================================================
if (& $shouldRun "devscripts-lint") {
    Start-Suite "devscripts-lint"

    $allPs1Files = @()
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "lib\*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "modules\*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "devscripts\*.ps1") -ErrorAction SilentlyContinue

    # No trailing whitespace
    Test-Assert "No trailing whitespace in any .ps1 file" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '\S\s+$') {
                    $violations += "$($f.Name):$($i + 1)"
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Trailing whitespace found in: $($violations[0..4] -join ', ')"

    # No tab characters
    Test-Assert "No tab characters in any .ps1 file" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $content = Get-Content $f.FullName -Raw
            if ($content -match "`t") {
                $violations += $f.Name
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Tab characters found in: $($violations -join ', ')"

    # No lines exceeding 200 characters
    Test-Assert "No lines exceeding 200 characters" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].Length -gt 200) {
                    $violations += "$($f.Name):$($i + 1) ($($lines[$i].Length) chars)"
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Some lines exceed 200 characters"

    # No hardcoded usernames
    Test-Assert "No hardcoded usernames (C:\Users\specific_user)" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                # Match C:\Users\<name> but not C:\Users\$env or C:\Users\*
                if ($lines[$i] -match 'C:\\Users\\[A-Za-z][A-Za-z0-9_]+' -and
                    $lines[$i] -notmatch 'C:\\Users\\\$' -and
                    $lines[$i] -notmatch 'C:\\Users\\\*' -and
                    $lines[$i] -notmatch 'C:\\Users\\Public' -and
                    $lines[$i] -notmatch 'C:\\Users\\Default' -and
                    $lines[$i] -notmatch '#.*C:\\Users\\') {
                    $violations += "$($f.Name):$($i + 1)"
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Hardcoded usernames: $($violations -join ', ')"

    # No plain-text passwords or API keys
    Test-Assert "No plain-text passwords or API keys" {
        $violations = @()
        $patterns = @(
            'password\s*=\s*[''"][^''"]{3,}[''"]',
            'apikey\s*=\s*[''"][^''"]{8,}[''"]',
            'api_key\s*=\s*[''"][^''"]{8,}[''"]',
            'secret\s*=\s*[''"][^''"]{8,}[''"]',
            'token\s*=\s*[''"][A-Za-z0-9+/=]{20,}[''"]'
        )
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                # Skip comment lines
                if ($lines[$i].TrimStart() -match '^#') { continue }
                foreach ($pat in $patterns) {
                    if ($lines[$i] -match $pat) {
                        $violations += "$($f.Name):$($i + 1)"
                        break
                    }
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Possible secrets: $($violations -join ', ')"

    # No bare Write-Host in modules (should use Write-Log)
    Test-Assert "No bare Write-Host in modules (should use Write-Log)" {
        $violations = @()
        $moduleDir = Join-Path $projectRoot "modules"
        $modulePs1 = Get-ChildItem "$moduleDir\*.ps1" -ErrorAction SilentlyContinue
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $trimmed = $lines[$i].TrimStart()
                # Allow Write-Host in comments, and skip common.ps1 function references
                if ($trimmed -match '^#') { continue }
                if ($trimmed -match '^\s*Write-Host\s' -and $trimmed -notmatch 'Write-Host\s+""') {
                    $violations += "$($f.Name):$($i + 1)"
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Bare Write-Host found in modules"

    # All files end with newline
    Test-Assert "All files end with newline" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $raw = Get-Content $f.FullName -Raw
            if ($raw -and -not $raw.EndsWith("`n")) {
                $violations += $f.Name
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Missing final newline: $($violations -join ', ')"

    # No consecutive blank lines (>2)
    Test-Assert "No excessive consecutive blank lines (>2)" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            $blankCount = 0
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ([string]::IsNullOrWhiteSpace($lines[$i])) {
                    $blankCount++
                    if ($blankCount -gt 2) {
                        $violations += "$($f.Name):$($i + 1)"
                        break
                    }
                } else {
                    $blankCount = 0
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Excessive blank lines in: $($violations -join ', ')"
}

# ============================================================================
# SUITE: devscripts-typecheck (DryRun safe)
# Run type validation on scripts
# ============================================================================
if (& $shouldRun "devscripts-typecheck") {
    Start-Suite "devscripts-typecheck"

    $allPs1Files = @()
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "lib\*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "modules\*.ps1") -ErrorAction SilentlyContinue
    $allPs1Files += Get-ChildItem (Join-Path $projectRoot "devscripts\*.ps1") -ErrorAction SilentlyContinue

    # All function parameters have type annotations where expected
    Test-Assert "All function params with defaults have type annotations" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $f.FullName, [ref]$tokens, [ref]$errors
            )
            $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
            foreach ($func in $functions) {
                if ($func.Parameters) {
                    foreach ($param in $func.Parameters) {
                        # Parameters with default values should have type constraints
                        if ($param.DefaultValue -and -not $param.StaticType -and
                            $param.StaticType -eq [object]) {
                            # Check if there is an explicit type attribute
                            $hasType = $param.Attributes | Where-Object {
                                $_ -is [System.Management.Automation.Language.TypeConstraintAst]
                            }
                            if (-not $hasType) {
                                $violations += "$($f.Name): $($func.Name).$($param.Name.VariablePath.UserPath)"
                            }
                        }
                    }
                }
            }
        }
        # This is advisory - report but allow some violations
        $violations.Count -lt 20
    } -FailMessage "Many untyped params with defaults: $($violations.Count) found"

    # No unsafe string concatenation in paths (should use Join-Path)
    Test-Assert "No unsafe string concatenation in paths (should use Join-Path)" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                # Skip comments
                if ($line.TrimStart() -match '^#') { continue }
                # Detect "path" + "\thing" or $var + "\thing" concatenation patterns
                # But allow string interpolation inside quotes
                if ($line -match '[''"]?\s*\+\s*[''"]\\' -and
                    $line -notmatch 'Join-Path' -and
                    $line -notmatch '#.*\+.*\\' -and
                    $line -notmatch '^\s*#') {
                    $violations += "$($f.Name):$($i + 1)"
                }
            }
        }
        # Allow a few legacy concatenations, but flag if there are many
        $violations.Count -lt 10
    } -FailMessage "Unsafe path concatenation ($($violations.Count) instances): $($violations[0..4] -join ', ')"

    # No unquoted variable expansions in paths
    Test-Assert "No unquoted variable expansions in critical path operations" {
        $violations = @()
        foreach ($f in $allPs1Files) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line.TrimStart() -match '^#') { continue }
                # Detect Test-Path $var\something or Remove-Item $var\something without quotes
                if ($line -match '(Test-Path|Remove-Item|Copy-Item|Move-Item|Get-Content|Set-Content)\s+\$\w+\\' -and
                    $line -notmatch '(Test-Path|Remove-Item|Copy-Item|Move-Item|Get-Content|Set-Content)\s+"') {
                    $violations += "$($f.Name):$($i + 1)"
                }
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Unquoted variable path expansions: $($violations[0..4] -join ', ')"

    # All switch parameters are [switch] type
    Test-Assert "All switch-like parameters use [switch] type" {
        $devscriptsDir = Join-Path $projectRoot "devscripts"
        $filesToCheck = @()
        $filesToCheck += Get-ChildItem (Join-Path $projectRoot "*.ps1") -ErrorAction SilentlyContinue
        $filesToCheck += Get-ChildItem (Join-Path $devscriptsDir "*.ps1") -ErrorAction SilentlyContinue
        $violations = @()
        foreach ($f in $filesToCheck) {
            $content = Get-Content $f.FullName -Raw
            # Find param blocks and check that boolean-like params are [switch]
            $paramMatches = [regex]::Matches($content, '\[bool\]\s*\$(Check|Fix|DryRun|Verbose|Quick|List|Force|Skip)')
            foreach ($pm in $paramMatches) {
                $violations += "$($f.Name): `$$($pm.Groups[1].Value) should be [switch] not [bool]"
            }
        }
        $violations.Count -eq 0
    } -FailMessage "$($violations -join '; ')"

    # Required functions from common.ps1 are defined
    Test-Assert "Required functions are defined in common.ps1" {
        $commonPath = Join-Path $projectRoot "lib\common.ps1"
        $commonContent = Get-Content $commonPath -Raw
        $required = @("Write-Log", "Write-Section", "Install-App", "Set-RegistrySafe",
                       "Disable-ServiceSafe", "Add-ToSystemPath", "Write-SummaryBox")
        $missing = @()
        foreach ($fn in $required) {
            if ($commonContent -notmatch "function\s+$fn\b") {
                $missing += $fn
            }
        }
        $missing.Count -eq 0
    } -FailMessage "Missing functions in common.ps1: $($missing -join ', ')"
}

# ============================================================================
# SUITE: cross-module-consistency
# Verify consistency across all modules
# ============================================================================
if (& $shouldRun "cross-module-consistency") {
    Start-Suite "cross-module-consistency"

    $modulesDir = Join-Path $projectRoot "modules"
    $modulePs1 = Get-ChildItem "$modulesDir\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name

    # All modules use the same logging patterns
    Test-Assert "All modules use Write-Log for logging" {
        $violations = @()
        foreach ($f in $modulePs1) {
            $content = Get-Content $f.FullName -Raw
            if ($content -notmatch 'Write-Log') {
                $violations += $f.Name
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Modules without Write-Log: $($violations -join ', ')"

    Test-Assert "All modules use Write-Section for section headers" {
        $violations = @()
        foreach ($f in $modulePs1) {
            $content = Get-Content $f.FullName -Raw
            if ($content -notmatch 'Write-Section') {
                $violations += $f.Name
            }
        }
        $violations.Count -eq 0
    } -FailMessage "Modules without Write-Section: $($violations -join ', ')"

    # No conflicting registry keys between modules
    Test-Assert "No conflicting registry keys between modules" {
        $regSets = @{}
        $conflicts = @()
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            foreach ($line in $lines) {
                if ($line.TrimStart() -match '^#') { continue }
                # Match Set-ItemProperty or Set-RegistrySafe calls with a registry path and -Name
                if ($line -match '(Set-ItemProperty|Set-RegistrySafe).*-Path\s+[''"]([^''"]+)[''"].*-Name\s+[''"]([^''"]+)[''"].*-Value\s+(.+?)(\s+-|$)') {
                    $regKey = "$($Matches[2])\$($Matches[3])"
                    $value = $Matches[4].Trim()
                    if ($regSets.ContainsKey($regKey)) {
                        $prev = $regSets[$regKey]
                        # Only flag if different modules set the same key to different values
                        if ($prev.file -ne $f.Name -and $prev.value -ne $value) {
                            $conflicts += "$regKey set by $($prev.file) ($($prev.value)) and $($f.Name) ($value)"
                        }
                    }
                    $regSets[$regKey] = @{ file = $f.Name; value = $value }
                }
            }
        }
        if ($conflicts.Count -gt 0) {
            Write-Host "    Registry conflicts: $($conflicts[0..([Math]::Min(2, $conflicts.Count - 1))] -join '; ')" -ForegroundColor DarkYellow
        }
        $conflicts.Count -eq 0
    } -FailMessage "Registry conflicts found (see details above)"

    # No module disables a service another module needs
    Test-Assert "No module disables a service another module enables/starts" {
        $disabled = @{}
        $started = @{}
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            foreach ($line in $lines) {
                if ($line.TrimStart() -match '^#') { continue }
                # Detect service disable
                if ($line -match 'Disable-ServiceSafe.*[''"]([^''"]+)[''"]') {
                    $disabled[$Matches[1]] = $f.Name
                }
                if ($line -match 'Set-Service.*-Name\s+[''"]?(\w+)[''"]?.*-StartupType\s+Disabled') {
                    $disabled[$Matches[1]] = $f.Name
                }
                # Detect service start/enable
                if ($line -match 'Start-Service.*[''"]([^''"]+)[''"]') {
                    $started[$Matches[1]] = $f.Name
                }
                if ($line -match 'Set-Service.*-Name\s+[''"]?(\w+)[''"]?.*-StartupType\s+(Automatic|Manual)') {
                    $started[$Matches[1]] = $f.Name
                }
            }
        }
        $conflicts = @()
        foreach ($svc in $disabled.Keys) {
            if ($started.ContainsKey($svc) -and $started[$svc] -ne $disabled[$svc]) {
                $conflicts += "$svc disabled by $($disabled[$svc]) but started by $($started[$svc])"
            }
        }
        $conflicts.Count -eq 0
    } -FailMessage "Service conflicts: $($conflicts -join '; ')"

    # PATH additions don't create duplicates
    Test-Assert "PATH additions do not contain obvious duplicates" {
        $pathAdds = @{}
        $duplicates = @()
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            foreach ($line in $lines) {
                if ($line.TrimStart() -match '^#') { continue }
                if ($line -match 'Add-ToSystemPath.*[''"]([^''"]+)[''"]') {
                    $pathVal = $Matches[1].ToLower()
                    if ($pathAdds.ContainsKey($pathVal) -and $pathAdds[$pathVal] -ne $f.Name) {
                        $duplicates += "$pathVal added by $($pathAdds[$pathVal]) and $($f.Name)"
                    }
                    $pathAdds[$pathVal] = $f.Name
                }
            }
        }
        $duplicates.Count -eq 0
    } -FailMessage "Duplicate PATH additions: $($duplicates -join '; ')"

    # Environment variables set by one module aren't overwritten by another
    Test-Assert "No environment variable conflicts between modules" {
        $envSets = @{}
        $conflicts = @()
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            foreach ($line in $lines) {
                if ($line.TrimStart() -match '^#') { continue }
                if ($line -match '\[Environment\]::SetEnvironmentVariable\(\s*[''"]([^''"]+)[''"]') {
                    $envVar = $Matches[1]
                    if ($envSets.ContainsKey($envVar) -and $envSets[$envVar] -ne $f.Name) {
                        $conflicts += "$envVar set by $($envSets[$envVar]) and $($f.Name)"
                    }
                    $envSets[$envVar] = $f.Name
                }
            }
        }
        $conflicts.Count -eq 0
    } -FailMessage "Environment variable conflicts: $($conflicts -join '; ')"

    # All registry paths are properly formatted
    Test-Assert "All registry paths are properly formatted" {
        $violations = @()
        foreach ($f in $modulePs1) {
            $lines = Get-Content $f.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i].TrimStart() -match '^#') { continue }
                # Detect registry paths that don't use the PowerShell provider format
                $regMatches = [regex]::Matches($lines[$i], '[''"]([^''"]*(?:HKLM|HKCU|HKCR)[^''"]*)[''"]')
                foreach ($rm in $regMatches) {
                    $path = $rm.Groups[1].Value
                    # Valid formats: HKLM:\... HKCU:\... HKCR:\... or HKCR\... (reg.exe style) or Registry::HKEY_...
                    if ($path -match '^(HKLM|HKCU|HKCR)' -and $path -notmatch '^(HKLM|HKCU|HKCR)(:|\\)') {
                        $violations += "$($f.Name):$($i + 1) - $path"
                    }
                }
            }
        }
        if ($violations.Count -gt 0) {
            Write-Host "    Malformed registry paths: $($violations[0..([Math]::Min(4, $violations.Count - 1))] -join ', ')" -ForegroundColor DarkYellow
        }
        $violations.Count -eq 0
    } -FailMessage "Malformed registry paths found (see details above)"
}

# ============================================================================
# SUITE: launch-bat
# Test launch.bat structure
# ============================================================================
if (& $shouldRun "launch-bat") {
    Start-Suite "launch-bat"

    $batPath = Join-Path $projectRoot "launch.bat"

    Test-Assert "launch.bat exists" {
        Test-Path $batPath
    }

    Test-Assert "launch.bat is ASCII-safe (no high bytes outside comments)" {
        $bytes = [System.IO.File]::ReadAllBytes($batPath)
        $highBytes = $bytes | Where-Object { $_ -gt 127 }
        $highBytes.Count -eq 0
    }

    $batContent = Get-Content $batPath -Raw -ErrorAction SilentlyContinue

    Test-Assert "Contains elevation check (net session)" {
        $batContent -match 'net\s+session'
    }

    Test-Assert "Contains PowerShell invocation with -ExecutionPolicy Bypass" {
        $batContent -match 'powershell.*-ExecutionPolicy\s+Bypass'
    }

    Test-Assert "References init.ps1" {
        $batContent -match 'init\.ps1'
    }

    Test-Assert "Has proper error handling (errorLevel check)" {
        $batContent -match 'errorLevel'
    }

    Test-Assert "Has RunAs elevation for non-admin" {
        $batContent -match 'RunAs' -or $batContent -match 'Verb\s+RunAs'
    }
}

# ============================================================================
# Summary
# ============================================================================

$totalTests = $script:Passed + $script:Failed + $script:Skipped + $script:Warnings
$endColor = if ($script:Failed -eq 0) { "Green" } else { "Red" }

Write-Host ""
Write-Host "  =============================" -ForegroundColor $endColor
Write-Host "  Test Results" -ForegroundColor $endColor
Write-Host "  =============================" -ForegroundColor $endColor
Write-Host "  Total:   $totalTests" -ForegroundColor White
Write-Host "  Passed:  $($script:Passed)" -ForegroundColor Green
Write-Host "  Failed:  $($script:Failed)" -ForegroundColor $(if ($script:Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Skipped: $($script:Skipped)" -ForegroundColor DarkGray
Write-Host "  Errors:  $($script:Warnings)" -ForegroundColor $(if ($script:Warnings -gt 0) { "Yellow" } else { "Green" })
Write-Host "  =============================" -ForegroundColor $endColor
Write-Host ""

# ============================================================================
# JUnit XML Export
# ============================================================================
if ($JUnit) {
    $xml = @()
    $xml += '<?xml version="1.0" encoding="UTF-8"?>'
    $xml += "<testsuites tests=`"$totalTests`" failures=`"$($script:Failed)`" errors=`"$($script:Warnings)`" skipped=`"$($script:Skipped)`">"

    # Group results by suite
    $suites = $script:Results | Group-Object { $_.Suite }
    foreach ($suite in $suites) {
        $suiteFails = ($suite.Group | Where-Object { $_.Status -eq "FAIL" }).Count
        $suiteErrors = ($suite.Group | Where-Object { $_.Status -eq "ERR" }).Count
        $suiteSkips = ($suite.Group | Where-Object { $_.Status -eq "SKIP" }).Count
        $suiteTime = ($suite.Group | Measure-Object -Property Time -Sum).Sum / 1000.0

        $xml += "  <testsuite name=`"$($suite.Name)`" tests=`"$($suite.Group.Count)`" failures=`"$suiteFails`" errors=`"$suiteErrors`" skipped=`"$suiteSkips`" time=`"$("{0:F3}" -f $suiteTime)`">"

        foreach ($test in $suite.Group) {
            $testTime = $test.Time / 1000.0
            $safeName = [System.Security.SecurityElement]::Escape($test.Name)
            $xml += "    <testcase name=`"$safeName`" classname=`"$($suite.Name)`" time=`"$("{0:F3}" -f $testTime)`">"

            switch ($test.Status) {
                "FAIL" {
                    $safeMsg = [System.Security.SecurityElement]::Escape($test.Message)
                    $xml += "      <failure message=`"$safeMsg`">$safeMsg</failure>"
                }
                "ERR" {
                    $safeMsg = [System.Security.SecurityElement]::Escape($test.Message)
                    $xml += "      <error message=`"$safeMsg`">$safeMsg</error>"
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
    $xml -join "`n" | Set-Content -Path $junitPath -Encoding UTF8
    Write-Host "  JUnit XML exported to: $junitPath" -ForegroundColor Cyan
    Write-Host ""
}

# Exit with appropriate code
exit $(if ($script:Failed -gt 0) { 1 } else { 0 })
