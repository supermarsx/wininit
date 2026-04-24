# ============================================================================
# WinInit - Progress Dashboard
# Persistent status line showing overall weighted progress, ETA, and stats
# ============================================================================

# --- Module Weight Table (relative execution time) ---
$script:ModuleWeights = @{
    "01-PackageManagers"    = 2
    "02-Applications"       = 15    # Heaviest - 50+ app installs
    "03-DesktopEnvironment" = 3
    "04-OneDriveRemoval"    = 2
    "05-Performance"        = 1
    "06-Debloat"            = 4
    "07-Privacy"            = 2
    "08-QualityOfLife"      = 3
    "09-Services"           = 2
    "10-NetworkPerformance" = 1
    "11-VisualUX"           = 1
    "12-SecurityHardening"  = 8     # Windows features take time
    "13-BrowserExtensions"  = 3
    "14-DevTools"           = 12    # Large downloads
    "15-PortableTools"      = 8     # Many GitHub downloads
    "16-UnixEnvironment"    = 6     # Cygwin is slow
    "17-VSCodeSetup"        = 5     # Many extensions
    "18-FinalConfig"        = 3
}

# --- Dashboard State ---
$script:DashboardState = @{
    StartTime       = $null
    CurrentModule   = 0
    TotalModules    = 18
    CurrentModuleName = ""
    CompletedWeight = 0
    TotalWeight     = 0
    ModuleStartTime = $null
    Errors          = 0
    Warnings        = 0
    ModuleResults   = @()    # Track per-module status for summary
}

# ============================================================================
# Initialize-Dashboard
# Call once before the module loop begins
# ============================================================================

function Initialize-Dashboard {
    param([int]$TotalModules = 18)

    $script:DashboardState.StartTime     = Get-Date
    $script:DashboardState.TotalModules  = $TotalModules
    $script:DashboardState.CurrentModule = 0
    $script:DashboardState.CompletedWeight = 0
    $script:DashboardState.Errors        = 0
    $script:DashboardState.Warnings      = 0
    $script:DashboardState.ModuleResults = @()
    $script:DashboardState.TotalWeight   = 0

    foreach ($w in $script:ModuleWeights.Values) {
        $script:DashboardState.TotalWeight += $w
    }
}

# ============================================================================
# Update-Dashboard
# Call at the start/end of each module to update state and display
# ============================================================================

function Update-Dashboard {
    param(
        [int]$ModuleIndex,
        [string]$ModuleName,
        [ValidateSet("running", "completed", "failed", "skipped")]
        [string]$Status = "running"
    )

    $state = $script:DashboardState
    $state.CurrentModule = $ModuleIndex
    $state.CurrentModuleName = $ModuleName

    if ($Status -eq "running") {
        $state.ModuleStartTime = Get-Date
    }

    if ($Status -eq "completed" -or $Status -eq "failed" -or $Status -eq "skipped") {
        # Accumulate completed weight
        $modKey = $script:ModuleWeights.Keys | Where-Object { $ModuleName -match $_ } | Select-Object -First 1
        if (-not $modKey) {
            # Try matching by the numeric prefix (e.g., "01-" from "01-PackageManagers.ps1")
            $prefix = if ($ModuleName -match '^(\d{2}-[^.]+)') { $Matches[1] } else { "" }
            $modKey = $script:ModuleWeights.Keys | Where-Object { $_ -eq $prefix } | Select-Object -First 1
        }
        if ($modKey) {
            $state.CompletedWeight += $script:ModuleWeights[$modKey]
        }

        # Track errors/warnings
        if ($Status -eq "failed") { $state.Errors++ }

        # Record result
        $modDuration = if ($state.ModuleStartTime) { (Get-Date) - $state.ModuleStartTime } else { [timespan]::Zero }
        $state.ModuleResults += @{
            Index    = $ModuleIndex
            Name     = $ModuleName
            Status   = $Status
            Duration = $modDuration
        }
    }

    Show-Dashboard
}

