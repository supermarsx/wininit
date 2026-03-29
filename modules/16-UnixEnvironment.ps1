# Module: 16 - Unix Environment
# Cygwin + MSYS2 + Strawberry Perl, Python venv setup, Go, Ruby

Write-Section "Unix Environment" "Cygwin, MSYS2, Perl, Python, Go, Ruby"

# ============================================================================
# Linux/Unix Environment (Cygwin, MSYS2, Git Bash)
# ============================================================================

# --- Cygwin (full POSIX environment: sh, bash, grep, awk, sed, ssh, etc.) ---
$cygwinRoot = "C:\cygwin64"
$cygwinInstaller = Join-Path $env:TEMP "cygwin-setup-x86_64.exe"
if (Test-Path "$cygwinRoot\bin\bash.exe") {
    Write-Log "Cygwin already installed at $cygwinRoot" "OK"
} else {
Write-Log "Installing Cygwin..."
Invoke-WebRequest -Uri "https://cygwin.com/setup-x86_64.exe" -OutFile $cygwinInstaller -UseBasicParsing

# Install with a comprehensive set of packages
$cygwinPackages = @(
    "bash", "coreutils", "grep", "gawk", "sed", "findutils", "diffutils",
    "tar", "gzip", "bzip2", "xz", "unzip", "zip",
    "curl", "wget", "openssh", "openssl",
    "make", "gcc-core", "gcc-g++", "gdb", "cmake",
    "git", "patch", "dos2unix",
    "vim", "nano", "less", "tree", "which", "file",
    "rsync", "nc", "socat", "inetutils",
    "python39", "python39-pip",
    "perl", "perl-ExtUtils-MakeMaker",
    "ruby",
    "tmux", "screen",
    "man-db", "cygutils-extra",
    "bc", "xxd", "strace"
) -join ","

$cygwinArgs = "--quiet-mode --no-admin --root $cygwinRoot --site https://mirrors.kernel.org/sourceware/cygwin/ --packages $cygwinPackages --no-desktop --no-startmenu"
$r = Invoke-SilentWithProgress $cygwinInstaller $cygwinArgs -Prefix "Cygwin"

# Add Cygwin bin to system PATH
$cygwinBin = Join-Path $cygwinRoot "bin"
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notmatch [regex]::Escape($cygwinBin)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$cygwinBin", "Machine")
    $env:Path = "$env:Path;$cygwinBin"
    Write-Log "Cygwin bin added to system PATH" "OK"
}
Remove-Item $cygwinInstaller -Force -ErrorAction SilentlyContinue
Write-Log "Cygwin installed with $(($cygwinPackages -split ',').Count) packages" "OK"
} # end Cygwin install check

# --- MSYS2 (alternative - lighter, pacman-based, better for building native Windows apps) ---
Write-Log "Installing MSYS2..."
Install-App "MSYS2" -WingetId "MSYS2.MSYS2" -ChocoId "msys2"

# Add MSYS2 usr/bin to PATH as well (lower priority than Cygwin)
$msys2Bin = "C:\msys64\usr\bin"
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ((Test-Path $msys2Bin) -and ($machinePath -notmatch [regex]::Escape($msys2Bin))) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$msys2Bin", "Machine")
    $env:Path = "$env:Path;$msys2Bin"
    Write-Log "MSYS2 bin added to system PATH" "OK"
}

Write-Log "Linux/Unix environment ready (sh, bash, grep, awk, sed, make, gcc, etc. all in PATH)" "OK"

# ============================================================================
# Perl, Python venv, Language Runtimes
# ============================================================================
Write-SubStep "Language Runtimes"

# --- Strawberry Perl (full Perl for Windows with CPAN) ---
Write-Log "Installing Strawberry Perl..."
Install-App "Strawberry Perl" -WingetId "StrawberryPerl.StrawberryPerl" -ChocoId "strawberryperl"
Write-Log "Strawberry Perl installed" "OK"

# --- Python venv: create a global default venv ---
# pip upgrade + globals are handled by module 14 background job
# Here we just create the venv structure and activation alias
$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if ($pythonExe) {
    $venvDir = "C:\venv"
    $defaultVenv = Join-Path $venvDir "default"

    if (Test-Path "$defaultVenv\Scripts\python.exe") {
        Write-Log "Python venv already exists at $defaultVenv" "OK"
    } else {
        Write-Log "Creating default Python venv..."
        if (-not (Test-Path $venvDir)) { New-Item -ItemType Directory -Path $venvDir -Force | Out-Null }
        & python -m venv $defaultVenv 2>&1 | Out-Null
        if (Test-Path "$defaultVenv\Scripts\python.exe") {
            Write-Log "Default venv created at $defaultVenv" "OK"
        } else {
            Write-Log "Failed to create venv at $defaultVenv" "WARN"
        }
    }

    # Create activation alias for PowerShell profile (if not already there)
    $psProfile = $PROFILE.CurrentUserAllHosts
    $psProfileDir = Split-Path $psProfile
    if (-not (Test-Path $psProfileDir)) { New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null }
    $activateAlias = @"

# WinInit: Python venv activation alias
function Activate-Venv { param([string]`$Name = "default") & "C:\venv\`$Name\Scripts\Activate.ps1" }
Set-Alias -Name venv -Value Activate-Venv
"@
    $aliasExists = $false
    if (Test-Path $psProfile) {
        $profileContent = Get-Content $psProfile -Raw -ErrorAction SilentlyContinue
        if ($profileContent -match "Activate-Venv") { $aliasExists = $true }
    }
    if (-not $aliasExists) {
        if (Test-Path $psProfile) {
            Add-Content -Path $psProfile -Value $activateAlias
        } else {
            Set-Content -Path $psProfile -Value $activateAlias -Encoding UTF8
        }
        Write-Log "PowerShell alias 'venv' created (usage: venv or venv myproject)" "OK"
    }

} else {
    Write-Log "Python not found - venv setup skipped" "WARN"
}

# --- Go (useful for many security tools) ---
Install-App "Go" -WingetId "GoLang.Go" -ChocoId "golang" -ScoopId "go"

# --- Ruby (standalone, for scripts/gems) ---
Install-App "Ruby" -WingetId "RubyInstallerTeam.Ruby.3.3" -ChocoId "ruby"

Write-Log "Language runtimes configured" "OK"

Write-Log "Module 16 - Unix Environment completed" "OK"

