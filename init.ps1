#Requires -RunAsAdministrator
param(
    [string]$ConfigFile = "",
    [string]$Profile = "",
    [string[]]$SkipModules = @(),
    [string[]]$OnlyModules = @(),
    [switch]$DryRun,
    [switch]$Update,
    [switch]$Help,
    [switch]$Resume,  # Resume from last checkpoint (set automatically after reboot)
    [switch]$Parallel # Opt-in: run independent modules concurrently
)
# ============================================================================
# WinInit - Windows Initialization & Customization Script
# Orchestrator - preflight checks, loads shared library, runs all modules
# ============================================================================

$Host.UI.RawUI.WindowTitle = "WinInit - Initializing Windows..."
$ErrorActionPreference = "Continue"

# --- Center window and set full height ---
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinInitWindow {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int h2, bool r);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
    public struct RECT { public int L, T, R, B; }
    public static void CenterFullHeight() {
        IntPtr h = GetConsoleWindow();
        RECT r; GetWindowRect(h, out r);
        int sw = GetSystemMetrics(0);
        int sh = GetSystemMetrics(1);
        int w = r.R - r.L;
        if (w < 960) w = 960;
        int x = (sw - w) / 2;
        int margin = 30;
        MoveWindow(h, x, margin, w, sh - margin * 2 - 40, true);
    }
}
"@ -ErrorAction SilentlyContinue
    [WinInitWindow]::CenterFullHeight()
} catch {}

# --- Set console size + large scrollback buffer ---
try {
    $rawUI = $Host.UI.RawUI
    # Set large scrollback buffer (9999 lines) for full scrollability
    $bufSize = $rawUI.BufferSize
    $bufSize.Width = 120
    $bufSize.Height = 9999
    $rawUI.BufferSize = $bufSize
    # Set window width to match
    $winSize = $rawUI.WindowSize
    $winSize.Width = 120
    $rawUI.WindowSize = $winSize
    # Set console colors
    $rawUI.BackgroundColor = "Black"
    $rawUI.ForegroundColor = "Gray"
    Clear-Host
} catch {}

# --- Record start time ---
$StartTime = Get-Date

# --- Load shared library ---
$commonLib = "$PSScriptRoot\lib\common.ps1"
if (-not (Test-Path $commonLib)) {
    Write-Host "  FATAL: lib\common.ps1 not found at $commonLib" -ForegroundColor Red
    Write-Host "  Ensure the full WinInit package is extracted correctly." -ForegroundColor Red
    pause
    exit 1
}
. $commonLib

# --- Load safety/risk indicator library ---
$safetyLib = "$PSScriptRoot\lib\safety.ps1"
if (-not (Test-Path $safetyLib)) {
    Write-Host "  FATAL: lib\safety.ps1 not found at $safetyLib" -ForegroundColor Red
    Write-Host "  Ensure the full WinInit package is extracted correctly." -ForegroundColor Red
    pause
    exit 1
}
. $safetyLib

# --- Load checkpoint/resume library ---
$checkpointLib = "$PSScriptRoot\lib\checkpoint.ps1"
if (Test-Path $checkpointLib) { . $checkpointLib }

# --- Load rollback library ---
$rollbackLib = "$PSScriptRoot\lib\rollback.ps1"
if (Test-Path $rollbackLib) { . $rollbackLib }

# --- Load community module loader ---
$communityLib = "$PSScriptRoot\lib\community.ps1"
if (Test-Path $communityLib) { . $communityLib }

# --- Load progress dashboard ---
$dashboardLib = "$PSScriptRoot\lib\dashboard.ps1"
if (Test-Path $dashboardLib) { . $dashboardLib }

# --- Load parallel execution library ---
$parallelLib = "$PSScriptRoot\lib\parallel.ps1"
if (Test-Path $parallelLib) { . $parallelLib }

# ============================================================================
# CLI: Help, Config, Profile, Dry-Run, Update
# ============================================================================

# --- Help ---
if ($Help) {
    Show-WinInitHelp
    exit 0
}

# --- Update mode (quick: just upgrade all packages) ---
if ($Update) {
    Write-Host ""
    Write-Host "  WinInit - Update Mode" -ForegroundColor Cyan
    Write-Host "  Running winget upgrade --all ..." -ForegroundColor Gray
    Write-Host ""
    $wingetExe = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetExe) {
        & winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
        Write-Host ""
        Write-Host "  Update complete." -ForegroundColor Green
    } else {
        Write-Host "  ERROR: winget not found. Run full init first." -ForegroundColor Red
    }
    exit 0
}

# --- Load TOML config ---
$configPath = if ($ConfigFile) { $ConfigFile } else { Join-Path $PSScriptRoot "config.toml" }
$tomlConfig = @{}
if (Test-Path $configPath) {
    $tomlConfig = Read-TomlConfig -Path $configPath
    # Don't log yet (log file not initialized), store for later
}

# --- Determine active profile ---
# Priority: CLI -Profile > config.toml [general].profile > "full" (default)
$activeProfile = "full"
if ($tomlConfig.ContainsKey("general") -and $tomlConfig["general"].ContainsKey("profile")) {
    $activeProfile = $tomlConfig["general"]["profile"]
}
if ($Profile) { $activeProfile = $Profile }

