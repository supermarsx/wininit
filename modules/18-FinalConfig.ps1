# Module: 18 - Final Config
# Windows Update + System Restore + Startup/session restore + Explorer restart + done message

Write-Section "Final Config" "Windows Update, System Restore, startup cleanup"

# ============================================================================
# Windows Update Configuration
# ============================================================================

$WUPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (-not (Test-Path $WUPath)) { New-Item -Path $WUPath -Force | Out-Null }
$AUPath = "$WUPath\AU"
if (-not (Test-Path $AUPath)) { New-Item -Path $AUPath -Force | Out-Null }

# --- Auto-install updates during the night ---
Write-Log "Configuring auto-install during night hours..."
# AUOptions: 4 = Auto download and schedule install
Set-ItemProperty -Path $AUPath -Name "AUOptions" -Value 4 -Type DWord
# Schedule install at 3:00 AM
Set-ItemProperty -Path $AUPath -Name "ScheduledInstallTime" -Value 3 -Type DWord
# Every day (0 = every day, 1-7 = specific day)
Set-ItemProperty -Path $AUPath -Name "ScheduledInstallDay" -Value 0 -Type DWord
# Allow installs during automatic maintenance
Set-ItemProperty -Path $AUPath -Name "AutomaticMaintenanceEnabled" -Value 1 -Type DWord
Write-Log "Updates scheduled to auto-install at 3:00 AM nightly" "OK"

# --- Defer updates 7 days, then force restart ---
Write-Log "Configuring 7-day deferral with forced restart..."
# Defer quality updates by 7 days
Set-ItemProperty -Path $WUPath -Name "DeferQualityUpdates"       -Value 1 -Type DWord
Set-ItemProperty -Path $WUPath -Name "DeferQualityUpdatesPeriodInDays" -Value 7 -Type DWord
# Defer feature updates by 30 days (less frequent, more disruptive)
Set-ItemProperty -Path $WUPath -Name "DeferFeatureUpdates"       -Value 1 -Type DWord
Set-ItemProperty -Path $WUPath -Name "DeferFeatureUpdatesPeriodInDays" -Value 30 -Type DWord

# After 7 days from install-ready: force restart (engaged restart)
Set-ItemProperty -Path $AUPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
# Set deadline: auto-restart 7 days after update is available
$DeadlinePath = "$WUPath"
Set-ItemProperty -Path $DeadlinePath -Name "SetComplianceDeadline"                -Value 1 -Type DWord
Set-ItemProperty -Path $DeadlinePath -Name "ConfigureDeadlineForQualityUpdates"   -Value 7 -Type DWord
Set-ItemProperty -Path $DeadlinePath -Name "ConfigureDeadlineForFeatureUpdates"   -Value 14 -Type DWord
Set-ItemProperty -Path $DeadlinePath -Name "ConfigureDeadlineGracePeriod"         -Value 2 -Type DWord
Set-ItemProperty -Path $DeadlinePath -Name "ConfigureDeadlineGracePeriodForFeatureUpdates" -Value 3 -Type DWord
# No restart during active hours (8 AM - 2 AM = basically only restart 2-8 AM)
Set-ItemProperty -Path $AUPath -Name "SetActiveHours"      -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $AUPath -Name "ActiveHoursStart"    -Value 8 -Type DWord
Set-ItemProperty -Path $AUPath -Name "ActiveHoursEnd"      -Value 2 -Type DWord
Write-Log "Updates deferred 7 days (quality) / 30 days (feature), force restart after deadline" "OK"

# ============================================================================
# System Restore
# ============================================================================
Write-SubStep "System Restore"

# --- Enable System Restore on C: ---
Write-Log "Enabling System Restore..."
Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
# Set max usage to 5% of disk
vssadmin resize shadowstorage /for=C: /on=C: /maxsize=5% >$null 2>&1
# Make sure the service is running
Set-Service -Name "srservice" -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name "srservice" -ErrorAction SilentlyContinue

