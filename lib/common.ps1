# ============================================================================
# WinInit - Shared Library
# Common functions used by all modules
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# --- Globals ---
$script:LogFile     = Join-Path $PSScriptRoot "..\wininit.log"
$script:TotalSteps  = 0
$script:CurrentStep = 0
$script:SectionName = ""
$script:VTEnabled   = $false
$script:SpinnerJob  = $null
$script:SpinnerFrames = @('|', '/', '-', '\')

# ============================================================================
# ANSI / Virtual Terminal Color Support
# ============================================================================

function Enable-VTMode {
    try {
        $null = Add-Type -Name 'Kernel32VT' -Namespace 'WinInit' -PassThru -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        $hOut = [WinInit.Kernel32VT]::GetStdHandle(-11)
        $mode = [uint32]0
        $null = [WinInit.Kernel32VT]::GetConsoleMode($hOut, [ref]$mode)
        # 0x0004 = ENABLE_VIRTUAL_TERMINAL_PROCESSING
        $null = [WinInit.Kernel32VT]::SetConsoleMode($hOut, $mode -bor 0x0004)
        $script:VTEnabled = $true
    } catch {
        $script:VTEnabled = $false
    }
}

Enable-VTMode

# ANSI escape sequences
# Color map — use $script:Colors (not $c which can be shadowed by dot-sourced modules)
$script:E = [char]27
$script:Colors = @{
    Reset      = "$([char]27)[0m"
    Bold       = "$([char]27)[1m"
    Dim        = "$([char]27)[2m"
    # Foreground
    Red        = "$([char]27)[31m"
    Green      = "$([char]27)[32m"
    Yellow     = "$([char]27)[33m"
    Blue       = "$([char]27)[34m"
    Magenta    = "$([char]27)[35m"
    Cyan       = "$([char]27)[36m"
    White      = "$([char]27)[37m"
    # Bright foreground
    Gray       = "$([char]27)[90m"
    BrRed      = "$([char]27)[91m"
    BrGreen    = "$([char]27)[92m"
    BrYellow   = "$([char]27)[93m"
    BrBlue     = "$([char]27)[94m"
    BrMagenta  = "$([char]27)[95m"
    BrCyan     = "$([char]27)[96m"
    BrWhite    = "$([char]27)[97m"
    # Background
    BgRed      = "$([char]27)[41m"
    BgGreen    = "$([char]27)[42m"
    BgYellow   = "$([char]27)[43m"
}
$script:C = $script:Colors

# Helper: get color map safely (guards against $script:C being overwritten by dot-sourced modules)
function Get-C { if ($script:C -is [hashtable] -and $script:C.Count -gt 5) { return $script:C } else { $script:C = $script:Colors; return $script:Colors } }

# ============================================================================
# Logging - console (colored) + file (plain, verbose)
# ============================================================================

$script:LogLevels = @{
    OK    = @{ Icon = "[+]"; Fg = "Green";    Ansi = "BrGreen";   Tag = "OK   " }
    INFO  = @{ Icon = "[*]"; Fg = "Cyan";     Ansi = "BrCyan";    Tag = "INFO " }
    WARN  = @{ Icon = "[!]"; Fg = "Yellow";   Ansi = "BrYellow";  Tag = "WARN " }
    ERROR = @{ Icon = "[-]"; Fg = "Red";      Ansi = "BrRed";     Tag = "ERROR" }
    STEP  = @{ Icon = "[>]"; Fg = "Magenta";  Ansi = "BrMagenta"; Tag = "STEP " }
    DEBUG = @{ Icon = "[.]"; Fg = "DarkGray"; Ansi = "Gray";      Tag = "DEBUG" }
    FATAL = @{ Icon = "[X]"; Fg = "Red";      Ansi = "BrRed";     Tag = "FATAL" }
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $cfg = $script:LogLevels[$Level]
    if (-not $cfg) { $cfg = $script:LogLevels["INFO"] }

    if ($script:SpinnerSync.Active) {
        if ($Level -in @("INFO", "DEBUG")) {
            # Silent levels: just update spinner message
            $script:SpinnerSync.Message = $Message
        } else {
            # Visible levels (OK, WARN, ERROR, FATAL, STEP): print through the spinner
            # Pause spinner to avoid race condition, clear line, print, resume
            $script:SpinnerSync.Paused = $true
            Start-Sleep -Milliseconds 150
            $pad = " " * 100
            try { [Console]::Write("`r$pad`r") } catch {}
            if ($script:VTEnabled) {
                $c = Get-C
                $ac = if ($c -is [hashtable]) { $c[$cfg.Ansi] } else { "" }
                [Console]::WriteLine("    $ac$($cfg.Icon)$($c.Reset) $($c.White)$Message$($c.Reset)")
            } else {
                Write-Host "    $($cfg.Icon) $Message" -ForegroundColor $cfg.Fg
            }
            $script:SpinnerSync.Paused = $false
        }
    } else {
        # No spinner: normal console output with timestamp
        if ($script:VTEnabled) {
            $c = Get-C
            $ac = if ($c -is [hashtable]) { $c[$cfg.Ansi] } else { "" }
            [Console]::WriteLine("$($c.Gray)$ts$($c.Reset) $ac$($cfg.Icon)$($c.Reset) $ac$Message$($c.Reset)")
        } else {
            Write-Host "$ts $($cfg.Icon) $Message" -ForegroundColor $cfg.Fg
        }
    }

    # File output (always, regardless of spinner state)
    $fileEntry = "[$ts] [$($cfg.Tag)] $Message"
    if ($script:SectionName) {
        $fileEntry = "[$ts] [$($cfg.Tag)] [$($script:SectionName)] $Message"
    }
    Add-Content -Path $script:LogFile -Value $fileEntry
}

# ============================================================================
# Section Header
# ============================================================================

function Write-Section {
    param(
        [string]$Name,
        [string]$Description = "",
        [int]$ItemCount = 0     # If >0, shows progress bar (e.g., number of apps to install)
    )
    $script:SectionName = $Name
    $script:CurrentStep++
    $pct = [math]::Max(0, [math]::Min(100, [math]::Round(($script:CurrentStep / [math]::Max(1, $script:TotalSteps)) * 100)))
    $step = "[$($script:CurrentStep)/$($script:TotalSteps)]"

    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("")
        [Console]::WriteLine("  $($c.BrCyan)$step$($c.Reset) $($c.Bold)$($c.BrWhite)$Name$($c.Reset)")
        if ($Description) {
            [Console]::WriteLine("        $($c.Gray)$Description$($c.Reset)")
        }
    } else {
        Write-Host ""
        Write-Host "  $step " -ForegroundColor Cyan -NoNewline
        Write-Host $Name -ForegroundColor White
        if ($Description) {
            Write-Host "        $Description" -ForegroundColor Gray
        }
    }

    Write-ProgressBar -Percent $pct -Label "Step $($script:CurrentStep) of $($script:TotalSteps)"
    Write-Host ""

    # File log: section divider
    $sep = "=" * 70
    Add-Content -Path $script:LogFile -Value ""
    Add-Content -Path $script:LogFile -Value $sep
    Add-Content -Path $script:LogFile -Value "$step $Name - $Description"
    Add-Content -Path $script:LogFile -Value $sep

    # Start a section-level spinner that shows current activity
    # All Write-Log calls within this section will update the spinner message
    # If ItemCount is set, shows a progress bar
    Start-Spinner "$Name..." -Total $ItemCount
}

