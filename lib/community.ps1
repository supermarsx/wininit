# ============================================================================
# WinInit - Community Module Loader
# Discovers and loads user-created modules from modules/community/
# ============================================================================

$script:CommunityModulesDir = Join-Path $PSScriptRoot "..\modules\community"

function Get-CommunityModules {
    <#
    .SYNOPSIS
        Returns an array of community module hashtables matching the same format
        as built-in modules (file, desc, community keys).
    .DESCRIPTION
        Scans modules/community/ for .ps1 files (excluding _template.ps1),
        extracts the first comment line as a description, and returns module
        definitions compatible with the main module loop in init.ps1.
    #>
    $communityModules = @()

    if (-not (Test-Path $script:CommunityModulesDir)) {
        New-Item -ItemType Directory -Path $script:CommunityModulesDir -Force | Out-Null
        return $communityModules
    }

    $communityFiles = Get-ChildItem -Path $script:CommunityModulesDir -Filter "*.ps1" -File |
        Where-Object { $_.Name -ne "_template.ps1" } |
        Sort-Object Name

    foreach ($file in $communityFiles) {
        # Try to extract description from first comment line
        $firstLine = Get-Content $file.FullName -TotalCount 1 -ErrorAction SilentlyContinue
        $desc = if ($firstLine -match "^#\s*(.+)") { $Matches[1] } else { "Community module: $($file.BaseName)" }

        $communityModules += @{
            file      = "community\$($file.Name)"
            desc      = "[Community] $desc"
            community = $true
        }
    }

    return $communityModules
}

function Test-CommunityModule {
    <#
    .SYNOPSIS
        Basic validation of a community module before execution.
    .DESCRIPTION
        Scans the module content for dangerous patterns that could cause
        data loss or security issues. Returns $true if the module passes
        validation, $false if it contains blocked patterns.
    .PARAMETER Path
        Full path to the community module .ps1 file.
    #>
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Log "Community module not found: $Path" "ERROR"
        return $false
    }

    $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Log "Community module is empty: $Path" "WARN"
        return $false
    }

    # Safety checks: block patterns that could cause catastrophic damage
    $dangerous = @(
        @{ Pattern = "Format-Volume";                        Desc = "disk formatting" }
        @{ Pattern = "Remove-Partition";                     Desc = "partition removal" }
        @{ Pattern = "Clear-Disk";                           Desc = "disk wiping" }
        @{ Pattern = "Initialize-Disk";                      Desc = "disk initialization" }
        @{ Pattern = "Remove-Item.*-Recurse.*C:\\Windows";   Desc = "Windows directory deletion" }
        @{ Pattern = "Remove-Item.*-Recurse.*C:\\Users";     Desc = "Users directory deletion" }
        @{ Pattern = "Remove-Item.*-Recurse.*C:\\Program";   Desc = "Program Files directory deletion" }
        @{ Pattern = "Invoke-Expression.*http";              Desc = "remote code execution via iex" }
        @{ Pattern = "iex.*http";                            Desc = "remote code execution via iex" }
        @{ Pattern = "DownloadString.*http(?!s)";            Desc = "insecure HTTP download" }
        @{ Pattern = "Net\.WebClient.*Download.*http(?!s)";  Desc = "insecure HTTP download" }
        @{ Pattern = "Disable-BitLocker";                    Desc = "BitLocker decryption" }
        @{ Pattern = "bcdedit.*deletevalue";                 Desc = "boot configuration deletion" }
        @{ Pattern = "reg\s+delete.*\\\\Windows\\\\";        Desc = "Windows registry deletion via reg.exe" }
    )

    foreach ($check in $dangerous) {
        if ($content -match $check.Pattern) {
            Write-Log "Community module BLOCKED: '$($check.Desc)' detected in $(Split-Path $Path -Leaf)" "ERROR"
            Write-Log "  Matched pattern: $($check.Pattern)" "ERROR"
            return $false
        }
    }

    # Warn about potentially risky (but allowed) operations
    $warnings = @(
        @{ Pattern = "Stop-Service";              Desc = "stops a Windows service" }
        @{ Pattern = "Set-Service.*Disabled";     Desc = "disables a Windows service" }
        @{ Pattern = "Invoke-WebRequest";         Desc = "downloads files from the internet" }
        @{ Pattern = "Start-Process.*-Verb.*Run"; Desc = "starts a process" }
    )

    foreach ($check in $warnings) {
        if ($content -match $check.Pattern) {
            Write-Log "Community module note: $($check.Desc) in $(Split-Path $Path -Leaf)" "DEBUG"
        }
    }

    return $true
}

function Invoke-CommunityModules {
    <#
    .SYNOPSIS
        Discovers, validates, and executes all community modules.
    .DESCRIPTION
        Called from init.ps1 after all built-in modules have completed.
        Each community module is validated before execution. Failed
        validations are logged but do not halt the overall process.
    #>
    $communityModules = Get-CommunityModules

    if ($communityModules.Count -eq 0) {
        Write-Log "No community modules found" "DEBUG"
        return @()
    }

    Write-Log "Found $($communityModules.Count) community module(s)" "INFO"
    $results = @()

    foreach ($mod in $communityModules) {
        $modPath = Join-Path (Split-Path $script:CommunityModulesDir -Parent) $mod.file
        $modStart = Get-Date

        Write-Log "Validating community module: $($mod.file)" "INFO"

        if (-not (Test-CommunityModule -Path $modPath)) {
            Write-Log "Skipped community module (failed validation): $($mod.file)" "WARN"
            $results += @{ name = $mod.file; status = "BLOCKED"; duration = [timespan]::Zero }
            continue
        }

        Write-Log "Running community module: $($mod.file) - $($mod.desc)" "INFO"

        try {
            . $modPath
            $modDuration = (Get-Date) - $modStart
            Write-Log "Community module completed: $($mod.file) ($("{0:N1}s" -f $modDuration.TotalSeconds))" "OK"
            $results += @{ name = $mod.file; status = "OK"; duration = $modDuration }
        } catch {
            $modDuration = (Get-Date) - $modStart
            $errorMsg = $_.Exception.Message
            Write-Log "Community module FAILED: $($mod.file) - $errorMsg" "ERROR"
            Write-Log "  At line: $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
            $results += @{ name = $mod.file; status = "FAIL"; duration = $modDuration }
        }
    }

    return $results
}