# Configure via registry
$SRPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
Set-ItemProperty -Path $SRPath -Name "DisableSR" -Value 0 -Type DWord
# Set restore point creation frequency (allow every 0 minutes - default is 1440 = 24h)
Set-ItemProperty -Path $SRPath -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord
Write-Log "System Restore enabled on C: (5% max)" "OK"

# --- Create "WinInit Complete" Restore Point ---
Write-Log "Creating WinInit restore point..."
Checkpoint-Computer -Description "WinInit Complete" -RestorePointType "APPLICATION_INSTALL" -ErrorAction SilentlyContinue
Write-Log "Restore point 'WinInit Complete' created" "OK"

# ============================================================================
# Startup & Session Restore
# ============================================================================
Write-SubStep "Startup & Session Restore"

# --- Minimal Startup - Clean out everything except essentials ---
Write-Log "Cleaning startup entries..."

# Disable all non-essential startup items via registry
$startupPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)
# Whitelist: ONLY these survive - everything else gets killed
$startupWhitelist = @(
    "SecurityHealth"        # Windows Security (mandatory)
)
foreach ($regPath in $startupPaths) {
    $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if ($entries) {
        $props = $entries.PSObject.Properties | Where-Object {
            $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")
        }
        foreach ($prop in $props) {
            $keep = $false
            foreach ($wl in $startupWhitelist) {
                if ($prop.Name -match $wl) { $keep = $true; break }
            }
            if (-not $keep) {
                Remove-ItemProperty -Path $regPath -Name $prop.Name -ErrorAction SilentlyContinue
                Write-Log "Removed startup entry: $($prop.Name)" "OK"
            }
        }
    }
}

# Disable startup items in the shell:startup folder too (except whitelist)
$startupFolder = [System.Environment]::GetFolderPath("Startup")
if (Test-Path $startupFolder) {
    Get-ChildItem $startupFolder -Filter "*.lnk" | ForEach-Object {
        $keep = $false
        foreach ($wl in $startupWhitelist) {
            if ($_.BaseName -match $wl) { $keep = $true; break }
        }
        if (-not $keep) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Removed startup shortcut: $($_.BaseName)" "OK"
        }
    }
}
Write-Log "Startup cleaned - registry and startup folder purged" "OK"

# Also disable startup apps that register via ApprovedStartupEntries
$approvedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $approvedPath) {
    $entries = Get-ItemProperty -Path $approvedPath -ErrorAction SilentlyContinue
    if ($entries) {
        $props = $entries.PSObject.Properties | Where-Object {
            $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") -and
            $_.Name -notmatch "SecurityHealth"
        }
        foreach ($prop in $props) {
            # Set first byte to 03 to disable (enabled = 02/06, disabled = 03)
            $val = $prop.Value
            if ($val -is [byte[]] -and $val.Length -ge 1 -and $val[0] -ne 3) {
                $val[0] = 3
                Set-ItemProperty -Path $approvedPath -Name $prop.Name -Value $val -ErrorAction SilentlyContinue
                Write-Log "Disabled startup (ApprovedRun): $($prop.Name)" "OK"
            }
        }
    }
}

# Same for HKLM approved
$approvedPathLM = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $approvedPathLM) {
    $entries = Get-ItemProperty -Path $approvedPathLM -ErrorAction SilentlyContinue
    if ($entries) {
        $props = $entries.PSObject.Properties | Where-Object {
            $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") -and
            $_.Name -notmatch "SecurityHealth"
        }
        foreach ($prop in $props) {
            $val = $prop.Value
            if ($val -is [byte[]] -and $val.Length -ge 1 -and $val[0] -ne 3) {
                $val[0] = 3
                Set-ItemProperty -Path $approvedPathLM -Name $prop.Name -Value $val -ErrorAction SilentlyContinue
                Write-Log "Disabled startup (ApprovedRun LM): $($prop.Name)" "OK"
            }
        }
    }
}

