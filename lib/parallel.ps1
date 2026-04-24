# ============================================================================
# WinInit - Safe Parallel Module Execution
# Enables running independent modules concurrently (opt-in via -Parallel)
# ============================================================================

# --- Module Dependency Map ---
# Modules that MUST run before others
$script:ModuleDependencies = @{
    "02-Applications"      = @("01-PackageManagers")    # Need package managers first
    "13-BrowserExtensions" = @("02-Applications")       # Need browsers installed
    "14-DevTools"          = @("01-PackageManagers")    # Need package managers
    "15-PortableTools"     = @("02-Applications")       # Need 7-zip for extraction
    "16-UnixEnvironment"   = @("01-PackageManagers")    # Need scoop/choco
    "17-VSCodeSetup"       = @("02-Applications")       # Need VS Code installed
}

# --- Parallel Groups ---
# Modules that can safely run together (no shared state conflicts)
$script:ParallelGroups = @(
    @{
        name    = "Registry Tweaks"
        modules = @("03-DesktopEnvironment", "05-Performance", "07-Privacy", "09-Services", "10-NetworkPerformance", "11-VisualUX")
    },
    @{
        name    = "Downloads & Installs"
        modules = @("14-DevTools", "15-PortableTools", "16-UnixEnvironment")
    }
)

# --- Modules that MUST always run sequentially ---
$script:SequentialOnly = @(
    "01-PackageManagers",
    "02-Applications",
    "04-OneDriveRemoval",
    "06-Debloat",
    "08-QualityOfLife",
    "12-SecurityHardening",
    "13-BrowserExtensions",
    "17-VSCodeSetup",
    "18-FinalConfig"
)

# ============================================================================
# Test-DependenciesMet
# Check whether all dependencies for a given module have completed
# ============================================================================

function Test-DependenciesMet {
    param(
        [string]$ModuleName,
        [string[]]$CompletedModules
    )
    $prefix = if ($ModuleName -match '^(\d{2}-[^.]+)') { $Matches[1] } else { $ModuleName }
    $deps = $script:ModuleDependencies[$prefix]
    if (-not $deps) { return $true }

    foreach ($dep in $deps) {
        $depMet = $false
        foreach ($cm in $CompletedModules) {
            if ($cm -match "^${dep}") { $depMet = $true; break }
        }
        if (-not $depMet) { return $false }
    }
    return $true
}

# ============================================================================
# Get-ModulePrefix
# Extract "01-PackageManagers" from "01-PackageManagers.ps1"
# ============================================================================

function Get-ModulePrefix {
    param([string]$FileName)
    if ($FileName -match '^(\d{2}-[^.]+)') { return $Matches[1] }
    return $FileName
}

# ============================================================================
# Invoke-ParallelModules
# Run a batch of modules concurrently using PowerShell jobs
# ============================================================================