# ============================================================================
# Progress Bar
# ============================================================================

function Write-ProgressBar {
    param([int]$Percent, [string]$Label = "Progress")
    $Percent = [math]::Max(0, [math]::Min(100, $Percent))
    $barWidth = 50
    $filled = [math]::Max(0, [math]::Min($barWidth, [math]::Round($barWidth * $Percent / 100)))
    $empty  = $barWidth - $filled
    $bar    = ("#" * $filled) + ("-" * $empty)

    if ($script:VTEnabled) {
        $c = Get-C
        $barColor = if ($Percent -lt 33) { $c.Red } elseif ($Percent -lt 66) { $c.Yellow } else { $c.Green }
        $pctStr = "$Percent%".PadLeft(4)
        [Console]::WriteLine("  ${barColor}${bar}$($c.Reset) $($c.BrWhite)${pctStr}$($c.Reset) $($c.Gray)$Label$($c.Reset)")
    } else {
        $color = if ($Percent -lt 33) { "Red" } elseif ($Percent -lt 66) { "Yellow" } else { "Green" }
        Write-Host "  " -NoNewline
        Write-Host $bar -ForegroundColor $color -NoNewline
        Write-Host " $Percent% $Label" -ForegroundColor Gray
    }
}

# ============================================================================
# Sub-step
# ============================================================================

function Write-SubStep {
    param([string]$Message)
    # If spinner is active, just update its message instead of printing a new line
    if ($script:SpinnerSync.Active) {
        $script:SpinnerSync.Message = $Message
    } else {
        if ($script:VTEnabled) {
            $c = Get-C
            [Console]::WriteLine("    $($c.Gray)>$($c.Reset) $($c.White)$Message$($c.Reset)")
        } else {
            Write-Host "    > " -ForegroundColor DarkGray -NoNewline
            Write-Host $Message -ForegroundColor White
        }
    }
    Write-Log $Message "DEBUG"
}

# ============================================================================
# Activity Spinner (live animated via background runspace)
# ============================================================================

$script:SpinnerRunspace = $null
$script:SpinnerPipe = $null
$script:SpinnerSync = [hashtable]::Synchronized(@{
    Active = $false
    Message = ""
    StartTime = $null
    Progress = 0     # Current item number
    Total = 0        # Total items (0 = no progress bar)
})

function Start-Spinner {
    param(
        [string]$Message,
        [int]$Total = 0    # If >0, shows a progress bar
    )

    # Stop any existing spinner first
    if ($script:SpinnerSync.Active) { Stop-Spinner }

    $script:SpinnerSync.Active = $true
    $script:SpinnerSync.Paused = $false
    $script:SpinnerSync.Message = $Message
    $script:SpinnerSync.StartTime = Get-Date
    $script:SpinnerSync.Progress = 0
    $script:SpinnerSync.Total = $Total

    # Create a background runspace that animates the spinner + progress bar
    $script:SpinnerRunspace = [runspacefactory]::CreateRunspace()
    $script:SpinnerRunspace.ApartmentState = "STA"
    $script:SpinnerRunspace.Open()
    $script:SpinnerRunspace.SessionStateProxy.SetVariable("sync", $script:SpinnerSync)

    $script:SpinnerPipe = [powershell]::Create().AddScript({
        $frames = @('|', '/', '-', '\')
        $idx = 0
        while ($sync.Active) {
            if ($sync.Paused) { Start-Sleep -Milliseconds 50; continue }
            $f = $frames[$idx % 4]
            $msg = $sync.Message
            $elapsed = "{0:N0}s" -f ((Get-Date) - $sync.StartTime).TotalSeconds
            $total = $sync.Total
            $progress = $sync.Progress

            if ($total -gt 0) {
                # Show progress bar: [####----] 12/50 42% | msg [5s]
                $pct = [math]::Min(100, [math]::Round(($progress / $total) * 100))
                $barW = 20
                $filled = [math]::Round($barW * $pct / 100)
                $empty = $barW - $filled
                $bar = ("#" * $filled) + ("-" * $empty)
                if ($msg.Length -gt 35) { $msg = $msg.Substring(0, 32) + "..." }
                $line = "    $f [$bar] $progress/$total ${pct}% $msg [$elapsed]"
            } else {
                if ($msg.Length -gt 58) { $msg = $msg.Substring(0, 55) + "..." }
                $line = "    $f $msg [$elapsed]"
            }
            $padded = $line.PadRight(100)
            try { [Console]::Write("`r$padded") } catch {}
            $idx++
            Start-Sleep -Milliseconds 120
        }
    })
    $script:SpinnerPipe.Runspace = $script:SpinnerRunspace
    $null = $script:SpinnerPipe.BeginInvoke()
}

function Update-SpinnerMessage {
    param([string]$Message)
    $script:SpinnerSync.Message = $Message
}

# Update spinner progress (increment by 1)
function Update-SpinnerProgress {
    param([string]$Message = "")
    $script:SpinnerSync.Progress++
    if ($Message) { $script:SpinnerSync.Message = $Message }
}

# Set spinner progress to a specific value
function Set-SpinnerProgress {
    param([int]$Current, [string]$Message = "")
    $script:SpinnerSync.Progress = $Current
    if ($Message) { $script:SpinnerSync.Message = $Message }
}

function Stop-Spinner {
    param(
        [string]$FinalMessage = "",
        [string]$Status = "OK"
    )

    # Signal the runspace to stop
    $script:SpinnerSync.Active = $false
    Start-Sleep -Milliseconds 150  # Let the runspace finish its last frame

    # Cleanup runspace
    if ($script:SpinnerPipe) {
        try { $script:SpinnerPipe.Stop() } catch {}
        try { $script:SpinnerPipe.Dispose() } catch {}
        $script:SpinnerPipe = $null
    }
    if ($script:SpinnerRunspace) {
        try { $script:SpinnerRunspace.Close() } catch {}
        try { $script:SpinnerRunspace.Dispose() } catch {}
        $script:SpinnerRunspace = $null
    }

    $elapsed = "{0:N1}s" -f ((Get-Date) - $script:SpinnerSync.StartTime).TotalSeconds
    $msg = if ($FinalMessage) { $FinalMessage } else { $script:SpinnerSync.Message }
    if ($msg.Length -gt 58) { $msg = $msg.Substring(0, 55) + "..." }

    $icon = switch ($Status) { "OK" { "+" } "WARN" { "!" } "ERROR" { "-" } default { "+" } }

    if ($script:VTEnabled) {
        $c = Get-C
        $color = switch ($Status) { "OK" { $c.BrGreen } "WARN" { $c.BrYellow } "ERROR" { $c.BrRed } default { $c.BrGreen } }
        [Console]::Write("`r")
        [Console]::WriteLine("    $color[$icon]$($c.Reset) $($c.White)$msg$($c.Reset) $($c.Gray)($elapsed)$($c.Reset)".PadRight(80))
    } else {
        $color = switch ($Status) { "OK" { "Green" } "WARN" { "Yellow" } "ERROR" { "Red" } default { "Green" } }
        Write-Host "`r    [$icon] " -ForegroundColor $color -NoNewline
        Write-Host "$msg " -ForegroundColor White -NoNewline
        Write-Host "($elapsed)".PadRight(20) -ForegroundColor Gray
    }
}

# Run a scriptblock with a live animated spinner
function Invoke-WithSpinner {
    param(
        [string]$Message,
        [scriptblock]$Action,
        [string]$SuccessMessage = "",
        [switch]$ContinueOnError
    )
    Start-Spinner $Message
    try {
        $result = & $Action
        $final = if ($SuccessMessage) { $SuccessMessage } else { $Message }
        Stop-Spinner -FinalMessage $final -Status "OK"
        return $result
    } catch {
        $final = if ($SuccessMessage) { "$SuccessMessage - FAILED" } else { "$Message - FAILED" }
        Stop-Spinner -FinalMessage $final -Status "ERROR"
        if (-not $ContinueOnError) { throw }
        return $null
    }
}

# Run an external command silently with a live spinner
# Use this for anything that writes to stdout (winget, choco, npm, pip, cargo, etc.)
function Invoke-ExternalWithSpinner {
    param(
        [string]$Message,
        [string]$Command,
        [string[]]$Arguments,
        [string]$SuccessMessage = ""
    )
    Start-Spinner $Message
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Command
        $psi.Arguments = $Arguments -join " "
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $final = if ($SuccessMessage) { $SuccessMessage } else { $Message }
        if ($proc.ExitCode -eq 0) {
            Stop-Spinner -FinalMessage $final -Status "OK"
        } else {
            Stop-Spinner -FinalMessage "$final (exit $($proc.ExitCode))" -Status "WARN"
        }
        return @{ ExitCode = $proc.ExitCode; Stdout = $stdout; Stderr = $stderr }
    } catch {
        Stop-Spinner -FinalMessage "$Message - FAILED" -Status "ERROR"
        return @{ ExitCode = -1; Stdout = ""; Stderr = $_.ToString() }
    }
}

