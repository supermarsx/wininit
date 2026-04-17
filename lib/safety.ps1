# ============================================================================
# WinInit - Safety / Risk Indicator System
# Provides risk-level tagging for all tweaks (safe, moderate, aggressive)
# ============================================================================

# --- Risk Level Definitions ---
$script:RiskLevels = @{
    safe       = @{ Icon = "[S]"; Color = "Green";  Ansi = "BrGreen";  Desc = "Cosmetic / easily reversible" }
    moderate   = @{ Icon = "[M]"; Color = "Yellow"; Ansi = "BrYellow"; Desc = "Functional change / may affect features" }
    aggressive = @{ Icon = "[A]"; Color = "Red";    Ansi = "BrRed";    Desc = "Disables security features / kernel-level" }
}

# --- Risk Statistics Tracker ---
$script:RiskStats = @{ safe = 0; moderate = 0; aggressive = 0 }

function Write-RiskLog {
    <#
    .SYNOPSIS
        Logs a message with a risk-level indicator prepended.
    .PARAMETER Message
        The log message text.
    .PARAMETER Risk
        Risk level: safe, moderate, or aggressive.
    .PARAMETER Level
        Log level passed to Write-Log (OK, INFO, WARN, ERROR, DEBUG, STEP).
    #>
    param(
        [string]$Message,
        [ValidateSet("safe", "moderate", "aggressive")]
        [string]$Risk = "safe",
        [string]$Level = "OK"
    )

    $script:RiskStats[$Risk]++
    $riskCfg = $script:RiskLevels[$Risk]
    Write-Log "$($riskCfg.Icon) $Message" $Level
}

function Write-RiskSummary {
    <#
    .SYNOPSIS
        Displays a summary of all risk-tagged operations performed during the run.
    #>
    $total = $script:RiskStats.safe + $script:RiskStats.moderate + $script:RiskStats.aggressive

    Write-Log "--- Risk Summary ---" "INFO"
    Write-Log "  Total tweaks applied: $total" "INFO"
    Write-Log "  [S] Safe       (cosmetic / reversible):        $($script:RiskStats.safe)" "INFO"
    Write-Log "  [M] Moderate   (functional / feature changes): $($script:RiskStats.moderate)" "INFO"
    Write-Log "  [A] Aggressive (security / kernel-level):      $($script:RiskStats.aggressive)" "INFO"

    if ($script:RiskStats.aggressive -gt 0) {
        Write-Log "  $($script:RiskStats.aggressive) aggressive tweak(s) applied - review log for details" "WARN"
    }
}