# --- Load profile JSON ---
$profilesDir = Join-Path $PSScriptRoot "profiles"
$profileConfig = Read-ProfileConfig -ProfileName $activeProfile -ProfilesDir $profilesDir

# --- Build effective module enable/disable map ---
# Start with all enabled, then layer: profile -> config.toml -> CLI overrides
$moduleEnabled = @{}
$allModuleNames = @(
    "01-PackageManagers", "02-Applications", "03-DesktopEnvironment",
    "04-OneDriveRemoval", "05-Performance", "06-Debloat", "07-Privacy",
    "08-QualityOfLife", "09-Services", "10-NetworkPerformance", "11-VisualUX",
    "12-SecurityHardening", "13-BrowserExtensions", "14-DevTools",
    "15-PortableTools", "16-UnixEnvironment", "17-VSCodeSetup", "18-FinalConfig"
)
foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $true }

# Layer 1: Profile
if ($profileConfig -and $profileConfig.modules) {
    foreach ($prop in $profileConfig.modules.PSObject.Properties) {
        $moduleEnabled[$prop.Name] = [bool]$prop.Value
    }
}

# Layer 2: config.toml [modules] section
if ($tomlConfig.ContainsKey("modules")) {
    foreach ($key in $tomlConfig["modules"].Keys) {
        if ($moduleEnabled.ContainsKey($key)) {
            $moduleEnabled[$key] = [bool]$tomlConfig["modules"][$key]
        }
    }
}

# Layer 3: CLI -SkipModules
foreach ($skip in $SkipModules) {
    # Match by number prefix or full name
    $matched = $allModuleNames | Where-Object { $_ -eq $skip -or $_ -like "$skip-*" }
    foreach ($m in $matched) { $moduleEnabled[$m] = $false }
}

# Layer 4: CLI -OnlyModules (overrides everything - disable all, then enable only listed)
if ($OnlyModules.Count -gt 0) {
    foreach ($m in $allModuleNames) { $moduleEnabled[$m] = $false }
    foreach ($only in $OnlyModules) {
        $matched = $allModuleNames | Where-Object { $_ -eq $only -or $_ -like "$only-*" }
        foreach ($m in $matched) { $moduleEnabled[$m] = $true }
    }
}

# --- Dry-run mode ---
# Priority: CLI -DryRun > config.toml [general].dry_run
if ($DryRun) {
    $script:DryRunMode = $true
} elseif ($tomlConfig.ContainsKey("general") -and $tomlConfig["general"].ContainsKey("dry_run")) {
    $script:DryRunMode = [bool]$tomlConfig["general"]["dry_run"]
}

# --- Apps skip list ---
# Merge profile + config.toml skip lists
$script:AppsSkip = @()
if ($profileConfig -and $profileConfig.apps_skip) {
    $script:AppsSkip += @($profileConfig.apps_skip)
}
if ($tomlConfig.ContainsKey("apps") -and $tomlConfig["apps"].ContainsKey("skip")) {
    $skipVal = $tomlConfig["apps"]["skip"]
    if ($skipVal -and @($skipVal).Count -gt 0) {
        $script:AppsSkip += @($skipVal)
    }
}
$script:AppsSkip = @($script:AppsSkip | Where-Object { $_ } | Select-Object -Unique)

# --- Privacy level ---
$script:PrivacyLevel = "strict"
if ($profileConfig -and $profileConfig.privacy_level) {
    $script:PrivacyLevel = $profileConfig.privacy_level
}
if ($tomlConfig.ContainsKey("privacy") -and $tomlConfig["privacy"].ContainsKey("level")) {
    $script:PrivacyLevel = $tomlConfig["privacy"]["level"]
}

# --- Store full config for modules to reference ---
$script:Config = $tomlConfig

# --- Count enabled modules for TotalSteps ---
$enabledCount = @($moduleEnabled.Values | Where-Object { $_ -eq $true }).Count
$script:TotalSteps = $enabledCount + 2  # preflight + enabled modules + summary

# --- Initialize log file ---
if (Test-Path $script:LogFile) {
    Add-Content -Path $script:LogFile -Value ""
    Add-Content -Path $script:LogFile -Value ("=" * 70)
    Add-Content -Path $script:LogFile -Value "NEW SESSION: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $script:LogFile -Value ("=" * 70)
} else {
    Set-Content -Path $script:LogFile -Value "WinInit Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}

# --- Banner ---
$osInfo = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 0)

$dryTag = if ($script:DryRunMode) { " [DRY RUN]" } else { "" }

Write-Banner -Title "W I N I N I T" `
    -Subtitle "Windows Initialization & Customization Script" `
    -Info @(
        "$enabledCount/$($allModuleNames.Count) Modules | Profile: $activeProfile | Privacy: $($script:PrivacyLevel)$dryTag",
        "User: $env:USERNAME@$env:COMPUTERNAME | RAM: ${ramGB}GB",
        "OS: $osInfo",
        "PS: $($Host.Name) v$($Host.Version) | VT: $($script:VTEnabled)",
        "Log: $($script:LogFile)"
    )