# ============================================================================
# Summary Box (colored for VT, fallback for legacy)
# ============================================================================

function Write-SummaryBox {
    param([string]$Title, [string[]]$Lines)

    # Log all summary lines to file
    Add-Content -Path $script:LogFile -Value ""
    Add-Content -Path $script:LogFile -Value ("=" * 70)
    Add-Content -Path $script:LogFile -Value "SUMMARY: $Title"
    Add-Content -Path $script:LogFile -Value ("-" * 70)
    foreach ($line in $Lines) {
        Add-Content -Path $script:LogFile -Value "  $line"
    }
    Add-Content -Path $script:LogFile -Value ("=" * 70)

    # Console output
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("")
        [Console]::WriteLine("  $($c.Bold)$($c.BrGreen)$Title$($c.Reset)")
        [Console]::WriteLine("  $($c.Green)$("-" * $Title.Length)$($c.Reset)")
        foreach ($line in $Lines) {
            if ($line -eq "") {
                [Console]::WriteLine("")
            } elseif ($line -match "^(REBOOT|Failed)") {
                [Console]::WriteLine("  $($c.BrYellow)$line$($c.Reset)")
            } elseif ($line -match "^\s+!") {
                [Console]::WriteLine("  $($c.BrRed)$line$($c.Reset)")
            } else {
                [Console]::WriteLine("  $($c.Cyan)$line$($c.Reset)")
            }
        }
        [Console]::WriteLine("")
    } else {
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor Green
        Write-Host "  $("-" * $Title.Length)" -ForegroundColor Green
        foreach ($line in $Lines) {
            if ($line -eq "") {
                Write-Host ""
            } elseif ($line -match "^(REBOOT|Failed)") {
                Write-Host "  $line" -ForegroundColor Yellow
            } elseif ($line -match "^\s+!") {
                Write-Host "  $line" -ForegroundColor Red
            } else {
                Write-Host "  $line" -ForegroundColor Cyan
            }
        }
        Write-Host ""
    }
}

# ============================================================================
# TUI Utilities
# ============================================================================

# --- Horizontal Rule ---
function Write-Rule {
    param([string]$Char = "-", [int]$Width = 70, [string]$Color = "DarkGray")
    $line = $Char * $Width
    if ($script:VTEnabled) {
        $c = Get-C
        $ansi = switch ($Color) {
            "DarkGray" { $c.Gray }
            "Cyan"     { $c.Cyan }
            "Green"    { $c.Green }
            "Yellow"   { $c.Yellow }
            "Red"      { $c.Red }
            default    { $c.Gray }
        }
        [Console]::WriteLine("  $ansi$line$($c.Reset)")
    } else {
        Write-Host "  $line" -ForegroundColor $Color
    }
}

# --- Status Badge (inline colored label) ---
function Write-Badge {
    param([string]$Label, [string]$Value, [string]$Color = "Cyan")
    if ($script:VTEnabled) {
        $c = Get-C
        $ansi = $c[$Color] ; if (-not $ansi) { $ansi = $c.Cyan }
        [Console]::Write("  $($c.Gray)$Label$($c.Reset) $ansi$Value$($c.Reset)  ")
    } else {
        Write-Host "  $Label " -ForegroundColor Gray -NoNewline
        Write-Host $Value -ForegroundColor $Color -NoNewline
        Write-Host "  " -NoNewline
    }
}