# ============================================================================
# Show-Dashboard
# Renders the progress dashboard line to the console
# ============================================================================

function Show-Dashboard {
    $state = $script:DashboardState
    if (-not $state.StartTime) { return }

    $elapsed = (Get-Date) - $state.StartTime
    $elapsedStr = "{0:hh\:mm\:ss}" -f $elapsed

    # --- Weighted percentage ---
    $totalWeight = [math]::Max(1, $state.TotalWeight)
    $pct = [math]::Min(100, [math]::Round(($state.CompletedWeight / $totalWeight) * 100))

    # --- ETA calculation ---
    $etaStr = "calculating..."
    if ($pct -gt 5 -and $elapsed.TotalSeconds -gt 30) {
        $totalEstimate = $elapsed.TotalSeconds / ($pct / 100)
        $remaining = [math]::Max(0, $totalEstimate - $elapsed.TotalSeconds)
        $etaTs = [timespan]::FromSeconds($remaining)
        $etaStr = "{0:hh\:mm\:ss}" -f $etaTs
    }

    # --- Build progress bar ---
    $barWidth = 30
    $filled = [math]::Round($barWidth * $pct / 100)
    $empty  = $barWidth - $filled
    $barFill  = ([char]0x2588).ToString() * $filled
    $barEmpty = ([char]0x2591).ToString() * $empty
    $bar = "$barFill$barEmpty"

    # --- Friendly module name (strip .ps1 extension) ---
    $displayName = $state.CurrentModuleName -replace '\.ps1$', ''

    # --- Error/warning indicator ---
    $errStr = ""
    if ($state.Errors -gt 0) {
        $errStr = " | Err: $($state.Errors)"
    }

    if ($script:VTEnabled) {
        $c = Get-C
        $barColor = if ($pct -lt 33) { $c.Red } elseif ($pct -lt 66) { $c.Yellow } else { $c.Green }
        $errColor = if ($state.Errors -gt 0) { $c.BrRed } else { "" }

        $line  = "  $($c.Gray)[$($c.Reset)"
        $line += "${barColor}${bar}$($c.Reset)"
        $line += "$($c.Gray)]$($c.Reset) "
        $line += "$($c.BrWhite)${pct}%$($c.Reset) "
        $line += "$($c.Gray)Module $($state.CurrentModule)/$($state.TotalModules)$($c.Reset) "
        $line += "$($c.Cyan)${displayName}$($c.Reset) "
        $line += "$($c.Gray)| Elapsed: $($c.BrWhite)$elapsedStr$($c.Reset) "
        $line += "$($c.Gray)| ETA: $($c.BrYellow)$etaStr$($c.Reset)"
        if ($errStr) {
            $line += " ${errColor}${errStr}$($c.Reset)"
        }
        [Console]::WriteLine($line)
    } else {
        $line = "  [$bar] ${pct}% Module $($state.CurrentModule)/$($state.TotalModules) $displayName | Elapsed: $elapsedStr | ETA: $etaStr$errStr"
        Write-Host $line -ForegroundColor Cyan
    }
}

# ============================================================================
# Write-DashboardSummary
# Called at the very end - generates a rich completion summary
# ============================================================================

