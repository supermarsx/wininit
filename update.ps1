#Requires -RunAsAdministrator
# ============================================================================
# WinInit Update - Keep installed software up to date
# Standalone companion script for post-install maintenance
# Run manually or via scheduled task (WinInit-WeeklyUpdate)
# ============================================================================

param(
    [switch]$Silent,          # No interactive output
    [switch]$DryRun,          # Show what would update without doing it
    [switch]$LogOnly,         # Only write to log, no console
    [string]$LogFile = "$PSScriptRoot\wininit-updates.log"
)

$ErrorActionPreference = "Continue"
$exitCode = 0

# ============================================================================
# Logging
# ============================================================================

function Write-UpdateLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tag = switch ($Level) {
        "OK"    { "[+]" }
        "INFO"  { "[*]" }
        "WARN"  { "[!]" }
        "ERROR" { "[-]" }
        default { "[*]" }
    }

    # Always write to log file
    Add-Content -Path $LogFile -Value "[$ts] $tag $Message"

    # Console output (unless Silent or LogOnly)
    if (-not $Silent -and -not $LogOnly) {
        $color = switch ($Level) {
            "OK"    { "Green" }
            "INFO"  { "Cyan" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            default { "Gray" }
        }
        Write-Host "$ts $tag $Message" -ForegroundColor $color
    }
}

# ============================================================================
# Helper: Run an external command and capture output
# ============================================================================

function Invoke-UpdateCommand {
    param(
        [string]$Label,
        [string]$Exe,
        [string]$Args,
        [switch]$AllowFailure
    )

    Write-UpdateLog "Running: $Label" "INFO"

    if ($DryRun) {
        Write-UpdateLog "[DRY RUN] Would execute: $Exe $Args" "INFO"
        return $true
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = $Args
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit(1800000)  # 30-minute timeout per command

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        # Log output (trimmed)
        if ($stdout.Trim()) {
            foreach ($line in ($stdout -split "`n" | Select-Object -First 50)) {
                $line = $line.Trim()
                if ($line) { Write-UpdateLog "  $line" "INFO" }
            }
        }
        if ($stderr.Trim()) {
            foreach ($line in ($stderr -split "`n" | Select-Object -First 20)) {
                $line = $line.Trim()
                if ($line) { Write-UpdateLog "  [stderr] $line" "WARN" }
            }
        }

        if ($proc.ExitCode -eq 0) {
            Write-UpdateLog "$Label completed successfully" "OK"
            return $true
        } else {
            Write-UpdateLog "$Label exited with code $($proc.ExitCode)" "WARN"
            if (-not $AllowFailure) { $script:exitCode = 1 }
            return $false
        }
    } catch {
        Write-UpdateLog "$Label failed: $_" "ERROR"
        if (-not $AllowFailure) { $script:exitCode = 1 }
        return $false
    }
}

# ============================================================================
# Main Update Logic
# ============================================================================

$updateStart = Get-Date

# --- Log header ---
Add-Content -Path $LogFile -Value ""
Add-Content -Path $LogFile -Value ("=" * 70)
Add-Content -Path $LogFile -Value "WinInit Update - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($DryRun) { Add-Content -Path $LogFile -Value "MODE: DRY RUN" }
Add-Content -Path $LogFile -Value ("=" * 70)

Write-UpdateLog "WinInit Update started" "INFO"
Write-UpdateLog "User: $env:USERNAME@$env:COMPUTERNAME" "INFO"
if ($DryRun) { Write-UpdateLog "DRY RUN mode - no changes will be made" "WARN" }

# Ensure TLS 1.2 for downloads
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {}

# Refresh PATH to pick up any new installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# ============================================================================
# 1. Winget Updates
# ============================================================================

Write-UpdateLog "--- Winget Updates ---" "INFO"
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if ($wingetCmd) {
    if ($DryRun) {
        # In dry-run mode, just list available updates
        Write-UpdateLog "Listing available winget updates..." "INFO"
        Invoke-UpdateCommand -Label "winget list upgrades" `
            -Exe "winget" -Args "upgrade --accept-source-agreements" `
            -AllowFailure
    } else {
        Invoke-UpdateCommand -Label "winget upgrade all" `
            -Exe "winget" -Args "upgrade --all --silent --accept-source-agreements --accept-package-agreements --disable-interactivity" `
            -AllowFailure
    }
} else {
    Write-UpdateLog "winget not found - skipping" "WARN"
}