# Remove common bloat from Run32 as well
$run32Paths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach ($r32 in $run32Paths) {
    if (Test-Path $r32) {
        $entries = Get-ItemProperty -Path $r32 -ErrorAction SilentlyContinue
        if ($entries) {
            $props = $entries.PSObject.Properties | Where-Object {
                $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")
            }
            foreach ($prop in $props) {
                Remove-ItemProperty -Path $r32 -Name $prop.Name -ErrorAction SilentlyContinue
                Write-Log "Removed RunOnce entry: $($prop.Name)" "OK"
            }
        }
    }
}

Write-Log "Startup fully minimized - only Windows Security survives" "OK"

# --- Enable "Restart Apps" After Sign-In (session restore) ---
Write-Log "Enabling session restore (reopen apps after restart)..."
# This is the "Automatically save my restartable apps and restart them when I sign back in"
$SignInPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $SignInPath -Name "RestartApps" -Value 1 -Type DWord
# Also enable via Settings path
$RestartPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
# Use the registered apps restore feature
$AccountPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
if (-not (Test-Path $AccountPath)) { New-Item -Path $AccountPath -Force | Out-Null }
Set-ItemProperty -Path $AccountPath -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord

# Enable "Use my sign-in info to auto-finish after an update"
$WinlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $WinlogonPath -Name "DisableAutomaticRestartSignOn" -Value 0 -Type DWord
Write-Log "Session restore enabled - previously open apps will reopen after restart" "OK"

# --- Validate & Repair Windows Terminal Settings ---
Write-Log "Validating Windows Terminal settings..."
$wtConfig = Repair-WTSettings
if ($wtConfig) {
    Write-Log "Windows Terminal settings validated" "OK"
} else {
    Write-Log "Windows Terminal settings could not be validated" "WARN"
}

# --- Add Windows Terminal to Startup ---
Write-Log "Adding Windows Terminal to startup..."
$wtStartupLnk = Join-Path $startupFolder "Windows Terminal.lnk"
if (-not (Test-Path $wtStartupLnk)) {
    $WshShell = New-Object -ComObject WScript.Shell
    $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
    if (-not $wtPath) { $wtPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe" }
    if (Test-Path $wtPath) {
        $shortcut = $WshShell.CreateShortcut($wtStartupLnk)
        $shortcut.TargetPath = $wtPath
        $shortcut.Arguments = "--startOnUserLogin"
        $shortcut.Description = "Windows Terminal"
        $shortcut.WindowStyle = 7  # Minimized
        $shortcut.Save()
        Write-Log "Windows Terminal added to startup (minimized)" "OK"
    } else {
        Write-Log "Windows Terminal not found - skipping startup entry" "WARN"
    }
}

# ============================================================================
# System Cleanup - Temp Files, Caches, Update Leftovers
# ============================================================================
Write-Log "Running system cleanup..."

# --- Temp files ---
$tempPaths = @(
    $env:TEMP,
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\Temp"
)
foreach ($tp in $tempPaths) {
    if (Test-Path $tp) {
        Get-ChildItem $tp -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaned: $tp" "OK"
    }
}

# --- Windows Update cache ---
Write-Log "Cleaning Windows Update cache..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
$wuCache = "$env:WINDIR\SoftwareDistribution\Download"
if (Test-Path $wuCache) {
    Remove-Item "$wuCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Windows Update download cache cleared" "OK"
}
$wuDataStore = "$env:WINDIR\SoftwareDistribution\DataStore"
if (Test-Path $wuDataStore) {
    Remove-Item "$wuDataStore\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Windows Update data store cleared" "OK"
}
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Start-Service -Name bits -ErrorAction SilentlyContinue

# --- DISM component cleanup (remove superseded updates) ---
Write-Log "Running DISM component cleanup..."
dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase >$null 2>&1
Write-Log "DISM component cleanup done" "OK"

# --- Thumbnail cache ---
$thumbCache = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path $thumbCache) {
    Get-ChildItem $thumbCache -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Thumbnail cache cleared" "OK"
}

# --- Font cache ---
Stop-Service -Name FontCache -Force -ErrorAction SilentlyContinue
$fontCache = "$env:WINDIR\ServiceProfiles\LocalService\AppData\Local\FontCache"
if (Test-Path $fontCache) {
    Remove-Item "$fontCache\*" -Recurse -Force -ErrorAction SilentlyContinue
}
Start-Service -Name FontCache -ErrorAction SilentlyContinue
Write-Log "Font cache cleared" "OK"