# --- Blank Line ---
function Write-Blank {
    param([int]$Count = 1)
    for ($i = 0; $i -lt $Count; $i++) { Write-Host "" }
}

# --- Header Banner (for script start) ---
function Write-Banner {
    param([string]$Title, [string]$Subtitle = "", [string[]]$Info = @())

    Write-Blank
    if ($script:VTEnabled) {
        $c = Get-C
        $w = 70
        $border = "=" * $w
        [Console]::WriteLine("  $($c.Cyan)$border$($c.Reset)")
        [Console]::WriteLine("")
        # Center the title
        $pad = [math]::Max(0, [math]::Floor(($w - $Title.Length) / 2))
        [Console]::WriteLine("$(" " * ($pad + 2))$($c.Bold)$($c.BrCyan)$Title$($c.Reset)")
        if ($Subtitle) {
            $pad2 = [math]::Max(0, [math]::Floor(($w - $Subtitle.Length) / 2))
            [Console]::WriteLine("$(" " * ($pad2 + 2))$($c.Gray)$Subtitle$($c.Reset)")
        }
        [Console]::WriteLine("")
        foreach ($line in $Info) {
            [Console]::WriteLine("  $($c.Gray)  $line$($c.Reset)")
        }
        [Console]::WriteLine("")
        [Console]::WriteLine("  $($c.Cyan)$border$($c.Reset)")
    } else {
        $border = "=" * 70
        Write-Host "  $border" -ForegroundColor Cyan
        Write-Host ""
        $pad = [math]::Max(0, [math]::Floor((70 - $Title.Length) / 2))
        Write-Host "$(" " * ($pad + 2))$Title" -ForegroundColor White
        if ($Subtitle) {
            $pad2 = [math]::Max(0, [math]::Floor((70 - $Subtitle.Length) / 2))
            Write-Host "$(" " * ($pad2 + 2))$Subtitle" -ForegroundColor Gray
        }
        Write-Host ""
        foreach ($line in $Info) {
            Write-Host "    $line" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  $border" -ForegroundColor Cyan
    }
    Write-Blank
}

# --- Elapsed Time Display ---
function Write-Elapsed {
    param([datetime]$StartTime)
    $elapsed = (Get-Date) - $StartTime
    $str = "{0:hh\:mm\:ss}" -f $elapsed
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::Write("  $($c.Gray)Elapsed: $($c.BrWhite)$str$($c.Reset)")
    } else {
        Write-Host "  Elapsed: " -ForegroundColor Gray -NoNewline
        Write-Host $str -ForegroundColor White -NoNewline
    }
}

# --- Countdown ---
function Write-Countdown {
    param([int]$Seconds = 3, [string]$Message = "Starting in")
    for ($i = $Seconds; $i -gt 0; $i--) {
        if ($script:VTEnabled) {
            $c = Get-C
            [Console]::Write("`r  $($c.Gray)$Message$($c.Reset) $($c.BrYellow)$i$($c.Reset)..  ")
        } else {
            Write-Host "`r  $Message $i..  " -NoNewline
        }
        Start-Sleep -Seconds 1
    }
    if ($script:VTEnabled) {
        [Console]::WriteLine("`r  $($script:C.BrGreen)Go!$($script:C.Reset)              ")
    } else {
        Write-Host "`r  Go!              "
    }
}

# --- Module Start/End markers ---
function Write-ModuleStart {
    param([string]$File, [string]$Description)
    Write-Blank
    Write-Rule -Char "-" -Width 60 -Color "DarkGray"
    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("  $($c.BrWhite)$File$($c.Reset)")
        [Console]::WriteLine("  $($c.Gray)$Description$($c.Reset)")
    } else {
        Write-Host "  $File" -ForegroundColor White
        Write-Host "  $Description" -ForegroundColor Gray
    }
    Write-Rule -Char "-" -Width 60 -Color "DarkGray"
    Write-Blank
}

# --- Completion Sound ---
# ============================================================================
# Windows Terminal Settings - Safe Read/Write/Repair
# ============================================================================

$script:WTSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"

function Strip-JsonComments {
    # Remove JSONC comments (// ...) while preserving strings that contain //
    param([string]$Text)
    $result = [System.Text.StringBuilder]::new()
    $inString = $false
    $escape = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($escape) {
            $null = $result.Append($c)
            $escape = $false
            $i++
            continue
        }
        if ($c -eq '\' -and $inString) {
            $null = $result.Append($c)
            $escape = $true
            $i++
            continue
        }
        if ($c -eq '"') {
            $inString = -not $inString
            $null = $result.Append($c)
            $i++
            continue
        }
        if (-not $inString -and $c -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            # Skip to end of line
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        $null = $result.Append($c)
        $i++
    }
    return $result.ToString()
}

