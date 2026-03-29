# Module: 01 - Package Managers
# ============================================================================
Write-Section "Section 1: Package Managers" "Installing winget, scoop, and Chocolatey"

# --- 1a. Winget ---
Write-Log "Checking winget..."
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Log "winget is already available" "OK"
} else {
    Write-Log "Installing winget (App Installer) from Microsoft Store..."
    Install-WithRetry "winget" {
        # winget ships with App Installer - force update via Add-AppxPackage
        $releases = Invoke-RestMethod "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $msixUrl  = ($releases.assets | Where-Object { $_.name -match '\.msixbundle$' }).browser_download_url
        $licUrl   = ($releases.assets | Where-Object { $_.name -match 'License.*\.xml$' }).browser_download_url
        $msixPath = Join-Path $env:TEMP "winget.msixbundle"
        $licPath  = Join-Path $env:TEMP "winget-license.xml"
        Invoke-WebRequest $msixUrl -OutFile $msixPath -UseBasicParsing
        Invoke-WebRequest $licUrl  -OutFile $licPath  -UseBasicParsing
        Add-AppxProvisionedPackage -Online -PackagePath $msixPath -LicensePath $licPath
        Remove-Item $msixPath, $licPath -ErrorAction SilentlyContinue
    }
}

# --- 1b. Scoop (must run as non-elevated user) ---
Write-Log "Checking scoop..."
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Log "scoop is already available" "OK"
} else {
    Write-Log "Installing scoop (as non-elevated process)..."
    try {
        # Scoop refuses to install as admin by default
        # Use the SCOOP_GLOBAL approach + RunAsInvoker trick
        [System.Environment]::SetEnvironmentVariable("SCOOP", "$env:USERPROFILE\scoop", "User")
        [System.Environment]::SetEnvironmentVariable("SCOOP_GLOBAL", "C:\scoop-global", "Machine")
        $env:SCOOP = "$env:USERPROFILE\scoop"
        $env:SCOOP_GLOBAL = "C:\scoop-global"

        # Download and run the installer with admin install enabled
        $scoopInstaller = Join-Path $env:TEMP "install-scoop.ps1"
        Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstaller -UseBasicParsing
        # Patch the installer to allow admin (add -RunAsAdmin flag)
        & powershell -NoProfile -ExecutionPolicy Bypass -Command "& { iex (Get-Content '$scoopInstaller' -Raw) } -RunAsAdmin" 2>&1 | Out-Null

        Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")

        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Log "scoop installed successfully" "OK"
        } else {
            # Try the direct approach as fallback
            Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin" 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                Write-Log "scoop installed (fallback method)" "OK"
            } else {
                Write-Log "scoop install failed - will use winget/choco as fallback" "WARN"
            }
        }
    } catch {
        Write-Log "scoop install failed: $_ - will use winget/choco as fallback" "WARN"
    }

    # Add extras bucket (only if scoop is available)
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop bucket add extras >$null 2>&1
        scoop bucket add versions >$null 2>&1
        Write-Log "scoop extras and versions buckets added" "OK"
    }
}

# --- 1c. Chocolatey ---
Write-Log "Checking Chocolatey..."
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Log "Chocolatey is already available" "OK"
} else {
    Write-Log "Installing Chocolatey..."
    Install-WithRetry "Chocolatey" {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
}

# Refresh PATH so new package managers are available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Summary of available package managers
$pmAvail = @()
if (Get-Command winget -ErrorAction SilentlyContinue) { $pmAvail += "winget" }
if (Get-Command scoop -ErrorAction SilentlyContinue)  { $pmAvail += "scoop" }
if (Get-Command choco -ErrorAction SilentlyContinue)  { $pmAvail += "choco" }
Write-Log "Package managers available: $($pmAvail -join ', ')" "OK"

Write-Log "Section 1: Package Managers completed" "OK"