Write-Log "WinInit started" "INFO"
Write-Log "Profile: $activeProfile | Modules: $enabledCount/$($allModuleNames.Count) | Dry-run: $($script:DryRunMode)" "INFO"
Write-Log "Config file: $configPath" "DEBUG"
Write-Log "Privacy level: $($script:PrivacyLevel)" "DEBUG"
if ($script:AppsSkip.Count -gt 0) {
    Write-Log "Apps skip list: $($script:AppsSkip -join ', ')" "DEBUG"
}
$skippedMods = @($moduleEnabled.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object { $_.Key }) -join ", "
if ($skippedMods) { Write-Log "Skipped modules: $skippedMods" "INFO" }
Write-Log "Log file: $($script:LogFile)" "DEBUG"
Write-Log "VT color support: $($script:VTEnabled)" "DEBUG"
Write-Log "PowerShell host: $($Host.Name) v$($Host.Version)" "DEBUG"

# --- Dry-run banner ---
if ($script:DryRunMode) {
    Write-Host ""
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("  $($c.Bold)$($c.BrYellow)*** DRY RUN MODE ***$($c.Reset)")
        [Console]::WriteLine("  $($c.Yellow)No changes will be made to the system. All actions will be simulated.$($c.Reset)")
    } else {
        Write-Host "  *** DRY RUN MODE ***" -ForegroundColor Yellow
        Write-Host "  No changes will be made to the system. All actions will be simulated." -ForegroundColor Yellow
    }
    Write-Host ""
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================
Write-Section "Preflight Checks" "Validating system state before starting"

$preflightPassed = $true
$preflightWarnings = @()
$preflightErrors = @()

# --- 1. Administrator check ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-Log "Running as Administrator" "OK"
    # Verify we're elevated as the actual user (not SYSTEM or a different account)
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Log "Elevated identity: $currentUser" "INFO"
    if ($currentUser -match "SYSTEM|DefaultAccount") {
        Write-Log "Running as SYSTEM - user-scoped settings will NOT apply correctly!" "ERROR"
        $preflightErrors += "Running as SYSTEM instead of user"
        $preflightPassed = $false
    }
    # Verify HKCU points to the right user
    $hkcuUser = (Get-ItemProperty "HKCU:\Volatile Environment" -Name "USERNAME" -ErrorAction SilentlyContinue).USERNAME
    if ($hkcuUser) {
        Write-Log "HKCU registry user: $hkcuUser" "OK"
    }
    Write-Log "USERPROFILE: $env:USERPROFILE" "INFO"
} else {
    Write-Log "NOT running as Administrator - many operations will fail" "ERROR"
    $preflightErrors += "Not running as Administrator"
    $preflightPassed = $false
}

# --- 2. OS Version check ---
$os = Get-CimInstance Win32_OperatingSystem
$osBuild = [int]$os.BuildNumber
$osCaption = $os.Caption
Write-Log "OS: $osCaption (Build $osBuild)"
if ($osBuild -lt 19041) {
    Write-Log "Windows build $osBuild is too old - requires 19041+ (Win 10 2004 or later)" "ERROR"
    $preflightErrors += "Windows build too old ($osBuild)"
    $preflightPassed = $false
} elseif ($osBuild -lt 22000) {
    Write-Log "Windows 10 detected - some Win 11 features will be skipped" "WARN"
    $preflightWarnings += "Windows 10 (some Win 11 features unavailable)"
} else {
    Write-Log "Windows 11 detected (Build $osBuild)" "OK"
}

# --- 3. Architecture check ---
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq "AMD64") {
    Write-Log "Architecture: x64 (AMD64)" "OK"
} else {
    Write-Log "Architecture: $arch - script is designed for x64" "WARN"
    $preflightWarnings += "Non-x64 architecture: $arch"
}

# --- 4. Internet connectivity + DNS ---
Write-Log "Testing internet connectivity..."
$connectivity = $false

# Method 1: HTTP request (most reliable - works even if ICMP is blocked)
$testUrls = @("https://www.google.com", "https://github.com", "https://microsoft.com")
foreach ($url in $testUrls) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop -Method Head
        if ($response.StatusCode -lt 400) {
            $connectivity = $true
            Write-Log "Internet connectivity: OK (via $url)" "OK"
            break
        }
    } catch {}
}

# Method 2: Fallback to .NET WebClient (lighter weight)
if (-not $connectivity) {
    try {
        $wc = New-Object System.Net.WebClient
        $null = $wc.DownloadString("http://www.msftconnecttest.com/connecttest.txt")
        $connectivity = $true
        Write-Log "Internet connectivity: OK (via msftconnecttest)" "OK"
    } catch {}
}

# Method 3: Fallback to DNS resolution
if (-not $connectivity) {
    try {
        $dns = [System.Net.Dns]::GetHostAddresses("github.com")
        if ($dns.Count -gt 0) {
            $connectivity = $true
            Write-Log "Internet connectivity: OK (DNS resolves, HTTP may be filtered)" "WARN"
        }
    } catch {}
}