function Read-WTSettings {
    # Safely read WT settings.json, handling JSONC comments, BOM, corruption
    $path = $script:WTSettingsPath
    if (-not (Test-Path $path)) { return $null }

    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if (-not $raw -or $raw.Trim().Length -eq 0) { return $null }

        # Strip BOM
        $raw = $raw.TrimStart([char]0xFEFF)
        # Strip JSONC comments using proper string-aware parser
        $raw = Strip-JsonComments $raw
        # Strip trailing commas before } or ] (common WT corruption)
        $raw = $raw -replace ',\s*([}\]])', '$1'

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        return $parsed
    } catch {
        Write-Log "WT settings.json parse failed ($_), backing up" "WARN"
        $backup = "$path.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $path $backup -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Write-WTSettings {
    param([object]$Config)
    $path = $script:WTSettingsPath
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $json = $Config | ConvertTo-Json -Depth 20

    # Post-process: fix $false serialization — ensure "hidden": false is explicit, not null
    $json = $json -replace '"hidden":\s*null', '"hidden": false'

    # Validate JSON round-trip before writing
    try {
        $null = $json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "Generated WT settings JSON is invalid - aborting write: $_" "ERROR"
        return $false
    }

    # Stop Windows Terminal briefly to prevent FileSystemWatcher race
    $wtProc = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue
    # Don't kill WT — just write atomically and let it reload

    # Atomic write: temp file → delete target → rename temp (NTFS atomic on same volume)
    $tempFile = "$path.wininit.tmp"
    try {
        [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.UTF8Encoding]::new($false))
        # Verify the temp file is valid before replacing
        $verifyJson = [System.IO.File]::ReadAllText($tempFile, [System.Text.Encoding]::UTF8)
        $null = $verifyJson | ConvertFrom-Json -ErrorAction Stop

        # Replace: delete old, rename temp
        if (Test-Path $path) { [System.IO.File]::Delete($path) }
        [System.IO.File]::Move($tempFile, $path)
    } catch {
        # Fallback: direct overwrite
        try {
            [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
        } catch {
            Write-Log "WT settings write failed completely: $_" "ERROR"
            return $false
        }
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    # Post-write verification: re-read and check it's valid
    Start-Sleep -Milliseconds 100
    try {
        $verify = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $null = $verify | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "WT settings corrupted after write - restoring from memory" "ERROR"
        # Emergency: write again directly
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    }

    return $true
}

function Get-WTProfilesList {
    # Build a guaranteed-valid profiles list with explicit boolean values
    $profiles = @(
        [PSCustomObject]@{
            guid        = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
            name        = "PowerShell"
            commandline = "powershell.exe -NoLogo"
            hidden      = [bool]$false
        }
        [PSCustomObject]@{
            guid        = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"
            name        = "PowerShell 7"
            commandline = "pwsh.exe -NoLogo"
            source      = "Windows.Terminal.PowershellCore"
            hidden      = [bool]$false
        }
        [PSCustomObject]@{
            guid        = "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}"
            name        = "Command Prompt"
            commandline = "cmd.exe"
            hidden      = [bool]$false
        }
    )
    return $profiles
}

function Repair-WTSettings {
    # Full validation and repair — ensures valid JSON with visible profiles
    $config = Read-WTSettings
    $repaired = $false

    if (-not $config) {
        Write-Log "WT settings missing or unreadable - creating fresh config" "WARN"
        $config = [PSCustomObject]@{}
        $repaired = $true
    }

    # 1. Ensure defaultProfile
    $hasDefault = $false
    if ($config.PSObject.Properties.Name -contains "defaultProfile" -and $config.defaultProfile) {
        $hasDefault = $true
    }
    if (-not $hasDefault) {
        $config | Add-Member -NotePropertyName "defaultProfile" -NotePropertyValue "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}" -Force
        $repaired = $true
    }

    # 2. Ensure profiles object
    $hasProfiles = $false
    if ($config.PSObject.Properties.Name -contains "profiles" -and $config.profiles) {
        $hasProfiles = $true
    }
    if (-not $hasProfiles) {
        $config | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{}) -Force
        $repaired = $true
    }

    # 3. Ensure profiles.list exists with visible entries
    $existingList = $null
    $hasPropList = $false
    if ($config.profiles -and $config.profiles.PSObject -and $config.profiles.PSObject.Properties.Name -contains "list") {
        $existingList = $config.profiles.list
        $hasPropList = $true
    }

    $hasList = $hasPropList -and $existingList -and @($existingList).Count -gt 0
    $hasVisible = $false
    if ($hasList) {
        foreach ($p in @($existingList)) {
            # Check hidden property carefully — treat missing, $false, and $null as visible
            $isHidden = $false
            if ($p.PSObject.Properties.Name -contains "hidden") {
                $isHidden = $p.hidden -eq $true
            }
            if (-not $isHidden) { $hasVisible = $true; break }
        }
    }

    if (-not $hasList -or -not $hasVisible) {
        $config.profiles | Add-Member -NotePropertyName "list" -NotePropertyValue (Get-WTProfilesList) -Force
        $repaired = $true
    } else {
        # Even if list exists, ensure no profiles have hidden=null (fix borked serialization)
        $fixed = $false
        foreach ($p in @($existingList)) {
            if ($p.PSObject.Properties.Name -contains "hidden" -and $null -eq $p.hidden) {
                $p.hidden = [bool]$false
                $fixed = $true
            }
        }
        if ($fixed) { $repaired = $true }
    }

    if ($repaired) {
        $ok = Write-WTSettings -Config $config
        if ($ok) { Write-Log "WT settings repaired" "OK" }
        else { Write-Log "WT settings repair write failed" "ERROR" }
        return $config
    }

    return $config
}

function Write-CompletionSound {
    param([switch]$Error)
    try {
        if ($Error) {
            [System.Console]::Beep(400, 500)
            [System.Console]::Beep(300, 500)
        } else {
            [System.Console]::Beep(800, 150)
            [System.Console]::Beep(1000, 150)
            [System.Console]::Beep(1200, 300)
        }
    } catch {}
}

# --- Stats Line (key=value pairs on one line) ---
function Write-StatsLine {
    param([hashtable]$Stats)
    Write-Host "  " -NoNewline
    foreach ($key in $Stats.Keys) {
        $val = $Stats[$key]
        if ($script:VTEnabled) {
            $c = Get-C
            [Console]::Write("$($c.Gray)$key=$($c.Reset)$($c.BrWhite)$val$($c.Reset)  ")
        } else {
            Write-Host "$key=" -ForegroundColor Gray -NoNewline
            Write-Host "$val" -ForegroundColor White -NoNewline
            Write-Host "  " -NoNewline
        }
    }
    Write-Host ""
}

# ============================================================================
# Timing Report
# ============================================================================

function Write-TimingReport {
    param([array]$Timings)

    Add-Content -Path $script:LogFile -Value ""
    Add-Content -Path $script:LogFile -Value "MODULE TIMING REPORT"
    Add-Content -Path $script:LogFile -Value ("-" * 70)

    if ($script:VTEnabled) {
        $c = Get-C
        [Console]::WriteLine("")
        [Console]::WriteLine("  $($c.Bold)$($c.BrCyan)Module Timing Report$($c.Reset)")
        [Console]::WriteLine("  $($c.Cyan)$("-" * 60)$($c.Reset)")
    } else {
        Write-Host ""
        Write-Host "  Module Timing Report" -ForegroundColor Cyan
        Write-Host "  $("-" * 60)" -ForegroundColor Cyan
    }

    foreach ($mt in $Timings) {
        $icon    = switch ($mt.status) { "OK" { "[+]" } "FAIL" { "[-]" } "SKIP" { "[~]" } }
        $timeStr = if ($mt.duration.TotalSeconds -gt 0) { "{0:N1}s" -f $mt.duration.TotalSeconds } else { "---" }
        $line    = "$icon $($mt.name.PadRight(38)) $($timeStr.PadLeft(8))  $($mt.status)"

        Add-Content -Path $script:LogFile -Value "  $line"

        if ($script:VTEnabled) {
            $c = Get-C
            $color = switch ($mt.status) { "OK" { $c.BrGreen } "FAIL" { $c.BrRed } "SKIP" { $c.BrYellow } }
            [Console]::WriteLine("  ${color}${line}$($c.Reset)")
        } else {
            $color = switch ($mt.status) { "OK" { "Green" } "FAIL" { "Red" } "SKIP" { "Yellow" } }
            Write-Host "  $line" -ForegroundColor $color
        }
    }

    if ($script:VTEnabled) {
        [Console]::WriteLine("  $($script:C.Cyan)$("-" * 60)$($script:C.Reset)")
    } else {
        Write-Host "  $("-" * 60)" -ForegroundColor Cyan
    }
    Write-Host ""
}