function Invoke-ParallelModules {
    param(
        [array]$Modules,           # Array of module hashtables (file, desc)
        [string]$GroupName,        # Friendly name for logging
        [string]$ScriptRoot,       # $PSScriptRoot from init.ps1
        [string]$CommonLib         # Path to common.ps1
    )

    $results = @()
    $jobMap = @{}

    Write-Log "Starting parallel group: $GroupName ($($Modules.Count) modules)" "INFO"

    foreach ($mod in $Modules) {
        $modPath = Join-Path $ScriptRoot "modules\$($mod.file)"
        if (-not (Test-Path $modPath)) {
            Write-Log "MODULE NOT FOUND: $modPath" "ERROR"
            $results += @{
                name     = $mod.file
                duration = [timespan]::Zero
                status   = "SKIP"
                output   = "Module file not found"
            }
            continue
        }

        $modStart = Get-Date

        # Use Start-Job to run each module in a separate process
        # Each job gets its own copy of common.ps1 and the module script
        $job = Start-Job -ScriptBlock {
            param($CommonLibPath, $ModulePath, $ModuleFile, $LogFilePath)

            $ErrorActionPreference = "Continue"

            # Minimal environment setup for the job
            $script:LogFile    = $LogFilePath
            $script:TotalSteps = 0
            $script:CurrentStep = 0
            $script:SectionName = ""
            $script:VTEnabled  = $false
            $script:DryRunMode = $false
            $script:Config     = @{}
            $script:AppsSkip   = @()
            $script:SpinnerSync = [hashtable]::Synchronized(@{
                Active    = $false
                Message   = ""
                StartTime = $null
                Progress  = 0
                Total     = 0
            })

            # Source common library (gives us Write-Log, etc.)
            . $CommonLibPath

            # Redirect job log to a temp file to avoid contention on the main log
            $jobLog = [System.IO.Path]::GetTempFileName()
            $script:LogFile = $jobLog

            # Override spinner functions to no-ops (no console in background jobs)
            function Start-Spinner { param([string]$Message, [int]$Total = 0) }
            function Stop-Spinner { param([string]$FinalMessage = "", [string]$Status = "OK") }
            function Update-SpinnerMessage { param([string]$Message) }
            function Update-SpinnerProgress { param([string]$Message = "") }
            function Set-SpinnerProgress { param([int]$Current, [string]$Message = "") }

            try {
                . $ModulePath
                return @{
                    Success = $true
                    LogFile = $jobLog
                    Error   = ""
                }
            } catch {
                return @{
                    Success = $false
                    LogFile = $jobLog
                    Error   = "$($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
                }
            }
        } -ArgumentList $CommonLib, $modPath, $mod.file, $script:LogFile

        $jobMap[$mod.file] = @{
            Job       = $job
            StartTime = $modStart
            Module    = $mod
        }
    }

    # --- Wait for all jobs and collect results ---
    $allJobs = $jobMap.Values | ForEach-Object { $_.Job }
    if ($allJobs.Count -gt 0) {
        Write-Log "Waiting for $($allJobs.Count) parallel jobs..." "INFO"
        $null = Wait-Job -Job $allJobs -Timeout 3600  # 1-hour max timeout
    }

    foreach ($modFile in $jobMap.Keys) {
        $entry = $jobMap[$modFile]
        $job = $entry.Job
        $modDuration = (Get-Date) - $entry.StartTime

        try {
            $jobResult = Receive-Job -Job $job -ErrorAction Stop

            if ($jobResult.Success) {
                $results += @{
                    name     = $modFile
                    duration = $modDuration
                    status   = "OK"
                    output   = ""
                }
                Write-Log "  [Parallel] $modFile completed ($("{0:N1}s" -f $modDuration.TotalSeconds))" "OK"
            } else {
                $results += @{
                    name     = $modFile
                    duration = $modDuration
                    status   = "FAIL"
                    output   = $jobResult.Error
                }
                Write-Log "  [Parallel] $modFile FAILED: $($jobResult.Error)" "ERROR"
            }

            # Merge job log into main log
            if ($jobResult.LogFile -and (Test-Path $jobResult.LogFile)) {
                $jobLogContent = Get-Content $jobResult.LogFile -Raw -ErrorAction SilentlyContinue
                if ($jobLogContent) {
                    Add-Content -Path $script:LogFile -Value ""
                    Add-Content -Path $script:LogFile -Value "--- [Parallel: $modFile] ---"
                    Add-Content -Path $script:LogFile -Value $jobLogContent
                    Add-Content -Path $script:LogFile -Value "--- [End Parallel: $modFile] ---"
                }
                Remove-Item $jobResult.LogFile -Force -ErrorAction SilentlyContinue
            }
        } catch {
            $results += @{
                name     = $modFile
                duration = $modDuration
                status   = "FAIL"
                output   = $_.Exception.Message
            }
            Write-Log "  [Parallel] $modFile error collecting result: $_" "ERROR"
        }

        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Parallel group '$GroupName' complete: $($results.Count) modules" "INFO"
    return $results
}

# ============================================================================
# Invoke-ModulesWithParallel
# Main entry point: orchestrates sequential + parallel execution
# ============================================================================

function Invoke-ModulesWithParallel {
    param(
        [array]$Modules,          # Full array of module hashtables from init.ps1
        [string]$ScriptRoot,      # $PSScriptRoot from init.ps1
        [string]$CommonLib        # Path to common.ps1
    )

    $failed     = @()
    $skipped    = @()
    $modTimings = @()
    $completedModules = @()

    # --- Phase 1: 01-PackageManagers (must run first, always sequential) ---
    $phase1 = $Modules | Where-Object { $_.file -match "^01-" }
    foreach ($mod in $phase1) {
        $result = Invoke-SequentialModule -Module $mod -Modules $Modules -ScriptRoot $ScriptRoot
        $modTimings += $result.Timing
        if ($result.Timing.status -eq "FAIL") { $failed += $mod.file }
        elseif ($result.Timing.status -eq "SKIP") { $skipped += $mod.file }
        $completedModules += (Get-ModulePrefix $mod.file)
    }

    # Refresh PATH after package managers
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Phase 2: 02-Applications (must run before browsers/VS Code deps, sequential) ---
    $phase2 = $Modules | Where-Object { $_.file -match "^02-" }
    foreach ($mod in $phase2) {
        $result = Invoke-SequentialModule -Module $mod -Modules $Modules -ScriptRoot $ScriptRoot
        $modTimings += $result.Timing
        if ($result.Timing.status -eq "FAIL") { $failed += $mod.file }
        elseif ($result.Timing.status -eq "SKIP") { $skipped += $mod.file }
        $completedModules += (Get-ModulePrefix $mod.file)
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Phase 3: Parallel Group - Registry Tweaks ---
    $regGroup = $script:ParallelGroups | Where-Object { $_.name -eq "Registry Tweaks" } | Select-Object -First 1
    if ($regGroup) {
        $regMods = @()
        foreach ($modName in $regGroup.modules) {
            $match = $Modules | Where-Object { $_.file -match "^$modName" } | Select-Object -First 1
            if ($match) { $regMods += $match }
        }
        if ($regMods.Count -gt 0) {
            Write-Log "--- Parallel Phase: Registry Tweaks ($($regMods.Count) modules) ---" "STEP"
            if ($script:VTEnabled) {
                $c = Get-C
                [Console]::WriteLine("")
                [Console]::WriteLine("  $($c.Bold)$($c.BrMagenta)>> Parallel: Registry Tweaks ($($regMods.Count) modules)$($c.Reset)")
            } else {
                Write-Host ""
                Write-Host "  >> Parallel: Registry Tweaks ($($regMods.Count) modules)" -ForegroundColor Magenta
            }

            $regResults = Invoke-ParallelModules -Modules $regMods -GroupName "Registry Tweaks" -ScriptRoot $ScriptRoot -CommonLib $CommonLib
            foreach ($r in $regResults) {
                $modTimings += $r
                if ($r.status -eq "FAIL") { $failed += $r.name }
                elseif ($r.status -eq "SKIP") { $skipped += $r.name }
                $completedModules += (Get-ModulePrefix $r.name)
            }
        }
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Phase 4: Sequential modules between parallel groups ---
    $betweenMods = @("04-OneDriveRemoval", "06-Debloat", "08-QualityOfLife", "12-SecurityHardening")
    foreach ($modPrefix in $betweenMods) {
        if ($completedModules -contains $modPrefix) { continue }
        $mod = $Modules | Where-Object { $_.file -match "^$modPrefix" } | Select-Object -First 1
        if ($mod) {
            $result = Invoke-SequentialModule -Module $mod -Modules $Modules -ScriptRoot $ScriptRoot
            $modTimings += $result.Timing
            if ($result.Timing.status -eq "FAIL") { $failed += $mod.file }
            elseif ($result.Timing.status -eq "SKIP") { $skipped += $mod.file }
            $completedModules += (Get-ModulePrefix $mod.file)
        }
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Phase 5: Parallel Group - Downloads & Installs ---
    $dlGroup = $script:ParallelGroups | Where-Object { $_.name -eq "Downloads & Installs" } | Select-Object -First 1
    if ($dlGroup) {
        $dlMods = @()
        foreach ($modName in $dlGroup.modules) {
            $match = $Modules | Where-Object { $_.file -match "^$modName" } | Select-Object -First 1
            if ($match -and (Test-DependenciesMet -ModuleName $modName -CompletedModules $completedModules)) {
                $dlMods += $match
            }
        }
        if ($dlMods.Count -gt 0) {
            Write-Log "--- Parallel Phase: Downloads & Installs ($($dlMods.Count) modules) ---" "STEP"
            if ($script:VTEnabled) {
                $c = Get-C
                [Console]::WriteLine("")
                [Console]::WriteLine("  $($c.Bold)$($c.BrMagenta)>> Parallel: Downloads & Installs ($($dlMods.Count) modules)$($c.Reset)")
            } else {
                Write-Host ""
                Write-Host "  >> Parallel: Downloads & Installs ($($dlMods.Count) modules)" -ForegroundColor Magenta
            }

            $dlResults = Invoke-ParallelModules -Modules $dlMods -GroupName "Downloads & Installs" -ScriptRoot $ScriptRoot -CommonLib $CommonLib
            foreach ($r in $dlResults) {
                $modTimings += $r
                if ($r.status -eq "FAIL") { $failed += $r.name }
                elseif ($r.status -eq "SKIP") { $skipped += $r.name }
                $completedModules += (Get-ModulePrefix $r.name)
            }
        }
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # --- Phase 6: Remaining sequential modules (13-BrowserExtensions, 17-VSCodeSetup, 18-FinalConfig) ---
    foreach ($mod in $Modules) {
        $prefix = Get-ModulePrefix $mod.file
        if ($completedModules -contains $prefix) { continue }

        $result = Invoke-SequentialModule -Module $mod -Modules $Modules -ScriptRoot $ScriptRoot
        $modTimings += $result.Timing
        if ($result.Timing.status -eq "FAIL") { $failed += $mod.file }
        elseif ($result.Timing.status -eq "SKIP") { $skipped += $mod.file }
        $completedModules += $prefix

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    return @{
        Failed     = $failed
        Skipped    = $skipped
        ModTimings = $modTimings
    }
}

# ============================================================================
# Invoke-SequentialModule (helper)
# Runs a single module in the current process (same as the default loop)
# ============================================================================

function Invoke-SequentialModule {
    param(
        [hashtable]$Module,
        [array]$Modules,
        [string]$ScriptRoot
    )

    $modPath  = Join-Path $ScriptRoot "modules\$($Module.file)"
    $modStart = Get-Date
    $modIndex = [array]::IndexOf($Modules, $Module) + 1

    if (-not (Test-Path $modPath)) {
        Write-Log "MODULE NOT FOUND: $modPath" "ERROR"
        return @{
            Timing = @{ name = $Module.file; duration = [timespan]::Zero; status = "SKIP" }
        }
    }

    Write-ModuleStart -File "[$modIndex/$($Modules.Count)] $($Module.file)" -Description $Module.desc
    Write-Log "Loading module: $($Module.file)" "INFO"

    # Update dashboard if available
    if ($script:DashboardState -and $script:DashboardState.StartTime) {
        Update-Dashboard -ModuleIndex $modIndex -ModuleName $Module.file -Status "running"
    }

    try {
        . $modPath
        $modDuration = (Get-Date) - $modStart
        Stop-Spinner -FinalMessage "$($Module.file) done ($("{0:N1}s" -f $modDuration.TotalSeconds))" -Status "OK"

        if ($script:DashboardState -and $script:DashboardState.StartTime) {
            Update-Dashboard -ModuleIndex $modIndex -ModuleName $Module.file -Status "completed"
        }

        return @{
            Timing = @{ name = $Module.file; duration = $modDuration; status = "OK" }
        }
    } catch {
        $modDuration = (Get-Date) - $modStart
        Stop-Spinner -FinalMessage "$($Module.file) FAILED" -Status "ERROR"
        $errorMsg = $_.Exception.Message
        $errorLine = $_.InvocationInfo.ScriptLineNumber
        $errorScript = $_.InvocationInfo.ScriptName
        Write-Log "MODULE FAILED: $($Module.file)" "ERROR"
        Write-Log "  Error: $errorMsg" "ERROR"
        Write-Log "  At: $errorScript line $errorLine" "ERROR"
        Write-Log "  Stack: $($_.ScriptStackTrace)" "ERROR"

        if ($script:DashboardState -and $script:DashboardState.StartTime) {
            Update-Dashboard -ModuleIndex $modIndex -ModuleName $Module.file -Status "failed"
        }

        return @{
            Timing = @{ name = $Module.file; duration = $modDuration; status = "FAIL" }
        }
    }
}
