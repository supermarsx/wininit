# ============================================================================
# WinInit DevScript: Linter
# Checks all scripts for common issues, anti-patterns, and style violations
# Usage: .\devscripts\lint.ps1 [-Fix]
# ============================================================================

param(
    [switch]$Fix    # Auto-fix what can be fixed (trailing whitespace, BOM, encoding)
)

$ErrorActionPreference = "Continue"
$script:Issues = 0
$script:Fixed  = 0

function Lint-Issue {
    param([string]$File, [int]$Line, [string]$Rule, [string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "[$Rule]" -ForegroundColor Yellow -NoNewline
    Write-Host " $File" -ForegroundColor White -NoNewline
    Write-Host ":$Line" -ForegroundColor DarkGray -NoNewline
    Write-Host " - $Message" -ForegroundColor Gray
    $script:Issues++
}

Write-Host ""
Write-Host "  WinInit Linter" -ForegroundColor Cyan
Write-Host "  ==============" -ForegroundColor Cyan
Write-Host ""

$allScripts = @()
$allScripts += Get-ChildItem "$PSScriptRoot\..\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\..\lib\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\..\modules\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\*.ps1"

foreach ($script in $allScripts) {
    $lines = Get-Content $script.FullName
    $lineNum = 0
    $isModuleScript = $script.FullName -match '\\modules\\'

    Write-Host "  Checking: $($script.Name)" -ForegroundColor DarkGray

    foreach ($line in $lines) {
        $lineNum++

        # Rule: No trailing whitespace
        if ($line -match "\s+$" -and $line.Trim().Length -gt 0) {
            Lint-Issue $script.Name $lineNum "TRAIL" "Trailing whitespace"
        }

        # Rule: No tabs (prefer spaces)
        if ($line -match "`t" -and $script.Name -ne "launch.bat") {
            Lint-Issue $script.Name $lineNum "TABS" "Tab character found (use spaces)"
        }

        # Rule: Lines shouldn't exceed 200 chars
        if ($line.Length -gt 200) {
            Lint-Issue $script.Name $lineNum "LEN" "Line exceeds 200 characters ($($line.Length))"
        }

        # Rule: No hardcoded usernames
        if ($line -match "C:\\Users\\[A-Za-z]+" -and $line -notmatch '\$env:' -and $line -notmatch "USERPROFILE") {
            Lint-Issue $script.Name $lineNum "USER" "Hardcoded username in path"
        }

        # Rule: No plain-text passwords or API keys
        if ($line -match "(password|api_key|secret|token)\s*=\s*['""][^'""]+['""]" -and $line -notmatch "#") {
            Lint-Issue $script.Name $lineNum "SEC" "Possible hardcoded secret"
        }

        # Rule: Use -ErrorAction, not 2>$null on PowerShell cmdlets
        if ($line -match "Set-ItemProperty.*2>\`$null" -or $line -match "Get-ItemProperty.*2>\`$null") {
            Lint-Issue $script.Name $lineNum "ERR" "Use -ErrorAction SilentlyContinue instead of 2>`$null on cmdlets"
        }

        # Rule: Don't use Write-Host for data (use Write-Log instead)
        if ($isModuleScript -and $line -match "^\s*Write-Host\s" -and $line -notmatch "ForegroundColor" -and $line -notmatch "NoNewline") {
            Lint-Issue $script.Name $lineNum "LOG" "Plain Write-Host - consider Write-Log for important messages"
        }
    }

    # Rule: File should end with newline
    $raw = Get-Content $script.FullName -Raw
    if ($raw -and -not $raw.EndsWith("`n")) {
        Lint-Issue $script.Name $lines.Count "EOF" "File doesn't end with newline"
    }

    # Rule: Parse errors
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors)
    foreach ($err in $parseErrors) {
        Lint-Issue $script.Name $err.Extent.StartLineNumber "PARSE" $err.Message
    }

    # Auto-fix trailing whitespace if -Fix
    if ($Fix) {
        $content = Get-Content $script.FullName
        $cleaned = $content | ForEach-Object { $_ -replace "\s+$", "" }
        $diff = Compare-Object $content $cleaned
        if ($diff) {
            $cleaned | Set-Content $script.FullName -Encoding UTF8
            $fixCount = $diff.Count / 2
            Write-Host "    Fixed $fixCount lines (trailing whitespace)" -ForegroundColor Green
            $script:Fixed += $fixCount
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "  ==============" -ForegroundColor Cyan
Write-Host "  Issues found: $($script:Issues)" -ForegroundColor $(if ($script:Issues -gt 0) { "Yellow" } else { "Green" })
if ($Fix) {
    Write-Host "  Auto-fixed:   $($script:Fixed)" -ForegroundColor Green
}
Write-Host ""

exit $(if ($script:Issues -gt 0) { 1 } else { 0 })