# ============================================================================
# Install with Retry
# ============================================================================

function Install-WithRetry {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [int]$MaxRetries = 2
    )
    for ($i = 0; $i -le $MaxRetries; $i++) {
        try {
            & $Action
            Write-Log "$Name installed successfully" "OK"
            return $true
        } catch {
            if ($i -lt $MaxRetries) {
                Write-Log "$Name failed (attempt $($i+1)/$($MaxRetries+1)): $_  - retrying..." "WARN"
                Start-Sleep -Seconds 3
            } else {
                Write-Log "$Name failed after $($MaxRetries+1) attempts: $_" "ERROR"
                return $false
            }
        }
    }
}

# ============================================================================
# Install App (winget -> choco -> scoop fallback)
# ============================================================================

# Run a command as a child process with fully redirected output (no console leak)
# Uses async reads so the spinner thread can animate while waiting
# Resolves full exe path and passes current environment to child process
function Invoke-Silent {
    param(
        [string]$Exe,
        [string]$Args,
        [int]$TimeoutSeconds = 1600  # ~26 min default timeout per command
    )
    try {
        # Resolve full path for the executable (handles UWP aliases like winget)
        $resolvedExe = $Exe
        $cmdInfo = Get-Command $Exe -ErrorAction SilentlyContinue
        if ($cmdInfo) {
            if ($cmdInfo.Source) { $resolvedExe = $cmdInfo.Source }
            elseif ($cmdInfo.Definition) { $resolvedExe = $cmdInfo.Definition }
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $resolvedExe
        $psi.Arguments = $Args
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        # Pass current PATH to child process (includes runtime additions)
        $psi.EnvironmentVariables["PATH"] = $env:Path

        $proc = [System.Diagnostics.Process]::Start($psi)

        # Use async reads to avoid blocking the main thread
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()

        # Poll for exit with timeout (lets spinner animate)
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not $proc.HasExited) {
            if ((Get-Date) -gt $deadline) {
                try { $proc.Kill() } catch {}
                Write-Log "$Exe timed out after ${TimeoutSeconds}s - killed" "WARN"
                return @{ ExitCode = -2; Output = "TIMEOUT after ${TimeoutSeconds}s" }
            }
            Start-Sleep -Milliseconds 100
        }

        $out = $outTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()

        return @{ ExitCode = $proc.ExitCode; Output = "$out $err" }
    } catch {
        return @{ ExitCode = -1; Output = $_.ToString() }
    }
}

# Run a command silently but feed stdout lines into the spinner message
# Perfect for long installs (Cygwin, npm, cargo, pip) where you want to see progress
function Invoke-SilentWithProgress {
    param(
        [string]$Exe,
        [string]$Args,
        [string]$Prefix = ""     # e.g. "Cygwin" - shown before the current line
    )
    try {
        $resolvedExe = $Exe
        $cmdInfo = Get-Command $Exe -ErrorAction SilentlyContinue
        if ($cmdInfo) {
            if ($cmdInfo.Source) { $resolvedExe = $cmdInfo.Source }
            elseif ($cmdInfo.Definition) { $resolvedExe = $cmdInfo.Definition }
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $resolvedExe
        $psi.Arguments = $Args
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["PATH"] = $env:Path

        $proc = [System.Diagnostics.Process]::Start($psi)

        # Start async stderr read immediately to prevent buffer deadlock
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        # Read stdout line by line and update spinner
        $allOutput = ""
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            $allOutput += "$line`n"
            if ($line -and $line.Trim()) {
                $clean = $line.Trim()
                # Extract just the useful part (package name, status, etc.)
                if ($clean -match "install\s+(\S+)" ) { $clean = "Installing $($Matches[1])" }
                elseif ($clean -match "Downloaded\s+.*?/([^/]+)$") { $clean = "Downloaded $($Matches[1])" }
                elseif ($clean -match "^\d+\s+install\s+(\S+)") { $clean = "Queued $($Matches[1])" }
                # Truncate and update spinner
                if ($clean.Length -gt 45) { $clean = $clean.Substring(0, 42) + "..." }
                $msg = if ($Prefix) { "$Prefix : $clean" } else { $clean }
                $script:SpinnerSync.Message = $msg
            }
        }
        $errOutput = $stderrTask.GetAwaiter().GetResult()
        $proc.WaitForExit()

        return @{ ExitCode = $proc.ExitCode; Output = "$allOutput $errOutput" }
    } catch {
        return @{ ExitCode = -1; Output = $_.ToString() }
    }
}

# Fallback install: run in-process with output captured (for when Invoke-Silent fails)
function Invoke-InProcess {
    param([string]$Command)
    try {
        $output = cmd /c "$Command" 2>&1 | Out-String
        return @{ ExitCode = $LASTEXITCODE; Output = $output }
    } catch {
        return @{ ExitCode = -1; Output = $_.ToString() }
    }
}

