# ============================================================================
# WinInit DevScript: Type Checker
# Validates PowerShell script types, parameter definitions, and common pitfalls
# Usage: .\devscripts\typecheck.ps1
# ============================================================================

$ErrorActionPreference = "Continue"
$script:Issues = 0

function Type-Issue {
    param([string]$File, [string]$Rule, [string]$Message)
    Write-Host "  " -NoNewline
    Write-Host "[$Rule]" -ForegroundColor Magenta -NoNewline
    Write-Host " $File" -ForegroundColor White -NoNewline
    Write-Host " - $Message" -ForegroundColor Gray
    $script:Issues++
}

Write-Host ""
Write-Host "  WinInit Type Checker" -ForegroundColor Cyan
Write-Host "  ====================" -ForegroundColor Cyan
Write-Host ""

$allScripts = @()
$allScripts += Get-ChildItem "$PSScriptRoot\..\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\..\lib\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\..\modules\*.ps1"
$allScripts += Get-ChildItem "$PSScriptRoot\*.ps1"

foreach ($scriptFile in $allScripts) {
    Write-Host "  Checking: $($scriptFile.Name)" -ForegroundColor DarkGray

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName, [ref]$tokens, [ref]$parseErrors
    )

    # Check parse errors
    foreach ($err in $parseErrors) {
        Type-Issue $scriptFile.Name "PARSE" "Line $($err.Extent.StartLineNumber): $($err.Message)"
    }

    # Check all function definitions for typed parameters
    $functions = $ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    foreach ($func in $functions) {
        $funcName = $func.Name
        if ($func.Parameters) {
            foreach ($param in $func.Parameters) {
                if (-not $param.StaticType -or $param.StaticType.Name -eq "Object") {
                    # Check if there's a [type] attribute
                    $hasType = $param.Attributes | Where-Object {
                        $_ -is [System.Management.Automation.Language.TypeConstraintAst]
                    }
                    if (-not $hasType) {
                        Type-Issue $scriptFile.Name "UNTYPED" "Function '$funcName' param '$($param.Name)' has no type constraint"
                    }
                }
            }
        }
    }

    # Check for common type-unsafe patterns
    $content = Get-Content $scriptFile.FullName -Raw

    # String concatenation with + instead of string interpolation
    $concatMatches = [regex]::Matches($content, '\$\w+\s*\+\s*"')
    if ($concatMatches.Count -gt 5) {
        Type-Issue $scriptFile.Name "CONCAT" "Heavy string concatenation ($($concatMatches.Count) instances) - consider interpolation"
    }

    # Unquoted variable expansion in paths
    $pathMatches = [regex]::Matches($content, 'Join-Path\s+\$\w+\s+[^"$]')
    foreach ($m in $pathMatches) {
        Type-Issue $scriptFile.Name "PATH" "Unquoted Join-Path argument near: $($m.Value.Trim().Substring(0, [Math]::Min(50, $m.Value.Trim().Length)))"
    }

    # Comparison with $null on wrong side
    $nullMatches = [regex]::Matches($content, '\$\w+\s*-eq\s*\$null')
    foreach ($m in $nullMatches) {
        Type-Issue $scriptFile.Name "NULL" "Use `$null on left side of comparison: `$null -eq `$var"
    }
}

# --- Verify common.ps1 exports expected functions ---
Write-Host ""
Write-Host "  --- Function Availability ---" -ForegroundColor Magenta

$commonContent = Get-Content "$PSScriptRoot\..\lib\common.ps1" -Raw
$requiredFunctions = @(
    "Write-Log", "Write-Section", "Write-ProgressBar", "Write-SubStep",
    "Install-WithRetry", "Install-App", "Install-PortableBin", "Install-PortableApp",
    "Update-Path", "Ensure-RegKey", "Write-SummaryBox"
)

foreach ($func in $requiredFunctions) {
    $found = $commonContent -match "function\s+$func\b"
    if ($found) {
        Write-Host "  [OK]   " -ForegroundColor Green -NoNewline
        Write-Host "$func defined in common.ps1"
    } else {
        Type-Issue "common.ps1" "MISSING" "Required function '$func' not found"
    }
}

# --- Verify modules reference functions that exist ---
Write-Host ""
Write-Host "  --- Cross-Reference ---" -ForegroundColor Magenta

$moduleFiles = Get-ChildItem "$PSScriptRoot\..\modules\*.ps1"
$knownFunctions = $requiredFunctions + @("Set-ItemProperty", "Get-ItemProperty", "New-Item", "Test-Path")

foreach ($mod in $moduleFiles) {
    $modContent = Get-Content $mod.FullName -Raw
    # Check for calls to Write-Section (every module should have one)
    if ($modContent -notmatch "Write-Section") {
        Type-Issue $mod.Name "NOSECTION" "Module doesn't call Write-Section"
    }
    # Check for calls to Write-Log at the end
    if ($modContent -notmatch 'Write-Log.*completed') {
        Type-Issue $mod.Name "NOEND" "Module doesn't have a completion Write-Log"
    }
}

# --- Summary ---
Write-Host ""
Write-Host "  ====================" -ForegroundColor Cyan
Write-Host "  Issues found: $($script:Issues)" -ForegroundColor $(if ($script:Issues -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

exit $(if ($script:Issues -gt 0) { 1 } else { 0 })