function Write-DashboardSummary {
    $state = $script:DashboardState
    if (-not $state.StartTime) { return }

    $totalDuration = (Get-Date) - $state.StartTime
    $durationStr = "{0:hh\:mm\:ss}" -f $totalDuration

    $completed = ($state.ModuleResults | Where-Object { $_.Status -eq "completed" }).Count
    $failedMods = ($state.ModuleResults | Where-Object { $_.Status -eq "failed" }).Count
    $skippedMods = ($state.ModuleResults | Where-Object { $_.Status -eq "skipped" }).Count

    # --- Log summary to file ---
    Add-Content -Path $script:LogFile -Value ""
    Add-Content -Path $script:LogFile -Value ("=" * 70)
    Add-Content -Path $script:LogFile -Value "DASHBOARD SUMMARY"
    Add-Content -Path $script:LogFile -Value ("-" * 70)
    Add-Content -Path $script:LogFile -Value "  Total duration: $durationStr"
    Add-Content -Path $script:LogFile -Value "  Completed: $completed  Failed: $failedMods  Skipped: $skippedMods"
    Add-Content -Path $script:LogFile -Value ("-" * 70)

    foreach ($mr in $state.ModuleResults) {
        $durStr = if ($mr.Duration.TotalSeconds -gt 0) { "{0:N1}s" -f $mr.Duration.TotalSeconds } else { "---" }
        $statusTag = $mr.Status.ToUpper().PadRight(9)
        Add-Content -Path $script:LogFile -Value "  $($mr.Name.PadRight(35)) $($durStr.PadLeft(8)) $statusTag"
    }
    Add-Content -Path $script:LogFile -Value ("=" * 70)

    # --- Console summary ---
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("")
        [Console]::WriteLine("  $($c.Bold)$($c.BrCyan)Dashboard Summary$($c.Reset)")
        [Console]::WriteLine("  $($c.Cyan)$("-" * 60)$($c.Reset)")
        [Console]::WriteLine("  $($c.Gray)Total Duration:$($c.Reset) $($c.BrWhite)$durationStr$($c.Reset)")
        [Console]::WriteLine("  $($c.BrGreen)Completed: $completed$($c.Reset)  $($c.BrRed)Failed: $failedMods$($c.Reset)  $($c.BrYellow)Skipped: $skippedMods$($c.Reset)")
        [Console]::WriteLine("  $($c.Cyan)$("-" * 60)$($c.Reset)")

        # Per-module breakdown
        foreach ($mr in $state.ModuleResults) {
            $durStr = if ($mr.Duration.TotalSeconds -gt 0) { "{0:N1}s" -f $mr.Duration.TotalSeconds } else { "---" }
            $color = switch ($mr.Status) {
                "completed" { $c.BrGreen }
                "failed"    { $c.BrRed }
                "skipped"   { $c.BrYellow }
                default     { $c.Gray }
            }
            $icon = switch ($mr.Status) {
                "completed" { "[+]" }
                "failed"    { "[-]" }
                "skipped"   { "[~]" }
                default     { "[?]" }
            }
            $name = ($mr.Name -replace '\.ps1$', '').PadRight(35)
            [Console]::WriteLine("  ${color}${icon} ${name} $($durStr.PadLeft(8))$($c.Reset)")
        }

        [Console]::WriteLine("  $($c.Cyan)$("-" * 60)$($c.Reset)")
        [Console]::WriteLine("")
    } else {
        Write-Host ""
        Write-Host "  Dashboard Summary" -ForegroundColor Cyan
        Write-Host "  $("-" * 60)" -ForegroundColor Cyan
        Write-Host "  Total Duration: $durationStr" -ForegroundColor White
        Write-Host "  Completed: $completed  Failed: $failedMods  Skipped: $skippedMods" -ForegroundColor Gray
        Write-Host "  $("-" * 60)" -ForegroundColor Cyan

        foreach ($mr in $state.ModuleResults) {
            $durStr = if ($mr.Duration.TotalSeconds -gt 0) { "{0:N1}s" -f $mr.Duration.TotalSeconds } else { "---" }
            $color = switch ($mr.Status) {
                "completed" { "Green" }
                "failed"    { "Red" }
                "skipped"   { "Yellow" }
                default     { "Gray" }
            }
            $icon = switch ($mr.Status) {
                "completed" { "[+]" }
                "failed"    { "[-]" }
                "skipped"   { "[~]" }
                default     { "[?]" }
            }
            $name = ($mr.Name -replace '\.ps1$', '').PadRight(35)
            Write-Host "  $icon $name $($durStr.PadLeft(8))" -ForegroundColor $color
        }

        Write-Host "  $("-" * 60)" -ForegroundColor Cyan
        Write-Host ""
    }
}