function Install-App {
    param(
        [string]$Name,
        [string]$WingetId,
        [string]$ChocoId,
        [string]$ScoopId
    )

    # If a section spinner is already running (with progress), update it
    # Otherwise start our own
    $ownSpinner = -not $script:SpinnerSync.Active
    if ($ownSpinner) {
        Start-Spinner "Installing $Name..."
    } else {
        # Update existing spinner message + bump progress
        $script:SpinnerSync.Message = "Installing $Name..."
        if ($script:SpinnerSync.Total -gt 0) {
            $script:SpinnerSync.Progress++
        }
    }

    # Helper: finish this app (stop spinner only if we own it)
    $finishOk = {
        param($via)
        if ($ownSpinner) { Stop-Spinner -FinalMessage "$Name ($via)" -Status "OK" }
        Write-Log "$Name installed via $via" "OK"
    }
    $finishFail = {
        if ($ownSpinner) { Stop-Spinner -FinalMessage "$Name - FAILED (all methods)" -Status "ERROR" }
        Write-Log "$Name - ALL install methods failed (winget/choco/scoop)" "ERROR"
    }

    if ($WingetId) {
        $wingetExe = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetExe) {
            for ($attempt = 1; $attempt -le 2; $attempt++) {
                $r = Invoke-Silent "winget" "install --id $WingetId -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
                if ($r.ExitCode -eq 0 -or $r.Output -match "already installed|No newer package|successfully installed") {
                    & $finishOk "winget"; return
                }
                if ($r.ExitCode -eq -1) {
                    $r2 = Invoke-InProcess "winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
                    if ($r2.ExitCode -eq 0 -or $r2.Output -match "already installed|No newer package|successfully installed") {
                        & $finishOk "winget"; return
                    }
                }
                if ($attempt -lt 2) {
                    Update-SpinnerMessage "Installing $Name... retrying winget"
                    Start-Sleep -Seconds 3
                }
            }
        }
        Update-SpinnerMessage "Installing $Name... trying choco"
    }

    if ($ChocoId) {
        $chocoExe = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoExe) {
            $r = Invoke-Silent "choco" "install $ChocoId -y --no-progress --limit-output"
            if ($r.ExitCode -eq 0 -or $r.Output -match "already installed") {
                & $finishOk "choco"; return
            }
            if ($r.ExitCode -eq -1) {
                $r2 = Invoke-InProcess "choco install $ChocoId -y --no-progress --limit-output"
                if ($r2.ExitCode -eq 0 -or $r2.Output -match "already installed") {
                    & $finishOk "choco"; return
                }
            }
            Update-SpinnerMessage "Installing $Name... trying scoop"
        }
    }

    if ($ScoopId) {
        $scoopExe = Get-Command scoop -ErrorAction SilentlyContinue
        if ($scoopExe) {
            $r = Invoke-Silent "scoop" "install $ScoopId"
            if ($r.ExitCode -eq 0 -or $r.Output -match "already installed") {
                & $finishOk "scoop"; return
            }
        }
    }

    & $finishFail
}

# ============================================================================
# GitHub Release Helper - get latest asset URL dynamically
# ============================================================================

function Get-GitHubReleaseUrl {
    param(
        [string]$Repo,          # e.g. "BurntSushi/ripgrep"
        [string]$Pattern        # regex to match asset name, e.g. "x86_64-pc-windows-msvc\.zip$"
    )
    try {
        $api = "https://api.github.com/repos/$Repo/releases/latest"
        $release = Invoke-RestMethod -Uri $api -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
        if ($asset) {
            return $asset.browser_download_url
        }
    } catch {}
    return $null
}

# ============================================================================
# Install Portable Binary to C:\bin
# ============================================================================

function Install-PortableBin {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ExeName,
        [string]$ArchiveType = "zip",
        [string]$SubPath = ""
    )
    $binDir = "C:\bin"
    $destExe = Join-Path $binDir $ExeName
    if (Test-Path $destExe) {
        Write-Log "$Name already in C:\bin" "OK"
        return
    }
    Start-Spinner "Downloading $Name..."
    try {
        $dlPath = Join-Path $env:TEMP "wininit_$Name.$ArchiveType"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $dlPath -UseBasicParsing
        $ProgressPreference = 'Continue'

        if ($ArchiveType -eq "direct") {
            Copy-Item $dlPath -Destination $destExe -Force
        } else {
            $extractDir = Join-Path $env:TEMP "wininit_$Name"
            if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }

            if ($ArchiveType -in @("targz", "7z")) {
                # Use 7-Zip for .tar.gz and .7z archives
                $7z = "C:\Program Files\7-Zip\7z.exe"
                if (Test-Path $7z) {
                    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
                    & $7z x $dlPath -o"$extractDir" -y 2>&1 | Out-Null
                    # For .tar.gz: extract the inner .tar as well
                    $tarFile = Get-ChildItem $extractDir -Filter "*.tar" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($tarFile) {
                        & $7z x $tarFile.FullName -o"$extractDir" -y 2>&1 | Out-Null
                        Remove-Item $tarFile.FullName -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Write-Log "$Name - 7-Zip not found, cannot extract archive" "ERROR"
                    return
                }
            } else {
                Expand-Archive -Path $dlPath -DestinationPath $extractDir -Force
            }

            $sourceExe = if ($SubPath) {
                Get-ChildItem $extractDir -Recurse -Filter $ExeName | Where-Object {
                    $_.FullName -match [regex]::Escape($SubPath)
                } | Select-Object -First 1
            } else {
                Get-ChildItem $extractDir -Recurse -Filter $ExeName | Select-Object -First 1
            }

            if ($sourceExe) {
                Copy-Item $sourceExe.FullName -Destination $destExe -Force
                Write-Log "Extracted $ExeName from archive" "DEBUG"
            } else {
                Write-Log "$Name - $ExeName not found in archive" "ERROR"
                return
            }
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $dlPath -Force -ErrorAction SilentlyContinue
        Stop-Spinner -FinalMessage "$Name -> C:\bin" -Status "OK"
        Write-Log "$Name installed to C:\bin" "OK"
    } catch {
        Stop-Spinner -FinalMessage "$Name download failed" -Status "ERROR"
        Write-Log "$Name download failed: $_" "ERROR"
    }
}

# ============================================================================
# Install Portable App to C:\apps
# ============================================================================

function Install-PortableApp {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ArchiveType = "zip"
    )
    $appsDir = "C:\apps"
    $appFolder = Join-Path $appsDir $Name
    if (Test-Path $appFolder) {
        Write-Log "$Name already in C:\apps" "OK"
        return
    }
    Start-Spinner "Downloading $Name..."
    try {
        $dlPath = Join-Path $env:TEMP "wininit_app_$Name.$ArchiveType"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $dlPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        Update-SpinnerMessage "Extracting $Name..."

        $extractDir = Join-Path $env:TEMP "wininit_app_extract_$Name"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }

        if ($ArchiveType -eq "7z") {
            $7zExe = Get-Command 7z -ErrorAction SilentlyContinue
            if (-not $7zExe) { $7zExe = "C:\Program Files\7-Zip\7z.exe" }
            & $7zExe x $dlPath -o"$extractDir" -y 2>&1 | Out-Null
        } else {
            Expand-Archive -Path $dlPath -DestinationPath $extractDir -Force
        }

        $items = @(Get-ChildItem $extractDir)
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            Move-Item $items[0].FullName $appFolder -Force
        } else {
            New-Item -ItemType Directory -Path $appFolder -Force | Out-Null
            $items | Move-Item -Destination $appFolder -Force
        }

        Remove-Item $dlPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Spinner -FinalMessage "$Name -> C:\apps" -Status "OK"
        Write-Log "$Name extracted to C:\apps\$Name" "OK"
    } catch {
        Stop-Spinner -FinalMessage "$Name download failed" -Status "ERROR"
        Write-Log "$Name download failed: $_" "ERROR"
    }
}

