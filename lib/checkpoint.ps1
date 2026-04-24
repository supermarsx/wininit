# ============================================================================
# WinInit - Checkpoint / Resume System
# Saves execution state to allow resuming after reboot or Ctrl+C
# ============================================================================

$script:CheckpointFile = Join-Path $PSScriptRoot "..\checkpoint.json"

function Save-Checkpoint {
    param(
        [int]$LastCompletedModule,     # Index of last successfully completed module
        [string]$LastModuleFile,       # e.g. "06-Debloat.ps1"
        [string]$Status,               # "in_progress", "paused", "rebooting"
        [hashtable]$ExtraData = @{}    # Any additional state to persist
    )
    $checkpoint = @{
        version               = 1
        timestamp             = (Get-Date).ToString("o")
        last_completed_module = $LastCompletedModule
        last_module_file      = $LastModuleFile
        status                = $Status
        user                  = $env:USERNAME
        computer              = $env:COMPUTERNAME
        pid                   = $PID
        extra                 = $ExtraData
    }
    try {
        $checkpoint | ConvertTo-Json -Depth 5 | Set-Content -Path $script:CheckpointFile -Encoding UTF8
        Write-Log "Checkpoint saved: module $LastCompletedModule ($LastModuleFile) - $Status" "DEBUG"
    } catch {
        Write-Log "Failed to save checkpoint: $_" "WARN"
    }
}

function Get-Checkpoint {
    if (-not (Test-Path $script:CheckpointFile)) { return $null }
    try {
        $data = Get-Content $script:CheckpointFile -Raw | ConvertFrom-Json
        return $data
    } catch {
        Write-Log "Checkpoint file corrupt, ignoring: $_" "WARN"
        return $null
    }
}

function Remove-Checkpoint {
    if (Test-Path $script:CheckpointFile) {
        Remove-Item $script:CheckpointFile -Force
        Write-Log "Checkpoint cleared" "DEBUG"
    }
}

function Register-RebootResume {
    # Register a RunOnce key to resume WinInit after reboot
    param([string]$ScriptPath)
    try {
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Resume"
        Set-ItemProperty -Path $runOncePath -Name "WinInitResume" -Value $cmd -Type String
        Write-Log "Registered RunOnce resume key" "INFO"
    } catch {
        Write-Log "Failed to register RunOnce resume key: $_" "WARN"
    }
}

function Unregister-RebootResume {
    try {
        $runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        Remove-ItemProperty -Path $runOncePath -Name "WinInitResume" -ErrorAction SilentlyContinue
        Write-Log "Removed RunOnce resume key" "DEBUG"
    } catch {
        Write-Log "Failed to remove RunOnce resume key: $_" "WARN"
    }
}