# Method 4: Last resort - ping
if (-not $connectivity) {
    try {
        $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ping) {
            $connectivity = $true
            Write-Log "Internet connectivity: OK (via ping)" "OK"
        }
    } catch {}
}

if (-not $connectivity) {
    Write-Log "No internet connectivity detected - package installs may fail" "WARN"
    $preflightWarnings += "Internet connectivity check failed (may be a false negative)"
    # Downgrade to warning instead of error - some corporate networks block all test methods
    # but winget/choco still work through proxy
}

# --- 6. Disk space check ---
$systemDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
if ($systemDrive) {
    $freeGB = [math]::Round($systemDrive.Free / 1GB, 1)
    if ($freeGB -lt 10) {
        Write-Log "System drive has only ${freeGB}GB free - need at least 10GB" "ERROR"
        $preflightErrors += "Insufficient disk space (${freeGB}GB free)"
        $preflightPassed = $false
    } elseif ($freeGB -lt 30) {
        Write-Log "System drive has ${freeGB}GB free - recommend 30GB+" "WARN"
        $preflightWarnings += "Low disk space (${freeGB}GB)"
    } else {
        Write-Log "System drive: ${freeGB}GB free" "OK"
    }
}

# --- 7. RAM check ---
$totalRAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
if ($totalRAM -lt 4) {
    Write-Log "Only ${totalRAM}GB RAM - minimum 4GB required" "ERROR"
    $preflightErrors += "Insufficient RAM (${totalRAM}GB)"
    $preflightPassed = $false
} elseif ($totalRAM -lt 8) {
    Write-Log "${totalRAM}GB RAM detected -8GB+ recommended" "WARN"
    $preflightWarnings += "Low RAM (${totalRAM}GB)"
} else {
    Write-Log "RAM: ${totalRAM}GB" "OK"
}

# --- 8. PowerShell version ---
$psVer = $PSVersionTable.PSVersion
Write-Log "PowerShell: $psVer"
if ($psVer.Major -lt 5) {
    Write-Log "PowerShell $psVer is too old - requires 5.1+" "ERROR"
    $preflightErrors += "PowerShell too old ($psVer)"
    $preflightPassed = $false
} else {
    Write-Log "PowerShell version: OK" "OK"
}

# --- 9. TLS 1.2 enabled ---
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    Write-Log "TLS 1.2 enabled" "OK"
} catch {
    Write-Log "Failed to enable TLS 1.2 - downloads may fail" "ERROR"
    $preflightErrors += "TLS 1.2 not available"
    $preflightPassed = $false
}

# --- 10. Module files exist ---
$modulesDir = Join-Path $PSScriptRoot "modules"
$expectedModules = 18
$foundModules = (Get-ChildItem "$modulesDir\*.ps1" -ErrorAction SilentlyContinue).Count
if ($foundModules -eq $expectedModules) {
    Write-Log "All $expectedModules module files present" "OK"
} elseif ($foundModules -gt 0) {
    Write-Log "Found $foundModules of $expectedModules modules - some may be missing" "WARN"
    $preflightWarnings += "Only $foundModules/$expectedModules modules found"
} else {
    Write-Log "No module files found in $modulesDir" "ERROR"
    $preflightErrors += "No modules found"
    $preflightPassed = $false
}

# --- 11. Execution policy ---
$execPolicy = Get-ExecutionPolicy -Scope Process
if ($execPolicy -in @("Unrestricted", "Bypass", "RemoteSigned")) {
    Write-Log "Execution policy: $execPolicy" "OK"
} else {
    Write-Log "Execution policy is $execPolicy - setting to Bypass for this session" "WARN"
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
    $preflightWarnings += "Execution policy changed from $execPolicy to Bypass"
}

# --- 12. No pending reboots ---
$pendingReboot = $false
$rebootKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
)
foreach ($rk in $rebootKeys) {
    if (Test-Path $rk) { $pendingReboot = $true; break }
}
# PendingFileRenameOperations is a registry value, not a key - Test-Path doesn't work on values
if (-not $pendingReboot) {
    $pfrOps = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($pfrOps) { $pendingReboot = $true }
}
if ($pendingReboot) {
    Write-Log "Pending reboot detected - some operations may fail or require re-run" "WARN"
    $preflightWarnings += "Pending reboot detected"
} else {
    Write-Log "No pending reboots" "OK"
}

# --- 13. Check for running AV that might interfere ---
$avProcesses = @("MsMpEng", "avp", "avgnt", "avguard", "bdagent")
$runningAV = Get-Process -Name $avProcesses -ErrorAction SilentlyContinue
if ($runningAV) {
    $avNames = ($runningAV | Select-Object -ExpandProperty Name -Unique) -join ", "
    Write-Log "Active antivirus detected: $avNames - may slow installs" "WARN"
    $preflightWarnings += "AV active: $avNames"
} else {
    Write-Log "No interfering AV detected" "OK"
}

# --- 14. Check if running from a network path ---
if ($PSScriptRoot -match "^\\\\") {
    Write-Log "Running from network path - copy to local drive for best results" "WARN"
    $preflightWarnings += "Running from network path"
} else {
    Write-Log "Running from local path: $PSScriptRoot" "OK"
}