# ============================================================================
# Refresh PATH
# ============================================================================

function Update-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Log "PATH refreshed" "DEBUG"
}

# ============================================================================
# Registry helpers
# ============================================================================

function Ensure-RegKey {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
        Write-Log "Created registry key: $Path" "DEBUG"
    }
}

function Set-RegistrySafe {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        Write-Log "Registry set: $Path\$Name = $Value ($Type)" "DEBUG"
    } catch {
        Write-Log "Registry write failed: $Path\$Name = $Value - $_" "WARN"
    }
}

# ============================================================================
# Service helpers
# ============================================================================

function Disable-ServiceSafe {
    param([string]$Name, [string]$DisplayName = "")
    $label = if ($DisplayName) { "$DisplayName ($Name)" } else { $Name }
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq "Running") {
                Write-Log "Stopping service: $label" "DEBUG"
                Stop-Service -Name $Name -Force -ErrorAction Stop
            }
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
            if (Test-Path $regPath) {
                Set-ItemProperty -Path $regPath -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
            }
            Write-Log "$label disabled" "OK"
        } else {
            Write-Log "$label not found (may not be installed)" "WARN"
        }
    } catch {
        Write-Log "$label disable failed: $_" "WARN"
    }
}

# ============================================================================
# Download helper (retry + exponential backoff)
# ============================================================================

function Invoke-DownloadSafe {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$MaxRetries = 3,
        [int]$TimeoutSec = 120
    )
    Write-Log "Downloading $(Split-Path $Url -Leaf) -> $OutFile" "DEBUG"
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            $ProgressPreference = 'Continue'
            Write-Log "Download complete: $(Split-Path $Url -Leaf)" "DEBUG"
            return $true
        } catch {
            $ProgressPreference = 'Continue'
            if ($i -lt $MaxRetries) {
                Write-Log "Download attempt $i/$MaxRetries failed for $(Split-Path $Url -Leaf): $_ - retrying..." "WARN"
                Start-Sleep -Seconds (2 * $i)
            } else {
                Write-Log "Download FAILED after $MaxRetries attempts: $Url - $_" "ERROR"
                return $false
            }
        }
    }
    return $false
}

# ============================================================================
# Safe command execution (with timeout)
# ============================================================================

function Invoke-CommandSafe {
    param(
        [string]$Description,
        [scriptblock]$Action,
        [int]$TimeoutMinutes = 10,
        [switch]$ContinueOnError
    )
    Write-Log "Executing: $Description (timeout: ${TimeoutMinutes}m)" "DEBUG"
    try {
        $job = Start-Job -ScriptBlock $Action
        $completed = Wait-Job $job -Timeout ($TimeoutMinutes * 60)
        if ($completed) {
            $result = Receive-Job $job
            Remove-Job $job -Force
            if ($LASTEXITCODE -ne 0 -and -not $ContinueOnError) {
                Write-Log "$Description completed with exit code $LASTEXITCODE" "WARN"
            } else {
                Write-Log "$Description completed" "OK"
            }
            return $result
        } else {
            Stop-Job $job
            Remove-Job $job -Force
            Write-Log "$Description TIMED OUT after $TimeoutMinutes minutes" "ERROR"
            return $null
        }
    } catch {
        Write-Log "$Description FAILED: $_" "ERROR"
        if (-not $ContinueOnError) { throw }
        return $null
    }
}

# ============================================================================
# PATH management
# ============================================================================

function Add-ToSystemPath {
    param([string]$Directory)
    if (-not (Test-Path $Directory)) {
        Write-Log "PATH: $Directory does not exist - skipping" "WARN"
        return $false
    }
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notmatch [regex]::Escape($Directory)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$Directory", "Machine")
        $env:Path = "$env:Path;$Directory"
        Write-Log "Added to PATH: $Directory" "OK"
        return $true
    } else {
        Write-Log "Already in PATH: $Directory" "OK"
        return $false
    }
}

# ============================================================================
# AppxPackage removal
# ============================================================================

function Remove-AppxSafe {
    param([string]$Name)
    Write-Log "Removing AppxPackage: $Name" "DEBUG"
    try {
        Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like "*$Name*" } |
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        Write-Log "AppxPackage removed: $Name" "DEBUG"
    } catch {
        Write-Log "AppxPackage removal issue for $Name - $_" "WARN"
    }
}

# ============================================================================
# Hosts file blocking
# ============================================================================

function Add-HostsBlock {
    param(
        [string]$MarkerName,
        [string[]]$Hostnames
    )
    $hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
    $hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
    $marker = "# --- WinInit $MarkerName ---"
    if ($hostsContent -notmatch [regex]::Escape($marker)) {
        $block = "`n$marker`n"
        foreach ($h in $Hostnames) {
            $block += "0.0.0.0 $h`n"
        }
        $block += "# --- End WinInit $MarkerName ---"
        Add-Content -Path $hostsFile -Value $block -Encoding ASCII
        Write-Log "$MarkerName - $($Hostnames.Count) hosts blocked" "OK"
    } else {
        Write-Log "$MarkerName - already applied" "OK"
    }
}

# ============================================================================
# User-Scope Safety
# ============================================================================
# NOTE on scoping: This script runs elevated (admin). On Windows, UAC elevation
# preserves the user's identity - so:
#   - HKCU:\ writes go to the CORRECT user's registry hive (not SYSTEM)
#   - $env:USERPROFILE points to the CORRECT user's folder
#   - $env:APPDATA, $env:LOCALAPPDATA are CORRECT
#   - npm/pip/cargo/go install to the CORRECT user's home dirs
# The only exception is if the script is run as SYSTEM (e.g., from a scheduled
# task or SCCM) - the preflight check catches this.

# Set a user-scoped environment variable (explicitly targets User, not Machine)
function Set-UserEnvVar {
    param([string]$Name, [string]$Value)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "User")
    # Also set for current session
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    Write-Log "User env var: $Name = $Value" "DEBUG"
}

# Set a machine-scoped environment variable
function Set-MachineEnvVar {
    param([string]$Name, [string]$Value)
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Machine")
    [System.Environment]::SetEnvironmentVariable($Name, $Value, "Process")
    Write-Log "Machine env var: $Name = $Value" "DEBUG"
}

# Get the user-scoped value of a path (resolves %USERPROFILE% etc.)
function Get-UserPath {
    param([string]$SubPath)
    return Join-Path $env:USERPROFILE $SubPath
}