# ============================================================================
# 2. Chocolatey Updates
# ============================================================================

Write-UpdateLog "--- Chocolatey Updates ---" "INFO"
$chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
if ($chocoCmd) {
    if ($DryRun) {
        Invoke-UpdateCommand -Label "choco list outdated" `
            -Exe "choco" -Args "outdated --no-progress" `
            -AllowFailure
    } else {
        Invoke-UpdateCommand -Label "choco upgrade all" `
            -Exe "choco" -Args "upgrade all -y --no-progress" `
            -AllowFailure
    }
} else {
    Write-UpdateLog "Chocolatey not found - skipping" "WARN"
}

# ============================================================================
# 3. Scoop Updates
# ============================================================================

Write-UpdateLog "--- Scoop Updates ---" "INFO"
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
if ($scoopCmd) {
    if ($DryRun) {
        Invoke-UpdateCommand -Label "scoop status" `
            -Exe "scoop" -Args "status" `
            -AllowFailure
    } else {
        # Update scoop itself first, then all packages
        Invoke-UpdateCommand -Label "scoop update (self)" `
            -Exe "scoop" -Args "update" `
            -AllowFailure
        Invoke-UpdateCommand -Label "scoop update (all packages)" `
            -Exe "scoop" -Args "update *" `
            -AllowFailure
    }
} else {
    Write-UpdateLog "Scoop not found - skipping" "WARN"
}

# ============================================================================
# 4. npm Global Updates
# ============================================================================

Write-UpdateLog "--- npm Updates ---" "INFO"
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    if ($DryRun) {
        Invoke-UpdateCommand -Label "npm outdated (global)" `
            -Exe "npm" -Args "outdated -g" `
            -AllowFailure
    } else {
        Invoke-UpdateCommand -Label "npm update (global)" `
            -Exe "npm" -Args "update -g" `
            -AllowFailure
    }
} else {
    Write-UpdateLog "npm not found - skipping" "WARN"
}

# ============================================================================
# 5. pip Updates
# ============================================================================

Write-UpdateLog "--- pip Updates ---" "INFO"
$pipCmd = Get-Command pip -ErrorAction SilentlyContinue
if ($pipCmd) {
    if ($DryRun) {
        # List outdated global packages
        Invoke-UpdateCommand -Label "pip list outdated" `
            -Exe "pip" -Args "list --outdated" `
            -AllowFailure
    } else {
        # Upgrade pip itself first
        Invoke-UpdateCommand -Label "pip self-upgrade" `
            -Exe "python" -Args "-m pip install --upgrade pip" `
            -AllowFailure

        # Upgrade all globally installed packages
        # Get list of outdated packages and upgrade them one by one
        Write-UpdateLog "Checking for outdated pip packages..." "INFO"
        try {
            $pipOutdated = & pip list --outdated --format=json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($pipOutdated -and $pipOutdated.Count -gt 0) {
                Write-UpdateLog "Found $($pipOutdated.Count) outdated pip package(s)" "INFO"
                foreach ($pkg in $pipOutdated) {
                    Invoke-UpdateCommand -Label "pip upgrade $($pkg.name)" `
                        -Exe "pip" -Args "install --upgrade `"$($pkg.name)`"" `
                        -AllowFailure
                }
            } else {
                Write-UpdateLog "All pip packages are up to date" "OK"
            }
        } catch {
            Write-UpdateLog "Failed to enumerate outdated pip packages: $_" "WARN"
        }
    }
} else {
    Write-UpdateLog "pip not found - skipping" "WARN"
}

# ============================================================================
# Summary
# ============================================================================

$updateDuration = (Get-Date) - $updateStart
$durationStr = "{0:hh\:mm\:ss}" -f $updateDuration

Write-UpdateLog "--- Update Summary ---" "INFO"
Write-UpdateLog "Duration: $durationStr" "INFO"
Write-UpdateLog "Exit code: $exitCode" $(if ($exitCode -eq 0) { "OK" } else { "ERROR" })

if (-not $Silent -and -not $LogOnly) {
    Write-Host ""
    Write-Host "  Update complete in $durationStr" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Yellow" })
    Write-Host "  Log: $LogFile" -ForegroundColor Gray
    Write-Host ""
}

exit $exitCode