# --- 15. System info summary ---
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$gpu = (Get-CimInstance Win32_VideoController | Select-Object -First 1).Name
Write-Log "CPU: $cpu"
Write-Log "GPU: $gpu"
Write-Log "User: $env:USERNAME on $env:COMPUTERNAME"
Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# --- Preflight Summary ---
Write-Host ""
if ($preflightPassed) {
    if ($preflightWarnings.Count -gt 0) {
        if ($script:VTEnabled) {
            $c = Get-C
            [Console]::WriteLine("  $($c.Bold)$($c.BrYellow)Preflight: PASSED$($c.Reset) $($c.BrYellow)with $($preflightWarnings.Count) warning(s)$($c.Reset)")
            foreach ($w in $preflightWarnings) {
                [Console]::WriteLine("    $($c.Yellow)[!] $w$($c.Reset)")
            }
        } else {
            Write-Host "  Preflight: PASSED with $($preflightWarnings.Count) warning(s)" -ForegroundColor Yellow
            foreach ($w in $preflightWarnings) {
                Write-Host "    [!] $w" -ForegroundColor Yellow
            }
        }
        Write-Log "Preflight passed with $($preflightWarnings.Count) warning(s)" "WARN"
        foreach ($w in $preflightWarnings) { Write-Log "  Warning: $w" "WARN" }
    } else {
        if ($script:VTEnabled) {
            [Console]::WriteLine("  $($script:C.Bold)$($script:C.BrGreen)Preflight: ALL CHECKS PASSED$($script:C.Reset)")
        } else {
            Write-Host "  Preflight: ALL CHECKS PASSED" -ForegroundColor Green
        }
        Write-Log "Preflight: all checks passed" "OK"
    }
    Write-Host ""
} else {
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("  $($c.Bold)$($c.BgRed)$($c.BrWhite) Preflight: FAILED - $($preflightErrors.Count) critical error(s) $($c.Reset)")
        foreach ($e in $preflightErrors) {
            [Console]::WriteLine("    $($c.BrRed)[-] $e$($c.Reset)")
        }
        foreach ($w in $preflightWarnings) {
            [Console]::WriteLine("    $($c.Yellow)[!] $w$($c.Reset)")
        }
    } else {
        Write-Host "  Preflight: FAILED - $($preflightErrors.Count) critical error(s)" -ForegroundColor Red
        foreach ($e in $preflightErrors) {
            Write-Host "    [-] $e" -ForegroundColor Red
        }
        foreach ($w in $preflightWarnings) {
            Write-Host "    [!] $w" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Log "Preflight FAILED - aborting" "FATAL"
    foreach ($e in $preflightErrors) { Write-Log "  Error: $e" "ERROR" }
    foreach ($w in $preflightWarnings) { Write-Log "  Warning: $w" "WARN" }
    if ($script:VTEnabled) {
        [Console]::WriteLine("  $($script:C.BrRed)Fix the errors above and re-run. Press any key to exit.$($script:C.Reset)")
    } else {
        Write-Host "  Fix the errors above and re-run. Press any key to exit." -ForegroundColor Red
    }
    pause
    exit 1
}

# --- Create a restore point BEFORE making any changes ---
if (-not $script:DryRunMode) {
    Write-Log "Creating pre-WinInit restore point..." "INFO"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        # Allow frequent restore points (default is 1 per 24h)
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
            -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinInit Pre-Install" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
        Write-Log "Restore point 'WinInit Pre-Install' created" "OK"
    } catch {
        Write-Log "Could not create restore point: $_ (continuing anyway)" "WARN"
    }
} else {
    Write-Log "[DRY RUN] Would create restore point 'WinInit Pre-Install'" "INFO"
}

# --- Disable Windows Defender real-time monitoring during install ---
# Dramatically speeds up installs, extractions, and compilations
if (-not $script:DryRunMode) {
    Write-Log "Temporarily disabling Defender real-time monitoring for faster installs..." "INFO"
    try {
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        Write-Log "Defender real-time monitoring disabled (will re-enable at end)" "OK"
    } catch {
        Write-Log "Could not disable Defender real-time monitoring: $_ (installs may be slower)" "WARN"
    }
} else {
    Write-Log "[DRY RUN] Would disable Defender real-time monitoring" "INFO"
}

# --- Force show file extensions and hidden files IMMEDIATELY ---
if (-not $script:DryRunMode) {
    Write-Log "Configuring Explorer: show file extensions and hidden files" "INFO"
    $explorerReg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $explorerReg -Name "HideFileExt"     -Value 0 -Type DWord
    Set-ItemProperty -Path $explorerReg -Name "Hidden"           -Value 1 -Type DWord
    Set-ItemProperty -Path $explorerReg -Name "ShowSuperHidden"  -Value 1 -Type DWord
    Write-Log "Explorer: HideFileExt=0, Hidden=1, ShowSuperHidden=1" "DEBUG"
    Write-Log "File extensions and hidden files now visible" "OK"
} else {
    Write-Log "[DRY RUN] Would configure Explorer: show file extensions and hidden files" "INFO"
    $script:DryRunStats.Registry += 3
}

