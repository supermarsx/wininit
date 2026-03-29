# ============================================================================
# WinInit DevScript: Formatter
# Auto-formats all scripts for consistent style
# Usage: .\devscripts\format.ps1 [-Check] [-Verbose]
# ============================================================================

param(
    [switch]$Check,     # Only check, don't modify (exit 1 if changes needed)
    [switch]$Verbose    # Show every change
)

$ErrorActionPreference = "Continue"
$script:FilesChanged = 0
$script:TotalChanges = 0

function Format-Script {
    param([string]$Path)

    $original = Get-Content $Path -Raw
    $lines = Get-Content $Path

    $formatted = @()
    $changes = 0

    foreach ($line in $lines) {
        $newLine = $line

        # Strip trailing whitespace
        $newLine = $newLine -replace "\s+$", ""

        # Normalize indentation (convert tabs to 4 spaces)
        if ($Path -notmatch "launch\.bat$") {
            $leadingTabs = ($newLine -match "^(\t+)")
            if ($leadingTabs) {
                $newLine = $newLine -replace "^\t+", { "    " * $Matches[0].Length }
            }
        }

        # Ensure space after # in comments (but not #Requires, #region, shebang)
        if ($newLine -match "^\s*#[A-Za-z]" -and $newLine -notmatch "^\s*#(Requires|region|endregion|!)") {
            $newLine = $newLine -replace "^(\s*)#([A-Za-z])", '$1# $2'
        }

        # Normalize operator spacing: -eq, -ne, -match, etc.
        $newLine = $newLine -replace "\s{2,}(-eq|-ne|-gt|-lt|-ge|-le|-match|-notmatch|-like|-notlike|-contains)\s", ' $1 '

        if ($newLine -ne $line) { $changes++ }
        $formatted += $newLine
    }

    # Ensure file ends with single newline
    $result = ($formatted -join "`r`n") + "`r`n"

    # Remove consecutive blank lines (max 2)
    $result = $result -replace "(`r`n){4,}", "`r`n`r`n`r`n"

    if ($result -ne $original) {
        $script:FilesChanged++
        $script:TotalChanges += $changes

        if ($Verbose -or $Check) {
            Write-Host "  [MOD] " -ForegroundColor Yellow -NoNewline
            Write-Host "$([System.IO.Path]::GetFileName($Path))" -ForegroundColor White -NoNewline
            Write-Host " - $changes line(s) changed" -ForegroundColor Gray
        }

        if (-not $Check) {
            Set-Content -Path $Path -Value $result -NoNewline -Encoding UTF8
        }
    } else {
        if ($Verbose) {
            Write-Host "  [OK]  " -ForegroundColor Green -NoNewline
            Write-Host "$([System.IO.Path]::GetFileName($Path))" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "  WinInit Formatter$(if ($Check) { ' (check mode)' })" -ForegroundColor Cyan
Write-Host "  =================" -ForegroundColor Cyan
Write-Host ""

$allFiles = @()
$allFiles += Get-ChildItem "$PSScriptRoot\..\*.ps1"
$allFiles += Get-ChildItem "$PSScriptRoot\..\*.bat"
$allFiles += Get-ChildItem "$PSScriptRoot\..\lib\*.ps1"
$allFiles += Get-ChildItem "$PSScriptRoot\..\modules\*.ps1"
$allFiles += Get-ChildItem "$PSScriptRoot\*.ps1"

foreach ($file in $allFiles) {
    Format-Script $file.FullName
}

# --- Summary ---
Write-Host ""
if ($Check) {
    if ($script:FilesChanged -gt 0) {
        Write-Host "  $($script:FilesChanged) file(s) need formatting ($($script:TotalChanges) changes)" -ForegroundColor Yellow
        Write-Host "  Run: .\devscripts\format.ps1  (without -Check) to fix" -ForegroundColor Gray
    } else {
        Write-Host "  All files formatted correctly" -ForegroundColor Green
    }
} else {
    if ($script:FilesChanged -gt 0) {
        Write-Host "  Formatted $($script:FilesChanged) file(s), $($script:TotalChanges) change(s)" -ForegroundColor Green
    } else {
        Write-Host "  All files already formatted" -ForegroundColor Green
    }
}
Write-Host ""

exit $(if ($Check -and $script:FilesChanged -gt 0) { 1 } else { 0 })
