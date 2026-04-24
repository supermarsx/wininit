#Requires -RunAsAdministrator
# ============================================================================
# WinInit Undo - Reverts all changes recorded in rollback.json
# Self-contained: does NOT require lib/common.ps1
# ============================================================================

param(
    [switch]$DryRun,         # Show what would be reverted without making changes
    [switch]$Confirm,        # Skip interactive confirmation prompt
    [string[]]$OnlyTypes = @()  # Filter: "registry", "service", "app_remove", etc.
)

$ErrorActionPreference = "Continue"
$RollbackFile = Join-Path $PSScriptRoot "rollback.json"
$LogFile      = Join-Path $PSScriptRoot "wininit-undo.log"

# ============================================================================
# Helpers (self-contained, no dependency on common.ps1)
# ============================================================================

function Write-UndoLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "$ts [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue

    $color = switch ($Level) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "FATAL" { "Red" }
        "INFO"  { "Gray" }
        "DEBUG" { "DarkGray" }
        default { "Gray" }
    }
    $icon = switch ($Level) {
        "OK"    { "[+]" }
        "WARN"  { "[!]" }
        "ERROR" { "[-]" }
        "FATAL" { "[X]" }
        "INFO"  { "[*]" }
        "DEBUG" { "[.]" }
        default { "[*]" }
    }
    Write-Host "  $icon $Message" -ForegroundColor $color
}

# ============================================================================
# Load rollback data
# ============================================================================