# --- Ensure TLS 1.2 for all downloads ---
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
Write-Log "TLS protocol set to TLS 1.2 + 1.3" "DEBUG"

# --- Create required directories upfront ---
if (-not $script:DryRunMode) {
    Write-Log "Creating required directories..." "INFO"
    $requiredDirs = @("C:\bin", "C:\apps", "C:\venv", "C:\vcpkg")
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir" "OK"
        } else {
            Write-Log "Directory exists: $dir" "DEBUG"
        }
    }
} else {
    Write-Log "[DRY RUN] Would create directories: C:\bin, C:\apps, C:\venv, C:\vcpkg" "INFO"
}

# ============================================================================
# Graceful Ctrl+C / Interruption Handler
# ============================================================================

$script:Interrupted = $false
$script:LastCompletedModuleIdx = -1

[Console]::TreatControlCAsInput = $false

# Register Ctrl+C handler via .NET event
try {
    [Console]::CancelKeyPress.Add({
        param($sender, $e)
        $e.Cancel = $true  # Don't kill the process immediately
        $script:Interrupted = $true
        Write-Host ""
        Write-Host "  [!] Ctrl+C detected - finishing current operation..." -ForegroundColor Yellow
        Write-Host "  [!] State will be saved. Run again with -Resume to continue." -ForegroundColor Yellow
    })
} catch {
    Write-Log "Could not register Ctrl+C handler: $_" "WARN"
}

# Register PowerShell.Exiting event as backup
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:Interrupted = $true
} -ErrorAction SilentlyContinue

# ============================================================================
# Initialize Rollback System
# ============================================================================

Initialize-Rollback

# ============================================================================
# Check for Resume from Checkpoint
# ============================================================================

$resumeFromIndex = 0
$isResuming = $false
if ($Resume -or (Test-Path $script:CheckpointFile)) {
    $checkpoint = Get-Checkpoint
    if ($checkpoint -and $checkpoint.status -in @("paused", "rebooting", "in_progress")) {
        $resumeFromIndex = $checkpoint.last_completed_module + 1
        $isResuming = $true
        Write-Log "Resuming from checkpoint: module index $resumeFromIndex ($($checkpoint.last_module_file) was last completed)" "INFO"
        Write-Host ""
        Write-Host "  Resuming from previous run..." -ForegroundColor Cyan
        Write-Host "  (Last completed: $($checkpoint.last_module_file))" -ForegroundColor Gray
        Write-Host ""

        # Remove RunOnce key if we were called from a reboot resume
        if ($Resume) {
            Unregister-RebootResume
        }
    } elseif ($checkpoint -and $checkpoint.status -eq "completed") {
        Write-Log "Previous run completed successfully - starting fresh" "INFO"
        Remove-Checkpoint
    }
}

# ============================================================================
# Module Execution
# ============================================================================

$modules = @(
    @{ file = "01-PackageManagers.ps1";    desc = "Installing package managers (winget, scoop, choco)" },
    @{ file = "02-Applications.ps1";       desc = "Installing applications (50+ apps)" },
    @{ file = "03-DesktopEnvironment.ps1"; desc = "Customizing desktop (dark mode, taskbar, telemetry)" },
    @{ file = "04-OneDriveRemoval.ps1";    desc = "Removing OneDrive completely" },
    @{ file = "05-Performance.ps1";        desc = "Performance optimizations (SysMain, Game Bar, etc.)" },
    @{ file = "06-Debloat.ps1";            desc = "Removing UWP bloatware (70+ packages)" },
    @{ file = "07-Privacy.ps1";            desc = "Privacy settings (Wi-Fi Sense, clipboard, SmartScreen)" },
    @{ file = "08-QualityOfLife.ps1";      desc = "Quality of life (NumLock, sticky keys, locale, terminal)" },
    @{ file = "09-Services.ps1";           desc = "Disabling junk services (30+ services)" },
    @{ file = "10-NetworkPerformance.ps1"; desc = "Network & memory tuning (Nagle, SSD, IRPStack)" },
    @{ file = "11-VisualUX.ps1";           desc = "Visual tweaks (transparency, Start menu, icons)" },
    @{ file = "12-SecurityHardening.ps1";  desc = "Security & features (SMBv1, Hyper-V, UTF-8, Sandbox)" },
    @{ file = "13-BrowserExtensions.ps1";  desc = "Browser extensions (Firefox, Chrome, Edge)" },
    @{ file = "14-DevTools.ps1";           desc = "Dev tools (Node, Rust, Go, CUDA, SQL, gRPC, K8s)" },
    @{ file = "15-PortableTools.ps1";      desc = "Portable tools (C:\bin + C:\apps)" },
    @{ file = "16-UnixEnvironment.ps1";    desc = "Unix environment (Cygwin, Perl, Python venv, Go)" },
    @{ file = "17-VSCodeSetup.ps1";        desc = "VS Code, fonts, terminal theme, Oh My Posh" },
    @{ file = "18-FinalConfig.ps1";        desc = "Updates, cleanup, System Restore, startup config" }
)

