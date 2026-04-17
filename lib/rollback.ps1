# ============================================================================
# WinInit - Rollback System
# Records all changes for later reversal via undo.ps1
# ============================================================================

$script:RollbackFile    = Join-Path $PSScriptRoot "..\rollback.json"
$script:RollbackEntries = @()

function Initialize-Rollback {
    # Load existing rollback data or start fresh
    if (Test-Path $script:RollbackFile) {
        try {
            $existing = Get-Content $script:RollbackFile -Raw | ConvertFrom-Json
            $script:RollbackEntries = @($existing)
            Write-Log "Loaded $($script:RollbackEntries.Count) existing rollback entries" "DEBUG"
        } catch {
            Write-Log "Rollback file corrupt, starting fresh: $_" "WARN"
            $script:RollbackEntries = @()
        }
    } else {
        $script:RollbackEntries = @()
    }
}

function Add-RollbackEntry {
    param(
        [string]$Type,        # "registry", "service", "app_remove", "file", "feature"
        [string]$Description,
        [hashtable]$Data      # Type-specific data for reversal
    )
    $entry = @{
        type        = $Type
        description = $Description
        timestamp   = (Get-Date).ToString("o")
        module      = $script:SectionName
        data        = $Data
    }
    $script:RollbackEntries += $entry
}

function Save-Rollback {
    # Called periodically and at end to persist rollback data
    if ($script:RollbackEntries.Count -gt 0) {
        try {
            $script:RollbackEntries | ConvertTo-Json -Depth 10 | Set-Content -Path $script:RollbackFile -Encoding UTF8
            Write-Log "Rollback data saved ($($script:RollbackEntries.Count) entries)" "DEBUG"
        } catch {
            Write-Log "Failed to save rollback data: $_" "WARN"
        }
    }
}

# ============================================================================
# Rollback-aware wrappers
# ============================================================================

function Set-RegistryWithRollback {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord",
        [string]$Description = ""
    )
    # Capture current state for rollback
    $currentValue = $null
    $existed = $false
    try {
        if (Test-Path $Path) {
            $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $current) {
                $currentValue = $current.$Name
                $existed = $true
            }
        }
    } catch {}

    # Record rollback entry
    $desc = if ($Description) { $Description } else { "$Path\$Name" }
    Add-RollbackEntry -Type "registry" -Description $desc -Data @{
        path             = $Path
        name             = $Name
        previous_value   = $currentValue
        previous_existed = $existed
        new_value        = $Value
        type             = $Type
    }

    # Actually set the value (delegate to existing function)
    Set-RegistrySafe -Path $Path -Name $Name -Value $Value -Type $Type
}

function Set-ServiceWithRollback {
    param(
        [string]$Name,
        [string]$NewStartType = "Disabled",
        [switch]$Stop
    )
    # Capture current state
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        $previousStart = $null
        try {
            $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
            if ($wmiSvc) { $previousStart = $wmiSvc.StartMode }
        } catch {}
        $previousRunning = $svc.Status -eq "Running"

        Add-RollbackEntry -Type "service" -Description "Service: $Name" -Data @{
            name                = $Name
            previous_start_type = $previousStart
            previous_running    = $previousRunning
            new_start_type      = $NewStartType
        }
    }

    if ($Stop) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Name -StartupType $NewStartType -ErrorAction SilentlyContinue
}