if (-not (Test-Path $RollbackFile)) {
    Write-Host ""
    Write-Host "  No rollback.json found at $RollbackFile" -ForegroundColor Yellow
    Write-Host "  Nothing to undo. Run WinInit first to generate rollback data." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

try {
    $entries = @(Get-Content $RollbackFile -Raw | ConvertFrom-Json)
} catch {
    Write-Host ""
    Write-Host "  Failed to parse rollback.json: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($entries.Count -eq 0) {
    Write-Host ""
    Write-Host "  rollback.json is empty - nothing to undo." -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Apply type filter if specified
if ($OnlyTypes.Count -gt 0) {
    $entries = @($entries | Where-Object { $_.type -in $OnlyTypes })
    if ($entries.Count -eq 0) {
        Write-Host ""
        Write-Host "  No entries matching type(s): $($OnlyTypes -join ', ')" -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
}

# ============================================================================
# Summary
# ============================================================================

$typeCounts = @{}
foreach ($e in $entries) {
    $t = $e.type
    if (-not $typeCounts.ContainsKey($t)) { $typeCounts[$t] = 0 }
    $typeCounts[$t]++
}

# Collect unique modules
$moduleList = @($entries | ForEach-Object { $_.module } | Where-Object { $_ } | Sort-Object -Unique)

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "   WinInit Undo" -ForegroundColor White
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total entries to revert: $($entries.Count)" -ForegroundColor White
foreach ($t in ($typeCounts.Keys | Sort-Object)) {
    Write-Host "    $($t): $($typeCounts[$t])" -ForegroundColor Gray
}
Write-Host ""
if ($moduleList.Count -gt 0) {
    Write-Host "  Modules affected:" -ForegroundColor White
    foreach ($m in $moduleList) {
        Write-Host "    - $m" -ForegroundColor Gray
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host "  [DRY RUN] No changes will be made." -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# Confirmation
# ============================================================================

if (-not $Confirm -and -not $DryRun) {
    Write-Host "  This will revert $($entries.Count) changes. Continue? [y/N] " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    if ($response -notin @("y", "Y", "yes", "Yes", "YES")) {
        Write-Host ""
        Write-Host "  Aborted by user." -ForegroundColor Yellow
        Write-Host ""
        exit 0
    }
    Write-Host ""
}

# ============================================================================
# Create restore point before undoing
# ============================================================================

if (-not $DryRun) {
    Write-UndoLog "Creating restore point before undo..." "INFO"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" `
            -Name "SystemRestorePointCreationFrequency" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "WinInit Pre-Undo" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
        Write-UndoLog "Restore point 'WinInit Pre-Undo' created" "OK"
    } catch {
        Write-UndoLog "Could not create restore point: $_ (continuing anyway)" "WARN"
    }
}

# ============================================================================
# Process entries in REVERSE order (LIFO - undo last change first)
# ============================================================================

Set-Content -Path $LogFile -Value "WinInit Undo Log - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ErrorAction SilentlyContinue

$successCount = 0
$failCount    = 0
$skipCount    = 0

# Reverse the array
[array]::Reverse($entries)

foreach ($entry in $entries) {
    $type = $entry.type
    $desc = $entry.description
    $data = $entry.data

    switch ($type) {
        # --- Registry ---
        "registry" {
            $regPath = $data.path
            $regName = $data.name

            if ($DryRun) {
                if ($data.previous_existed -eq $true) {
                    Write-UndoLog "[DRY RUN] Would restore registry: $regPath\$regName = $($data.previous_value)" "INFO"
                } else {
                    Write-UndoLog "[DRY RUN] Would remove registry value: $regPath\$regName" "INFO"
                }
                $skipCount++
                continue
            }

            try {
                if ($data.previous_existed -eq $true) {
                    # Restore previous value
                    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                    $regType = if ($data.type) { $data.type } else { "DWord" }
                    Set-ItemProperty -Path $regPath -Name $regName -Value $data.previous_value -Type $regType -ErrorAction Stop
                    Write-UndoLog "Restored: $regPath\$regName = $($data.previous_value)" "OK"
                    $successCount++
                } else {
                    # Value did not exist before - remove it
                    if (Test-Path $regPath) {
                        $existing = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
                        if ($null -ne $existing) {
                            Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop
                            Write-UndoLog "Removed: $regPath\$regName (did not exist before)" "OK"
                        } else {
                            Write-UndoLog "Already absent: $regPath\$regName" "DEBUG"
                        }
                        $successCount++
                    } else {
                        Write-UndoLog "Key does not exist: $regPath (nothing to remove)" "DEBUG"
                        $successCount++
                    }
                }
            } catch {
                Write-UndoLog "FAILED to revert registry $regPath\$regName : $_" "ERROR"
                $failCount++
            }
        }

        # --- Service ---
        "service" {
            $svcName = $data.name

            if ($DryRun) {
                Write-UndoLog "[DRY RUN] Would restore service $svcName to StartType=$($data.previous_start_type), Running=$($data.previous_running)" "INFO"
                $skipCount++
                continue
            }

            try {
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                if (-not $svc) {
                    Write-UndoLog "Service not found: $svcName (may have been uninstalled)" "WARN"
                    $skipCount++
                    continue
                }

                # Map WMI StartMode names to Set-Service -StartupType values
                $startTypeMap = @{
                    "Auto"     = "Automatic"
                    "Manual"   = "Manual"
                    "Disabled" = "Disabled"
                    "Boot"     = "Boot"
                    "System"   = "System"
                }
                $prevStart = $data.previous_start_type
                $mappedType = if ($startTypeMap.ContainsKey($prevStart)) { $startTypeMap[$prevStart] } else { $prevStart }

                if ($mappedType -and $mappedType -in @("Automatic", "Manual", "Disabled")) {
                    Set-Service -Name $svcName -StartupType $mappedType -ErrorAction Stop
                    Write-UndoLog "Restored service $svcName startup to $mappedType" "OK"
                }

                # Restart service if it was previously running
                if ($data.previous_running -eq $true) {
                    Start-Service -Name $svcName -ErrorAction Stop
                    Write-UndoLog "Started service $svcName (was previously running)" "OK"
                }

                $successCount++
            } catch {
                Write-UndoLog "FAILED to revert service $svcName : $_" "ERROR"
                $failCount++
            }
        }

        # --- App removal (re-install would be needed, just log) ---
        "app_remove" {
            if ($DryRun) {
                Write-UndoLog "[DRY RUN] Would note: reinstall $desc" "INFO"
                $skipCount++
                continue
            }
            Write-UndoLog "Cannot auto-reinstall: $desc (manual action required)" "WARN"
            $skipCount++
        }

        # --- File changes ---
        "file" {
            $filePath = $data.path

            if ($DryRun) {
                if ($data.action -eq "created") {
                    Write-UndoLog "[DRY RUN] Would remove file: $filePath" "INFO"
                } elseif ($data.action -eq "modified") {
                    Write-UndoLog "[DRY RUN] Would restore file: $filePath" "INFO"
                }
                $skipCount++
                continue
            }

            try {
                if ($data.action -eq "created" -and (Test-Path $filePath)) {
                    Remove-Item $filePath -Force -ErrorAction Stop
                    Write-UndoLog "Removed file: $filePath" "OK"
                    $successCount++
                } elseif ($data.action -eq "modified" -and $data.backup_path -and (Test-Path $data.backup_path)) {
                    Copy-Item $data.backup_path $filePath -Force -ErrorAction Stop
                    Write-UndoLog "Restored file from backup: $filePath" "OK"
                    $successCount++
                } else {
                    Write-UndoLog "Cannot revert file change: $filePath (no backup available)" "WARN"
                    $skipCount++
                }
            } catch {
                Write-UndoLog "FAILED to revert file $filePath : $_" "ERROR"
                $failCount++
            }
        }

        # --- Windows feature ---
        "feature" {
            $featureName = $data.name

            if ($DryRun) {
                $action = if ($data.previous_enabled) { "re-enable" } else { "disable" }
                Write-UndoLog "[DRY RUN] Would $action feature: $featureName" "INFO"
                $skipCount++
                continue
            }

            try {
                if ($data.previous_enabled -eq $true) {
                    Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop | Out-Null
                    Write-UndoLog "Re-enabled feature: $featureName" "OK"
                } else {
                    Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop | Out-Null
                    Write-UndoLog "Disabled feature: $featureName" "OK"
                }
                $successCount++
            } catch {
                Write-UndoLog "FAILED to revert feature $featureName : $_" "ERROR"
                $failCount++
            }
        }

        default {
            Write-UndoLog "Unknown entry type '$type' - skipping: $desc" "WARN"
            $skipCount++
        }
    }
}

# ============================================================================
# Final Report
# ============================================================================

Write-Host ""
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "   Undo Complete" -ForegroundColor White
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host ""
if ($DryRun) {
    Write-Host "  [DRY RUN] No changes were made." -ForegroundColor Yellow
    Write-Host "  Run without -DryRun to apply." -ForegroundColor Gray
} else {
    Write-Host "  Reverted:  $successCount" -ForegroundColor Green
    Write-Host "  Failed:    $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Skipped:   $skipCount" -ForegroundColor $(if ($skipCount -gt 0) { "Yellow" } else { "Gray" })
}
Write-Host ""
Write-Host "  Log: $LogFile" -ForegroundColor Gray
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "  Some entries failed to revert. Check the log for details." -ForegroundColor Yellow
    Write-Host "  A System Restore to 'WinInit Pre-Install' may be needed." -ForegroundColor Yellow
    Write-Host ""
}

Write-UndoLog "Undo finished: $successCount reverted, $failCount failed, $skipCount skipped" "INFO"