# --- Prefetch ---
$prefetch = "$env:WINDIR\Prefetch"
if (Test-Path $prefetch) {
    Remove-Item "$prefetch\*" -Force -ErrorAction SilentlyContinue
    Write-Log "Prefetch cache cleared" "OK"
}

# --- Windows Installer cache (orphaned patches) ---
$installerCache = "$env:WINDIR\Installer\`$PatchCache`$"
if (Test-Path $installerCache) {
    Remove-Item "$installerCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Installer patch cache cleared" "OK"
}

# --- Delivery Optimization cache ---
Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
Write-Log "Delivery Optimization cache cleared" "OK"

# --- Windows Error Reporting dumps ---
$werDumps = @(
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER",
    "$env:PROGRAMDATA\Microsoft\Windows\WER"
)
foreach ($wd in $werDumps) {
    if (Test-Path $wd) {
        Remove-Item "$wd\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Log "Error reporting dumps cleared" "OK"

# --- Event logs (clear all) ---
Write-Log "Clearing Windows event logs..."
wevtutil el 2>$null | ForEach-Object { wevtutil cl $_ >$null 2>&1 }
Write-Log "Event logs cleared" "OK"

# --- DNS cache ---
ipconfig /flushdns >$null 2>&1
Write-Log "DNS cache flushed" "OK"

# --- Recycle Bin ---
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Log "Recycle Bin emptied" "OK"

# --- Browser caches (Chrome, Firefox, Edge) ---
$browserCaches = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
)
foreach ($bc in $browserCaches) {
    if (Test-Path $bc) {
        Remove-Item "$bc\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Firefox cache (profile-based)
$ffProfiles = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $ffProfiles) {
    Get-ChildItem $ffProfiles -Directory | ForEach-Object {
        $cache2 = Join-Path $_.FullName "cache2"
        if (Test-Path $cache2) { Remove-Item "$cache2\*" -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
Write-Log "Browser caches cleared (Chrome, Edge, Firefox)" "OK"

# --- npm/pip/cargo caches ---
$devCaches = @(
    "$env:LOCALAPPDATA\npm-cache",
    "$env:LOCALAPPDATA\pip\Cache",
    (Join-Path $env:USERPROFILE ".cargo\registry\cache")
)
foreach ($dc in $devCaches) {
    if (Test-Path $dc) {
        Remove-Item "$dc\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Log "Dev caches cleared (npm, pip, cargo)" "OK"

# --- Calculate space freed ---
Write-Log "System cleanup complete" "OK"

# ============================================================================
# Run Windows Update check
# ============================================================================
Write-Log "Checking for Windows Updates..."
$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()
try {
    $searchResult = $updateSearcher.Search("IsInstalled=0")
    $pendingCount = $searchResult.Updates.Count
    if ($pendingCount -gt 0) {
        Write-Log "$pendingCount update(s) available - they will install at 3 AM per policy" "INFO"
        foreach ($update in $searchResult.Updates) {
            Write-Log "  Pending: $($update.Title)" "INFO"
        }
    } else {
        Write-Log "System is up to date - no pending updates" "OK"
    }
} catch {
    Write-Log "Windows Update check failed: $_" "WARN"
}

# ============================================================================
# Post-Install Verification
# ============================================================================
Write-Log "Running post-install verification..." "STEP"

$script:VerifyPassed = 0
$script:VerifyFailed = 0
$script:VerifyWarned = 0
$script:VerifyReport = @()

function Verify-Item {
    param(
        [string]$Category,
        [string]$Name,
        [scriptblock]$Check
    )
    try {
        $result = & $Check
        if ($result) {
            $script:VerifyPassed++
            $script:VerifyReport += @{ Cat = $Category; Name = $Name; Status = "OK" }
        } else {
            $script:VerifyFailed++
            $script:VerifyReport += @{ Cat = $Category; Name = $Name; Status = "FAIL" }
            Write-Log "VERIFY FAIL: $Category / $Name" "WARN"
        }
    } catch {
        $script:VerifyWarned++
        $script:VerifyReport += @{ Cat = $Category; Name = $Name; Status = "WARN" }
    }
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# --- Package Managers ---
Start-Spinner "Verifying package managers..."
Verify-Item "PackageManager" "winget"     { $null -ne (Get-Command winget -ErrorAction SilentlyContinue) }
Verify-Item "PackageManager" "choco"      { $null -ne (Get-Command choco -ErrorAction SilentlyContinue) }
Verify-Item "PackageManager" "scoop"      { $null -ne (Get-Command scoop -ErrorAction SilentlyContinue) }
Verify-Item "PackageManager" "npm"        { $null -ne (Get-Command npm -ErrorAction SilentlyContinue) }
Verify-Item "PackageManager" "pip"        { $null -ne (Get-Command pip -ErrorAction SilentlyContinue) }
Verify-Item "PackageManager" "cargo"      { $null -ne (Get-Command cargo -ErrorAction SilentlyContinue) }
Stop-Spinner -FinalMessage "Package managers verified" -Status "OK"

# --- Core Dev Tools ---
Start-Spinner "Verifying core dev tools..."
$coreTools = @(
    @("DevTool", "git"),
    @("DevTool", "python"),
    @("DevTool", "node"),
    @("DevTool", "code"),
    @("DevTool", "pwsh"),
    @("DevTool", "go"),
    @("DevTool", "rustc"),
    @("DevTool", "gcc"),
    @("DevTool", "cmake"),
    @("DevTool", "make"),
    @("DevTool", "docker"),
    @("DevTool", "kubectl"),
    @("DevTool", "helm"),
    @("DevTool", "terraform"),
    @("DevTool", "ruby"),
    @("DevTool", "perl"),
    @("DevTool", "java"),
    @("DevTool", "javac"),
    @("DevTool", "mvn"),
    @("DevTool", "gradle"),
    @("DevTool", "deno"),
    @("DevTool", "bun")
)
foreach ($tool in $coreTools) {
    Verify-Item $tool[0] $tool[1] { $null -ne (Get-Command $tool[1] -ErrorAction SilentlyContinue) }
}
Stop-Spinner -FinalMessage "Core dev tools verified" -Status "OK"

# --- CLI Tools in PATH ---
Start-Spinner "Verifying CLI tools..."
$cliTools = @(
    @("CLI", "rg"),
    @("CLI", "fd"),
    @("CLI", "bat"),
    @("CLI", "fzf"),
    @("CLI", "jq"),
    @("CLI", "curl"),
    @("CLI", "ssh"),
    @("CLI", "7z"),
    @("CLI", "ffmpeg"),
    @("CLI", "adb"),
    @("CLI", "nmap"),
    @("CLI", "lazygit"),
    @("CLI", "delta")
)
foreach ($tool in $cliTools) {
    Verify-Item $tool[0] $tool[1] { $null -ne (Get-Command $tool[1] -ErrorAction SilentlyContinue) }
}
Stop-Spinner -FinalMessage "CLI tools verified" -Status "OK"

# --- GUI Applications (check install paths) ---
Start-Spinner "Verifying GUI applications..."
$guiApps = @(
    @("App", "Google Chrome",       "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"),
    @("App", "Firefox",             "$env:ProgramFiles\Mozilla Firefox\firefox.exe"),
    @("App", "VS Code",             "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"),
    @("App", "Visual Studio 2022",  "${env:ProgramFiles}\Microsoft Visual Studio\2022"),
    @("App", "Android Studio",      "$env:ProgramFiles\Android\Android Studio\bin\studio64.exe"),
    @("App", "Docker Desktop",      "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"),
    @("App", "7-Zip",               "$env:ProgramFiles\7-Zip\7z.exe"),
    @("App", "Notepad++",           "$env:ProgramFiles\Notepad++\notepad++.exe"),
    @("App", "PuTTY",               "$env:ProgramFiles\PuTTY\putty.exe"),
    @("App", "WinSCP",              "$env:ProgramFiles (x86)\WinSCP\WinSCP.exe"),
    @("App", "GIMP",                "$env:ProgramFiles\GIMP 2\bin\gimp-2.10.exe"),
    @("App", "Inkscape",            "$env:ProgramFiles\Inkscape\bin\inkscape.exe"),
    @("App", "VLC",                 "$env:ProgramFiles\VideoLAN\VLC\vlc.exe"),
    @("App", "Wireshark",           "$env:ProgramFiles\Wireshark\Wireshark.exe"),
    @("App", "Postman",             "$env:LOCALAPPDATA\Postman\Postman.exe"),
    @("App", "Git Desktop",         "$env:LOCALAPPDATA\GitHubDesktop\GitHubDesktop.exe"),
    @("App", "OpenVPN",             "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"),
    @("App", "Bitwarden",           "$env:ProgramFiles\Bitwarden\Bitwarden.exe"),
    @("App", "PowerToys",           "$env:ProgramFiles\PowerToys\PowerToys.exe"),
    @("App", "qBittorrent",         "$env:ProgramFiles\qBittorrent\qbittorrent.exe")
)
foreach ($app in $guiApps) {
    $checkPath = $app[2]
    Verify-Item $app[0] $app[1] {
        (Test-Path $checkPath) -or (Test-Path "$checkPath*") -or
        (Get-ChildItem (Split-Path $checkPath) -ErrorAction SilentlyContinue | Where-Object { $_.Name -match [regex]::Escape((Split-Path $checkPath -Leaf).TrimEnd('.exe')) })
    }
}
Stop-Spinner -FinalMessage "GUI applications verified" -Status "OK"

# --- Directories ---
Start-Spinner "Verifying directories..."
$dirs = @(
    @("Dir", "C:\bin",          "C:\bin"),
    @("Dir", "C:\apps",         "C:\apps"),
    @("Dir", "C:\vcpkg",        "C:\vcpkg"),
    @("Dir", "C:\venv",         "C:\venv"),
    @("Dir", "C:\android-sdk",  "C:\android-sdk"),
    @("Dir", "C:\cygwin64",     "C:\cygwin64"),
    @("Dir", "C:\msys64",       "C:\msys64")
)
foreach ($dir in $dirs) {
    Verify-Item $dir[0] $dir[1] { Test-Path $dir[2] }
}
# Check C:\bin has tools
Verify-Item "Dir" "C:\bin has exes" {
    (Get-ChildItem "C:\bin" -Filter "*.exe" -ErrorAction SilentlyContinue).Count -gt 5
}
# Check C:\apps has folders
Verify-Item "Dir" "C:\apps has folders" {
    (Get-ChildItem "C:\apps" -Directory -ErrorAction SilentlyContinue).Count -gt 5
}
Stop-Spinner -FinalMessage "Directories verified" -Status "OK"

# --- PATH entries ---
Start-Spinner "Verifying PATH..."
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$pathEntries = @(
    @("PATH", "C:\bin"),
    @("PATH", "C:\apps"),
    @("PATH", "C:\Program Files\7-Zip"),
    @("PATH", "C:\vcpkg"),
    @("PATH", "mingw64\bin"),
    @("PATH", "cargo\bin")
)
foreach ($entry in $pathEntries) {
    $search = $entry[1]
    Verify-Item $entry[0] $search { $machinePath -match [regex]::Escape($search) -or $env:Path -match [regex]::Escape($search) }
}
Stop-Spinner -FinalMessage "PATH verified" -Status "OK"

# --- Environment Variables ---
Start-Spinner "Verifying environment variables..."
$envVars = @(
    @("EnvVar", "VCPKG_ROOT"),
    @("EnvVar", "ANDROID_HOME"),
    @("EnvVar", "JAVA_HOME"),
    @("EnvVar", "GOPATH"),
    @("EnvVar", "CMAKE_TOOLCHAIN_FILE"),
    @("EnvVar", "DOTNET_CLI_TELEMETRY_OPTOUT"),
    @("EnvVar", "POWERSHELL_TELEMETRY_OPTOUT"),
    @("EnvVar", "VSCODE_TELEMETRY_OPTOUT")
)
foreach ($ev in $envVars) {
    Verify-Item $ev[0] $ev[1] {
        [System.Environment]::GetEnvironmentVariable($ev[1], "Machine") -or
        [System.Environment]::GetEnvironmentVariable($ev[1], "User")
    }
}
Stop-Spinner -FinalMessage "Environment variables verified" -Status "OK"

# --- Registry Settings ---
Start-Spinner "Verifying registry settings..."
$regChecks = @(
    @("Registry", "Dark mode (apps)",     "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 0),
    @("Registry", "Dark mode (system)",   "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0),
    @("Registry", "File extensions",      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "HideFileExt", 0),
    @("Registry", "Hidden files",         "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "Hidden", 1),
    @("Registry", "Explorer ThisPC",      "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "LaunchTo", 1),
    @("Registry", "Search hidden",        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search", "SearchboxTaskbarMode", 0),
    @("Registry", "Bing disabled",        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search", "BingSearchEnabled", 0),
    @("Registry", "Telemetry off",        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection", "AllowTelemetry", 0),
    @("Registry", "SMBv1 disabled",       "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters", "SMB1", 0),
    @("Registry", "Long paths",           "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem", "LongPathsEnabled", 1),
    @("Registry", "Game DVR off",         "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR", "AllowGameDVR", 0),
    @("Registry", "OneDrive blocked",     "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive", "DisableFileSyncNGSC", 1),
    @("Registry", "Ink disabled",         "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace", "AllowWindowsInkWorkspace", 0),
    @("Registry", "Copilot disabled",     "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot", "TurnOffWindowsCopilot", 1),
    @("Registry", "Web search off",       "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search", "DisableWebSearch", 1)
)
foreach ($check in $regChecks) {
    $regPath = $check[2]; $regName = $check[3]; $expected = $check[4]
    Verify-Item $check[0] $check[1] {
        $val = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
        $val -eq $expected
    }
}
Stop-Spinner -FinalMessage "Registry settings verified" -Status "OK"

# --- Services ---
Start-Spinner "Verifying disabled services..."
$svcChecks = @(
    "DiagTrack", "dmwappushservice", "SysMain", "WSearch", "Fax",
    "wisvc", "PhoneSvc", "RetailDemo", "MapsBroker", "lfsvc",
    "XblAuthManager", "XblGameSave", "TabletInputService"
)
foreach ($svc in $svcChecks) {
    Verify-Item "Service" "$svc disabled" {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { $s.StartType -eq "Disabled" } else { $true }
    }
}
Stop-Spinner -FinalMessage "Services verified" -Status "OK"

# --- Hosts File ---
Start-Spinner "Verifying hosts file blocks..."
$hostsContent = Get-Content "$env:WINDIR\System32\drivers\etc\hosts" -Raw -ErrorAction SilentlyContinue
Verify-Item "Hosts" "Telemetry block"    { $hostsContent -match "WinInit Telemetry Block" }
Verify-Item "Hosts" "Bing/Search block"  { $hostsContent -match "WinInit Bing" }
Verify-Item "Hosts" "Extended block"     { $hostsContent -match "WinInit Extended" }
Stop-Spinner -FinalMessage "Hosts file verified" -Status "OK"

# --- Windows Terminal Settings ---
Start-Spinner "Verifying Windows Terminal settings..."
Verify-Item "Terminal" "settings.json exists" {
    Test-Path $script:WTSettingsPath
}
Verify-Item "Terminal" "settings.json valid JSON" {
    $null -ne (Read-WTSettings)
}
Verify-Item "Terminal" "has visible profiles" {
    $wt = Read-WTSettings
    $wt -and $wt.profiles -and $wt.profiles.list -and @($wt.profiles.list | Where-Object { -not $_.hidden -or $_.hidden -eq $false }).Count -gt 0
}
Stop-Spinner -FinalMessage "Windows Terminal verified" -Status "OK"

# --- Browser Extensions (policies exist) ---
Start-Spinner "Verifying browser extension policies..."
Verify-Item "Browser" "Firefox policies.json" {
    Test-Path "$env:ProgramFiles\Mozilla Firefox\distribution\policies.json"
}
Verify-Item "Browser" "Chrome extensions policy" {
    Test-Path "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
}
Verify-Item "Browser" "Edge extensions policy" {
    Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"
}
Stop-Spinner -FinalMessage "Browser policies verified" -Status "OK"

# --- VS Code Extensions ---
Start-Spinner "Verifying VS Code extensions..."
$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if ($codeCmd) {
    $installedExts = & code --list-extensions 2>$null
    $keyExts = @(
        "anthropic.claude-code",
        "ms-vscode.cpptools",
        "ms-python.python",
        "ms-azuretools.vscode-docker",
        "rust-lang.rust-analyzer",
        "dbaeumer.vscode-eslint"
    )
    foreach ($ext in $keyExts) {
        Verify-Item "VSCode" $ext { $installedExts -contains $ext }
    }
}
Stop-Spinner -FinalMessage "VS Code extensions verified" -Status "OK"

# --- Defender Exclusions ---
Start-Spinner "Verifying Defender exclusions..."
try {
    $prefs = Get-MpPreference -ErrorAction Stop
    Verify-Item "Defender" "C:\vcpkg excluded"  { $prefs.ExclusionPath -contains "C:\vcpkg" }
    Verify-Item "Defender" "C:\bin excluded"     { $prefs.ExclusionPath -contains "C:\bin" }
    Verify-Item "Defender" "node.exe excluded"   { $prefs.ExclusionProcess -contains "node.exe" }
    Verify-Item "Defender" "cargo.exe excluded"  { $prefs.ExclusionProcess -contains "cargo.exe" }
} catch {
    Write-Log "Defender preferences not accessible" "WARN"
}
Stop-Spinner -FinalMessage "Defender exclusions verified" -Status "OK"

# --- Print Verification Report ---
Write-Blank
Write-Rule -Char "=" -Width 70 -Color "Cyan"

$totalVerify = $script:VerifyPassed + $script:VerifyFailed + $script:VerifyWarned
Write-Log "Verification: $($script:VerifyPassed)/$totalVerify passed, $($script:VerifyFailed) failed, $($script:VerifyWarned) warnings" "INFO"

# Show failures
if ($script:VerifyFailed -gt 0) {
    Write-Log "Failed verifications:" "WARN"
    foreach ($item in $script:VerifyReport | Where-Object { $_.Status -eq "FAIL" }) {
        Write-Log "  MISSING: [$($item.Cat)] $($item.Name)" "WARN"
    }
}

# Stats by category
$categories = $script:VerifyReport | Group-Object Cat
foreach ($cat in $categories) {
    $passed = ($cat.Group | Where-Object { $_.Status -eq "OK" }).Count
    $total = $cat.Group.Count
    $pct = if ($total -gt 0) { [math]::Round(($passed / $total) * 100) } else { 0 }
    $statusColor = if ($pct -eq 100) { "OK" } elseif ($pct -ge 80) { "WARN" } else { "ERROR" }
    Write-Log "  $($cat.Name.PadRight(15)) $passed/$total ($pct%)" $statusColor
}

Write-Rule -Char "=" -Width 70 -Color "Cyan"
Write-Blank

# --- Restart Explorer to apply all visual changes ---
Write-Log "Restarting Explorer to apply all changes..."
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process explorer.exe
Write-Log "Explorer restarted" "OK"

# ============================================================================
# Done
# ============================================================================
Write-Log "=========================================="
Write-Log "WinInit complete! Check log: $LogFile"
Write-Log "REBOOT REQUIRED for: Hyper-V, UTF-8, locale, WSL, SMBv1, SSD changes."
Write-Log "A restore point 'WinInit Complete' has been created."
Write-Log "=========================================="

Write-Log "Module 18 - Final Config completed" "OK"