$failed  = @()
$skipped = @()
$modTimings = @()
$runIndex = 0    # tracks position among enabled modules for display

# --- Initialize progress dashboard ---
if (Get-Command Initialize-Dashboard -ErrorAction SilentlyContinue) {
    Initialize-Dashboard -TotalModules $modules.Count
    Write-Log "Progress dashboard initialized" "DEBUG"
}

if ($isResuming -and $resumeFromIndex -gt 0) {
    Write-Host "  Skipping modules 1-$resumeFromIndex (already completed)" -ForegroundColor Gray
    Write-Host ""
}

# --- Parallel mode (opt-in, disabled during resume) ---
if ($Parallel -and -not $isResuming -and (Get-Command Invoke-ModulesWithParallel -ErrorAction SilentlyContinue)) {
    Write-Log "PARALLEL MODE enabled - independent modules will run concurrently" "WARN"
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("  $($c.Bold)$($c.BrMagenta)Parallel mode: ON$($c.Reset) $($c.Gray)- independent modules run concurrently$($c.Reset)")
    } else {
        Write-Host "  Parallel mode: ON - independent modules run concurrently" -ForegroundColor Magenta
    }

    $parallelResult = Invoke-ModulesWithParallel -Modules $modules -ScriptRoot $PSScriptRoot -CommonLib $commonLib
    $failed     = $parallelResult.Failed
    $skipped    = $parallelResult.Skipped
    $modTimings = $parallelResult.ModTimings
} else {
    # --- Default: sequential execution ---
    if ($Parallel -and $isResuming) {
        Write-Log "Parallel mode disabled during resume - running sequentially" "WARN"
    } elseif ($Parallel) {
        Write-Log "Parallel mode requested but lib/parallel.ps1 not loaded - falling back to sequential" "WARN"
    }

    for ($i = 0; $i -lt $modules.Count; $i++) {
        $mod = $modules[$i]
        $modIndex = $i + 1

        # --- Filter: skip disabled modules based on config/profile/CLI ---
        $modName = $mod.file -replace '\.ps1$', ''
        if ($moduleEnabled.ContainsKey($modName) -and -not $moduleEnabled[$modName]) {
            Write-Log "Skipping module (disabled): $($mod.file)" "INFO"
            $skipped += $mod.file
            $modTimings += @{ name = $mod.file; duration = [timespan]::Zero; status = "SKIP" }
            if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "skipped"
            }
            continue
        }

        # --- Resume: skip modules already completed in a previous run ---
        if ($i -lt $resumeFromIndex) {
            Write-Log "Skipping module (already completed): $($mod.file)" "DEBUG"
            $skipped += $mod.file
            $modTimings += @{ name = $mod.file; duration = [timespan]::Zero; status = "SKIP" }
            if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "skipped"
            }
            continue
        }

        $runIndex++
        $modPath = Join-Path $PSScriptRoot "modules\$($mod.file)"
        $modStart = Get-Date

        if (Test-Path $modPath) {
            # --- Dashboard: show status before module starts ---
            if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "running"
            }

            Write-ModuleStart -File "[$runIndex/$enabledCount] $($mod.file)" -Description $mod.desc
            Write-Log "Loading module: $($mod.file)" "INFO"

            try {
                . $modPath
                # Stop the section spinner (started by Write-Section inside the module)
                $modDuration = (Get-Date) - $modStart
                Stop-Spinner -FinalMessage "$($mod.file) done ($("{0:N1}s" -f $modDuration.TotalSeconds))" -Status "OK"
                $modTimings += @{ name = $mod.file; duration = $modDuration; status = "OK" }

                # --- Dashboard: mark completed ---
                if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                    Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "completed"
                }
            } catch {
                $modDuration = (Get-Date) - $modStart
                Stop-Spinner -FinalMessage "$($mod.file) FAILED" -Status "ERROR"
                $errorMsg = $_.Exception.Message
                $errorLine = $_.InvocationInfo.ScriptLineNumber
                $errorScript = $_.InvocationInfo.ScriptName
                Write-Log "MODULE FAILED: $($mod.file)" "ERROR"
                Write-Log "  Error: $errorMsg" "ERROR"
                Write-Log "  At: $errorScript line $errorLine" "ERROR"
                Write-Log "  Stack: $($_.ScriptStackTrace)" "ERROR"
                $failed += $mod.file
                $modTimings += @{ name = $mod.file; duration = $modDuration; status = "FAIL" }

                # --- Dashboard: mark failed ---
                if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                    Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "failed"
                }
            }
        } else {
            Write-Log "MODULE NOT FOUND: $modPath" "ERROR"
            $skipped += $mod.file
            $modTimings += @{ name = $mod.file; duration = [timespan]::Zero; status = "SKIP" }
            if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) {
                Update-Dashboard -ModuleIndex $modIndex -ModuleName $mod.file -Status "skipped"
            }
        }

        # Save checkpoint and rollback data after each module
        $script:LastCompletedModuleIdx = $i
        Save-Checkpoint -LastCompletedModule $i -LastModuleFile $mod.file -Status "in_progress"
        Save-Rollback

        # Check for Ctrl+C interruption
        if ($script:Interrupted) {
            Save-Checkpoint -LastCompletedModule $i -LastModuleFile $mod.file -Status "paused"
            Save-Rollback
            Write-Log "Execution paused by user after module $($mod.file)" "WARN"
            Write-Host ""
            Write-Host "  Execution paused. Run init.ps1 -Resume to continue from module $($i + 2)." -ForegroundColor Yellow
            break
        }

        # Refresh PATH after each module (some modules install tools that later modules need)
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
}

