# Module: 12 - Security Hardening & Windows Features
# SMBv1, LLMNR, Hyper-V, UTF-8, Sandbox, Reserved Storage

Write-Section "Security Hardening"

# Suppress all progress bars from DISM/Appx/WindowsFeature cmdlets
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# --- 12a. Disable SMBv1 ---
Write-Log "Disabling SMBv1 (legacy, exploitable)..."
$smb1Features = @("SMB1Protocol", "SMB1Protocol-Client", "SMB1Protocol-Server")
$smb1AlreadyOff = $true
foreach ($smb1 in $smb1Features) {
    $state = Get-WindowsOptionalFeature -Online -FeatureName $smb1 -ErrorAction SilentlyContinue
    if ($state -and $state.State -eq "Enabled") {
        $smb1AlreadyOff = $false
        Disable-WindowsOptionalFeature -Online -FeatureName $smb1 -NoRestart -ErrorAction SilentlyContinue 3>$null | Out-Null
    }
}
if ($smb1AlreadyOff) {
    Write-Log "SMBv1 already disabled" "OK"
} else {
    # Disable SMBv1 server config
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue 3>$null | Out-Null
    # Verify
    $smb1Verify = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue
    if ($smb1Verify -and $smb1Verify.State -in @("Disabled", "DisablePending")) {
        Write-Log "SMBv1 disabled successfully" "OK"
    } else {
        Write-Log "SMBv1 may still be active (state: $($smb1Verify.State))" "WARN"
    }
}
# Registry belt-and-suspenders
$SMBPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
Set-ItemProperty -Path $SMBPath -Name "SMB1" -Value 0 -Type DWord

# --- 12b. Disable LLMNR ---
Write-Log "Disabling LLMNR (Link-Local Multicast Name Resolution)..."
$DNSClientPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $DNSClientPath)) { New-Item -Path $DNSClientPath -Force | Out-Null }
Set-ItemProperty -Path $DNSClientPath -Name "EnableMulticast" -Value 0 -Type DWord
Write-Log "LLMNR disabled" "OK"

# ============================================================================
# SECTION 13 - Windows Features (Hyper-V, UTF-8)
# ============================================================================
Write-Section "Windows Features"

# --- 13b. Enable UTF-8 System-Wide ---
Write-Log "Enabling UTF-8 system-wide (Beta: Use Unicode UTF-8)..."
# This sets the "Use Unicode UTF-8 for worldwide language support" checkbox
$NLSPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage"
Set-ItemProperty -Path $NLSPath -Name "ACP"    -Value "65001" -Type String   # ANSI code page -> UTF-8
Set-ItemProperty -Path $NLSPath -Name "OEMCP"  -Value "65001" -Type String   # OEM code page -> UTF-8
Set-ItemProperty -Path $NLSPath -Name "MACCP"  -Value "65001" -Type String   # MAC code page -> UTF-8
# Also set the intl config
$IntlGlobal = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language"
Set-ItemProperty -Path $IntlGlobal -Name "Default" -Value "0409" -Type String -ErrorAction SilentlyContinue
# Set console to UTF-8 by default
$ConsoleRegPath = "HKCU:\Console"
Set-ItemProperty -Path $ConsoleRegPath -Name "CodePage" -Value 65001 -Type DWord -ErrorAction SilentlyContinue
# PowerShell output encoding
[System.Environment]::SetEnvironmentVariable("PYTHONIOENCODING", "utf-8", "User")
Write-Log "UTF-8 enabled system-wide (code pages set to 65001)" "OK"

# ============================================================================
# Enable Windows Optional Features (comprehensive)
# ============================================================================
Write-Log "Enabling Windows optional features..."

# Features that use Enable-WindowsOptionalFeature (FeatureName style)
$enableFeatures = @(
    # --- Hyper-V (full suite) ---
    "Microsoft-Hyper-V-All",
    "Microsoft-Hyper-V",
    "Microsoft-Hyper-V-Tools-All",
    "Microsoft-Hyper-V-Management-PowerShell",
    "Microsoft-Hyper-V-Management-Clients",
    "Microsoft-Hyper-V-Hypervisor",
    "Microsoft-Hyper-V-Services",
    # --- Virtualization Platform ---
    "VirtualMachinePlatform",
    "HypervisorPlatform",
    # --- Containers ---
    "Containers",
    "Containers-DisposableClientVM",     # Windows Sandbox
    # --- WSL ---
    "Microsoft-Windows-Subsystem-Linux",
    # --- .NET Frameworks ---
    "NetFx3",                             # .NET 3.5
    "NetFx4-AdvSrvs",                     # .NET 4.8 Advanced Services
    "NetFx4Extended-ASPNET45",            # ASP.NET 4.5+
    "WCF-Services45",                     # WCF Services
    "WCF-TCP-PortSharing45",              # WCF TCP Port Sharing
    # --- Network Tools ---
    "TelnetClient",                        # Telnet client
    "TFTP",                                # TFTP client
    # --- Misc ---
    "SimpleTCP",
    # --- Brandless Boot (removes Windows logo during boot) ---
    "Client-DeviceLockdown",
    "Client-EmbeddedBootExp"
)

# Capabilities that use Add-WindowsCapability (Name~~~~ style)
$enableCapabilities = @(
    "WirelessDisplay.Client~~~~0.0.1.0",                           # Miracast
    "Microsoft-Windows-Client-EmbeddedExp-Package~~~~0.0.1.0"      # WMIC
)