# ============================================================================
# Community Modules
# ============================================================================

if (Get-Command Invoke-CommunityModules -ErrorAction SilentlyContinue) {
    $communityResults = Invoke-CommunityModules
    if ($communityResults -and $communityResults.Count -gt 0) {
        foreach ($cr in $communityResults) {
            $modTimings += @{ name = $cr.name; duration = $cr.duration; status = $cr.status }
            if ($cr.status -eq "FAIL") { $failed += $cr.name }
            if ($cr.status -eq "BLOCKED") { $skipped += $cr.name }
        }
    }
}

# ============================================================================
# Finalize Checkpoint & Rollback
# ============================================================================
if (-not $script:Interrupted) {
    # All modules completed - mark checkpoint as done and clean up
    Save-Checkpoint -LastCompletedModule ($modules.Count - 1) -LastModuleFile $modules[-1].file -Status "completed"
    Save-Rollback
    Remove-Checkpoint
    Unregister-RebootResume
    Write-Log "All modules completed - checkpoint cleared" "DEBUG"
} else {
    # Interrupted - final rollback save (checkpoint already saved in loop)
    Save-Rollback
}

# ============================================================================
# Re-enable Windows Defender real-time monitoring
# ============================================================================
if (-not $script:DryRunMode) {
    Write-Log "Re-enabling Defender real-time monitoring..." "INFO"
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-Log "Defender real-time monitoring re-enabled" "OK"
    } catch {
        Write-Log "Could not re-enable Defender: $_ (may need manual re-enable)" "WARN"
    }
}

# ============================================================================
# Final Summary
# ============================================================================

$EndTime  = Get-Date
$Duration = $EndTime - $StartTime
$durationStr = "{0:hh\:mm\:ss}" -f $Duration
$succeeded = $modules.Count - $failed.Count - $skipped.Count

Write-Blank 2

# Module timing report
Write-TimingReport $modTimings

# Dashboard summary (weighted progress view)
if (Get-Command Write-DashboardSummary -ErrorAction SilentlyContinue) {
    Write-DashboardSummary
}

Write-Blank

# Stats line
Write-Rule -Char "=" -Width 70 -Color "Cyan"
Write-Blank
Write-StatsLine @{
    Duration  = $durationStr
    Profile   = $activeProfile
    Modules   = "$enabledCount/$($modules.Count)"
    Succeeded = "$succeeded"
    Failed    = "$($failed.Count)"
    Skipped   = "$($skipped.Count)"
}
Write-Blank

# Dry-run summary (shows what WOULD have happened)
if ($script:DryRunMode) {
    Write-DryRunSummary
}

# Get updated disk space
$freeGBNow = [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue).Free / 1GB, 1)

$modeLabel = if ($script:DryRunMode) { "DRY RUN" } else { "Complete" }
$summaryLines = @(
    "Duration:    $durationStr",
    "Profile:     $activeProfile",
    "Modules:     $enabledCount of $($modules.Count) enabled",
    "Succeeded:   $succeeded",
    "Failed:      $($failed.Count)",
    "Skipped:     $($skipped.Count)",
    "",
    "Disk Free:   ${freeGBNow}GB (was ${freeGB}GB before)",
    "Log file:    $($script:LogFile)",
    "",
    "REBOOT REQUIRED for:",
    "  Hyper-V, UTF-8, locale, WSL, SMBv1, SSD, Sandbox, CUDA"
)

if ($failed.Count -gt 0) {
    $summaryLines += ""
    $summaryLines += "Failed modules:"
    foreach ($f in $failed) { $summaryLines += "  ! $f" }
}

Write-SummaryBox "WinInit $modeLabel!" $summaryLines

Write-Log "WinInit finished in $durationStr" "INFO"
Write-Log "Profile: $activeProfile | Succeeded: $succeeded | Failed: $($failed.Count) | Skipped: $($skipped.Count)" "INFO"
Write-Log "Log saved to: $($script:LogFile)" "INFO"
if ($failed.Count -gt 0) {
    foreach ($f in $failed) { Write-Log "FAILED module: $f" "ERROR" }
}

# Scroll to bottom hint
Write-Blank
if ($script:VTEnabled) {
    $c = Get-C
    [Console]::WriteLine("  $($c.Gray)Scroll up to review all output | Full log: $($script:LogFile)$($c.Reset)")
} else {
    Write-Host "  Scroll up to review all output | Full log: $($script:LogFile)" -ForegroundColor Gray
}
Write-Blank

# Completion sound
Write-CompletionSound -Error:($failed.Count -gt 0)