$featureResults = @{ enabled = 0; skipped = 0; failed = 0 }

foreach ($feature in $enableFeatures) {
    # Check current state first
    $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    if (-not $state) {
        Write-Log "Feature not available: $feature (not on this edition)" "WARN"
        $featureResults.failed++
        continue
    }
    if ($state.State -eq "Enabled") {
        Write-Log "Already enabled: $feature" "OK"
        $featureResults.skipped++
        continue
    }

    # Enable it
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction Stop 3>$null | Out-Null
    } catch {
        # Fallback to DISM
        dism /Online /Enable-Feature /FeatureName:$feature /NoRestart /All >$null 2>&1
    }

    # Verify it took effect
    $verify = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue
    if ($verify -and $verify.State -in @("Enabled", "EnablePending")) {
        Write-Log "Feature enabled: $feature" "OK"
        $featureResults.enabled++
    } else {
        Write-Log "Feature failed to enable: $feature (state: $($verify.State))" "WARN"
        $featureResults.failed++
    }
}

foreach ($cap in $enableCapabilities) {
    # Check current state first
    $state = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cap }
    if (-not $state) {
        Write-Log "Capability not available: $cap" "WARN"
        $featureResults.failed++
        continue
    }
    if ($state.State -eq "Installed") {
        Write-Log "Already installed: $cap" "OK"
        $featureResults.skipped++
        continue
    }

    # Enable it
    try {
        Add-WindowsCapability -Online -Name $cap -ErrorAction Stop 3>$null | Out-Null
    } catch {
        Write-Log "Capability failed: $cap ($_)" "WARN"
        $featureResults.failed++
        continue
    }

    # Verify
    $verify = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $cap }
    if ($verify -and $verify.State -eq "Installed") {
        Write-Log "Capability installed: $cap" "OK"
        $featureResults.enabled++
    } else {
        Write-Log "Capability failed to install: $cap" "WARN"
        $featureResults.failed++
    }
}

Write-Log "Features: $($featureResults.enabled) enabled, $($featureResults.skipped) already active, $($featureResults.failed) unavailable" "OK"

# WMIC and Wireless Display already handled by capabilities loop above

# --- .NET 3.5 via DISM (most reliable method) ---
Write-Log "Ensuring .NET 3.5..."
$dotnet35 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction SilentlyContinue
if ($dotnet35 -and $dotnet35.State -ne "Enabled") {
    dism /Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart >$null 2>&1 3>$null
    Write-Log ".NET 3.5 enabled via DISM" "OK"
} else {
    Write-Log ".NET 3.5 already enabled" "OK"
}

# --- .NET 4.8 (usually pre-installed on Win 10 1903+, but ensure it) ---
$dotnet48Key = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue
if ($dotnet48Key -and $dotnet48Key.Release -ge 528040) {
    Write-Log ".NET 4.8+ already installed (release $($dotnet48Key.Release))" "OK"
} else {
    Install-App ".NET 4.8 Runtime" -WingetId "Microsoft.DotNet.Framework.DeveloperPack_4" -ChocoId "dotnet4.8"
}

# --- Brandless Boot (remove Windows logo, show plain boot) ---
Write-Log "Configuring brandless boot..."
$brandlessPath = "HKLM:\SOFTWARE\Microsoft\Windows Embedded\EmbeddedLogon"
if (-not (Test-Path $brandlessPath)) { New-Item -Path $brandlessPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $brandlessPath -Name "BrandingNeutral" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Also disable boot logo via bcdedit
bcdedit /set "{current}" bootux disabled >$null 2>&1
bcdedit /set "{current}" quietboot yes >$null 2>&1
Write-Log "Brandless/quiet boot configured" "OK"

# --- Sysmon (Sysinternals System Monitor) ---
Write-Log "Installing Sysmon..."
$sysmonExe = Get-Command sysmon -ErrorAction SilentlyContinue
if (-not $sysmonExe) {
    $sysmonExe = Get-Command sysmon64 -ErrorAction SilentlyContinue
}
if (-not $sysmonExe) {
    # Download from Sysinternals Live
    $sysmonPath = "C:\bin\sysmon64.exe"
    if (-not (Test-Path $sysmonPath)) {
        try {
            Invoke-WebRequest -Uri "https://live.sysinternals.com/Sysmon64.exe" -OutFile $sysmonPath -UseBasicParsing
            Write-Log "Sysmon64 downloaded to C:\bin" "OK"
        } catch {
            Write-Log "Sysmon download failed: $_" "WARN"
        }
    }
    # Install Sysmon with default config (accept EULA)
    if (Test-Path $sysmonPath) {
        & $sysmonPath -accepteula -i 2>&1 | Out-Null
        Write-Log "Sysmon installed and running" "OK"
    }
} else {
    Write-Log "Sysmon already installed" "OK"
}

Write-Log "Windows optional features configured" "OK"

# --- Disable Reserved Storage ---
Write-Log "Disabling Reserved Storage..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" `
    -Name "ShippedWithReserves" -Value 0 -Type DWord -ErrorAction SilentlyContinue
dism /Online /Set-ReservedStorageState /State:Disabled >$null 2>&1
Write-Log "Reserved Storage disabled" "OK"

Write-Log "Module 12-SecurityHardening completed" "OK"
