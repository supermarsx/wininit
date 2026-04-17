# Module: 07 - Privacy
# Comprehensive privacy hardening: telemetry, ads, tracking, location,
# camera/mic, inking, tips, error reporting, Cortana, Copilot, feedback, hosts

Write-Section "Privacy (Comprehensive)"

# ============================================================================
# Flag: set to $true to block telemetry hosts via the hosts file (aggressive)
# ============================================================================
$script:BlockTelemetryHosts = $false

# --- 7a. Disable Wi-Fi Sense ---
Write-Log "Disabling Wi-Fi Sense..."
$WifiSensePath = "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"
if (-not (Test-Path $WifiSensePath)) { New-Item -Path $WifiSensePath -Force | Out-Null }
Set-ItemProperty -Path $WifiSensePath -Name "AutoConnectAllowedOEM" -Value 0 -Type DWord
$WifiPolicy = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi"
$wifiKeys = @("AllowWiFiHotSpotReporting", "AllowAutoConnectToWiFiSenseHotspots")
foreach ($wk in $wifiKeys) {
    $wkPath = Join-Path $WifiPolicy $wk
    if (-not (Test-Path $wkPath)) { New-Item -Path $wkPath -Force | Out-Null }
    Set-ItemProperty -Path $wkPath -Name "Value" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-RiskLog "Wi-Fi Sense disabled" "safe" "OK"

# --- 7b. Disable Clipboard Cloud Sync ---
Write-Log "Disabling clipboard cloud sync..."
$ClipPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $ClipPath)) { New-Item -Path $ClipPath -Force | Out-Null }
Set-ItemProperty -Path $ClipPath -Name "AllowCrossDeviceClipboard" -Value 0 -Type DWord
Set-ItemProperty -Path $ClipPath -Name "AllowClipboardHistory"     -Value 0 -Type DWord
# User level too
$ClipUser = "HKCU:\Software\Microsoft\Clipboard"
if (-not (Test-Path $ClipUser)) { New-Item -Path $ClipUser -Force | Out-Null }
Set-ItemProperty -Path $ClipUser -Name "EnableClipboardHistory"    -Value 0 -Type DWord
Set-ItemProperty -Path $ClipUser -Name "CloudClipboardAutomaticUpload" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-RiskLog "Clipboard cloud sync disabled" "safe" "OK"

# --- 7c. Disable Timeline ---
Write-Log "Disabling Timeline..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed"    -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities"  -Value 0 -Type DWord
Write-RiskLog "Timeline disabled" "safe" "OK"

# --- 7d. Disable SmartScreen for Apps ---
Write-Log "Disabling SmartScreen for apps..."
$SmartScreenPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Set-ItemProperty -Path $SmartScreenPath -Name "EnableSmartScreen" -Value 0 -Type DWord -ErrorAction SilentlyContinue
$SmartScreenExplorer = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
Set-ItemProperty -Path $SmartScreenExplorer -Name "SmartScreenEnabled" -Value "Off" -Type String -ErrorAction SilentlyContinue
# Disable SmartScreen for downloaded files
$AttachmentPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments"
if (-not (Test-Path $AttachmentPath)) { New-Item -Path $AttachmentPath -Force | Out-Null }
Set-ItemProperty -Path $AttachmentPath -Name "SaveZoneInformation" -Value 1 -Type DWord
Write-RiskLog "SmartScreen for apps disabled" "moderate" "OK"

# --- 7e. Disable Delivery Optimization (P2P Updates) ---
Write-Log "Disabling Delivery Optimization..."
$DOPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
if (-not (Test-Path $DOPath)) { New-Item -Path $DOPath -Force | Out-Null }
Set-ItemProperty -Path $DOPath -Name "DODownloadMode" -Value 0 -Type DWord  # 0 = off
$DOUserPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
if (-not (Test-Path $DOUserPath)) { New-Item -Path $DOUserPath -Force | Out-Null }
Set-ItemProperty -Path $DOUserPath -Name "DODownloadMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-RiskLog "Delivery Optimization (P2P updates) disabled" "safe" "OK"

# ============================================================================
# 7f. Telemetry & Diagnostics
# ============================================================================
Write-Log "Configuring telemetry and diagnostics..."

# Disable Windows telemetry
$DataCollectionPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-not (Test-Path $DataCollectionPath)) { New-Item -Path $DataCollectionPath -Force | Out-Null }
Set-ItemProperty -Path $DataCollectionPath -Name "AllowTelemetry" -Value 0 -Type DWord
Write-RiskLog "Windows telemetry disabled (AllowTelemetry=0)" "safe" "OK"

# Disable diagnostic data
Set-ItemProperty -Path $DataCollectionPath -Name "MaxTelemetryAllowed" -Value 0 -Type DWord
Write-RiskLog "Diagnostic data disabled (MaxTelemetryAllowed=0)" "safe" "OK"

# Disable Connected User Experiences & Telemetry service (DiagTrack)
Write-Log "Disabling DiagTrack service..."
Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
$DiagTrackReg = "HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack"
if (Test-Path $DiagTrackReg) {
    Set-ItemProperty -Path $DiagTrackReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
}
Write-RiskLog "DiagTrack service stopped and disabled" "aggressive" "OK"

# Disable dmwappushservice (WAP Push)
Write-Log "Disabling dmwappushservice..."
Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
$WapReg = "HKLM:\SYSTEM\CurrentControlSet\Services\dmwappushservice"
if (Test-Path $WapReg) {
    Set-ItemProperty -Path $WapReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
}
Write-RiskLog "dmwappushservice (WAP Push) stopped and disabled" "aggressive" "OK"

# Disable Customer Experience Improvement Program (CEIP)
$CEIPPath = "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"
if (-not (Test-Path $CEIPPath)) { New-Item -Path $CEIPPath -Force | Out-Null }
Set-ItemProperty -Path $CEIPPath -Name "CEIPEnable" -Value 0 -Type DWord
Write-RiskLog "CEIP disabled" "safe" "OK"

# Disable Application Impact Telemetry
$AppCompatPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
if (-not (Test-Path $AppCompatPath)) { New-Item -Path $AppCompatPath -Force | Out-Null }
Set-ItemProperty -Path $AppCompatPath -Name "AITEnable" -Value 0 -Type DWord
Write-RiskLog "Application Impact Telemetry disabled" "safe" "OK"

# Disable Steps Recorder
Set-ItemProperty -Path $AppCompatPath -Name "DisableStepsRecorder" -Value 1 -Type DWord
Write-RiskLog "Steps Recorder disabled" "safe" "OK"

# Disable Inventory Collector
Set-ItemProperty -Path $AppCompatPath -Name "DisableInventory" -Value 1 -Type DWord
Write-RiskLog "Inventory Collector disabled" "safe" "OK"

# ============================================================================
# 7g. Advertising & Tracking
# ============================================================================
Write-Log "Configuring advertising and tracking..."

# Disable Advertising ID (user level)
$AdvInfoPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
if (-not (Test-Path $AdvInfoPath)) { New-Item -Path $AdvInfoPath -Force | Out-Null }
Set-ItemProperty -Path $AdvInfoPath -Name "Enabled" -Value 0 -Type DWord
Write-RiskLog "Advertising ID disabled (user)" "safe" "OK"

# Disable ad tracking
Set-ItemProperty -Path $AdvInfoPath -Name "DisabledByGroupPolicy" -Value 1 -Type DWord
Write-RiskLog "Ad tracking disabled via group policy flag" "safe" "OK"

# Disable advertising ID via machine policy
$AdvPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
if (-not (Test-Path $AdvPolicyPath)) { New-Item -Path $AdvPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $AdvPolicyPath -Name "AllowAdvertisingInfo" -Value 0 -Type DWord
Write-RiskLog "Advertising ID disabled (machine policy)" "safe" "OK"

# ============================================================================
# 7h. Location
# ============================================================================
Write-Log "Configuring location settings..."

$LocationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
if (-not (Test-Path $LocationPath)) { New-Item -Path $LocationPath -Force | Out-Null }

# Disable location tracking globally
Set-ItemProperty -Path $LocationPath -Name "DisableLocation" -Value 1 -Type DWord
Write-RiskLog "Location tracking disabled globally" "safe" "OK"

# Disable location scripting
Set-ItemProperty -Path $LocationPath -Name "DisableLocationScripting" -Value 1 -Type DWord
Write-RiskLog "Location scripting disabled" "safe" "OK"

# Disable sensor data collection
Set-ItemProperty -Path $LocationPath -Name "DisableSensors" -Value 1 -Type DWord
Write-RiskLog "Sensor data collection disabled" "safe" "OK"

# ============================================================================
# 7i. Camera & Microphone Defaults
# ============================================================================
Write-Log "Configuring camera and microphone defaults..."

# Set camera default to deny for apps
$CamConsentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
if (-not (Test-Path $CamConsentPath)) { New-Item -Path $CamConsentPath -Force | Out-Null }
Set-ItemProperty -Path $CamConsentPath -Name "Value" -Value "Deny" -Type String
Write-RiskLog "Camera default set to Deny for apps" "moderate" "OK"

# Set microphone default to deny for apps
$MicConsentPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"
if (-not (Test-Path $MicConsentPath)) { New-Item -Path $MicConsentPath -Force | Out-Null }
Set-ItemProperty -Path $MicConsentPath -Name "Value" -Value "Deny" -Type String
Write-RiskLog "Microphone default set to Deny for apps" "moderate" "OK"

# ============================================================================
# 7j. Inking & Typing
# ============================================================================
Write-Log "Configuring inking and typing privacy..."

# Disable "Improve inking and typing"
$InputPersonPath = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
if (-not (Test-Path $InputPersonPath)) { New-Item -Path $InputPersonPath -Force | Out-Null }
Set-ItemProperty -Path $InputPersonPath -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord
Write-RiskLog "Implicit ink collection restricted" "safe" "OK"

# Disable "Getting to know you"
Set-ItemProperty -Path $InputPersonPath -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord
Write-RiskLog "Implicit text collection restricted" "safe" "OK"

# Disable handwriting data sharing
$TabletPCPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC"
if (-not (Test-Path $TabletPCPath)) { New-Item -Path $TabletPCPath -Force | Out-Null }
Set-ItemProperty -Path $TabletPCPath -Name "PreventHandwritingDataSharing" -Value 1 -Type DWord
Write-RiskLog "Handwriting data sharing disabled" "safe" "OK"

# Disable handwriting error reports
$HWErrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports"
if (-not (Test-Path $HWErrPath)) { New-Item -Path $HWErrPath -Force | Out-Null }
Set-ItemProperty -Path $HWErrPath -Name "PreventHandwritingErrorReports" -Value 1 -Type DWord
Write-RiskLog "Handwriting error reports disabled" "safe" "OK"

# ============================================================================
# 7k. Tailored Experiences & Content
# ============================================================================
Write-Log "Configuring tailored experiences and content..."

# Disable tailored experiences (user level)
$CloudContentUser = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $CloudContentUser)) { New-Item -Path $CloudContentUser -Force | Out-Null }
Set-ItemProperty -Path $CloudContentUser -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord
Write-RiskLog "Tailored experiences disabled" "safe" "OK"

# Disable Windows tips/suggestions
Set-ItemProperty -Path $CloudContentUser -Name "DisableSoftLanding" -Value 1 -Type DWord
Write-RiskLog "Windows tips and suggestions disabled" "safe" "OK"

# Disable Windows Spotlight on lock screen
Set-ItemProperty -Path $CloudContentUser -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord
Write-RiskLog "Windows Spotlight on lock screen disabled" "safe" "OK"

# Disable "Get fun facts, tips" on lock screen & app suggestions in Start
$CloudContentMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $CloudContentMachine)) { New-Item -Path $CloudContentMachine -Force | Out-Null }
Set-ItemProperty -Path $CloudContentMachine -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Write-RiskLog "Consumer features (tips on lock screen, app suggestions) disabled" "safe" "OK"

# ============================================================================
# 7l. Windows Error Reporting
# ============================================================================
Write-Log "Configuring Windows Error Reporting..."

# Disable WER service
Stop-Service -Name "WerSvc" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "WerSvc" -StartupType Disabled -ErrorAction SilentlyContinue
$WerSvcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\WerSvc"
if (Test-Path $WerSvcReg) {
    Set-ItemProperty -Path $WerSvcReg -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
}
Write-RiskLog "WerSvc service stopped and disabled" "moderate" "OK"

# Disable WER via policy
$WERPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
if (-not (Test-Path $WERPolicyPath)) { New-Item -Path $WERPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $WERPolicyPath -Name "Disabled" -Value 1 -Type DWord
Write-RiskLog "Windows Error Reporting disabled via policy" "moderate" "OK"

# Disable WER consent
$WERConsentPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Consent"
if (-not (Test-Path $WERConsentPath)) { New-Item -Path $WERConsentPath -Force | Out-Null }
Set-ItemProperty -Path $WERConsentPath -Name "DefaultConsent" -Value 1 -Type DWord
Write-RiskLog "Windows Error Reporting consent set to never send" "moderate" "OK"

# ============================================================================
# 7m. Cortana & Search (reinforcement)
# ============================================================================
Write-Log "Configuring Cortana and search..."

$SearchPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (-not (Test-Path $SearchPath)) { New-Item -Path $SearchPath -Force | Out-Null }

# Disable Cortana fully
Set-ItemProperty -Path $SearchPath -Name "AllowCortana" -Value 0 -Type DWord
Write-RiskLog "Cortana disabled" "safe" "OK"

# Disable web search from taskbar
Set-ItemProperty -Path $SearchPath -Name "DisableWebSearch" -Value 1 -Type DWord
Write-RiskLog "Web search from taskbar disabled" "safe" "OK"

# Disable Connected Search
Set-ItemProperty -Path $SearchPath -Name "ConnectedSearchUseWeb" -Value 0 -Type DWord
Write-RiskLog "Connected Search disabled" "safe" "OK"

# ============================================================================
# 7n. Edge / Copilot / AI Features (Windows 11 24H2+)
# ============================================================================
Write-Log "Configuring Copilot and AI features..."

# Disable Windows Copilot (user level)
$CopilotUser = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $CopilotUser)) { New-Item -Path $CopilotUser -Force | Out-Null }
Set-ItemProperty -Path $CopilotUser -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
Write-RiskLog "Windows Copilot disabled (user)" "safe" "OK"

# Disable Windows Recall
$WindowsAIPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
if (-not (Test-Path $WindowsAIPath)) { New-Item -Path $WindowsAIPath -Force | Out-Null }
Set-ItemProperty -Path $WindowsAIPath -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
Write-RiskLog "Windows Recall disabled" "safe" "OK"

# Disable Copilot via machine policy
$CopilotMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $CopilotMachine)) { New-Item -Path $CopilotMachine -Force | Out-Null }
Set-ItemProperty -Path $CopilotMachine -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
Write-RiskLog "Windows Copilot disabled (machine policy)" "safe" "OK"

# ============================================================================
# 7o. Feedback
# ============================================================================
Write-Log "Configuring feedback settings..."

$FeedbackPath = "HKCU:\Software\Microsoft\Siuf\Rules"
if (-not (Test-Path $FeedbackPath)) { New-Item -Path $FeedbackPath -Force | Out-Null }

# Disable feedback notifications
Set-ItemProperty -Path $FeedbackPath -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord
Write-RiskLog "Feedback notifications disabled" "safe" "OK"

# Disable feedback frequency
Set-ItemProperty -Path $FeedbackPath -Name "PeriodInNanoSeconds" -Value 0 -Type DWord
Write-RiskLog "Feedback frequency set to never" "safe" "OK"

# ============================================================================
# 7p. Optional: Telemetry Hosts Blocking
# ============================================================================

function Block-TelemetryHosts {
    <#
    .SYNOPSIS
        Appends known Microsoft telemetry domains to the Windows hosts file.
        Only runs when $script:BlockTelemetryHosts is $true.
    #>
    if (-not $script:BlockTelemetryHosts) {
        Write-Log "Telemetry hosts blocking skipped (BlockTelemetryHosts = false)" "INFO"
        return
    }

    Write-Log "Blocking telemetry hosts via hosts file..."

    $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
    $marker    = "# --- WinInit Telemetry Block ---"

    $telemetryHosts = @(
        "0.0.0.0 vortex.data.microsoft.com",
        "0.0.0.0 vortex-win.data.microsoft.com",
        "0.0.0.0 telecommand.telemetry.microsoft.com",
        "0.0.0.0 telemetry.microsoft.com",
        "0.0.0.0 settings-win.data.microsoft.com",
        "0.0.0.0 watson.telemetry.microsoft.com",
        "0.0.0.0 watson.microsoft.com",
        "0.0.0.0 oca.telemetry.microsoft.com",
        "0.0.0.0 sqm.telemetry.microsoft.com",
        "0.0.0.0 choice.microsoft.com",
        "0.0.0.0 df.telemetry.microsoft.com",
        "0.0.0.0 reports.wes.df.telemetry.microsoft.com",
        "0.0.0.0 cs1.wpc.v0cdn.net",
        "0.0.0.0 vortex-sandbox.data.microsoft.com",
        "0.0.0.0 survey.watson.microsoft.com",
        "0.0.0.0 watson.ppe.telemetry.microsoft.com",
        "0.0.0.0 telemetry.appex.bing.net",
        "0.0.0.0 telemetry.urs.microsoft.com",
        "0.0.0.0 pre.footprintpredict.com",
        "0.0.0.0 i1.services.social.microsoft.com"
    )

    try {
        # Check if we already added entries (avoid duplicates on re-run)
        $existingContent = Get-Content -Path $hostsFile -Raw -ErrorAction SilentlyContinue
        if ($existingContent -and $existingContent.Contains($marker)) {
            Write-RiskLog "Telemetry hosts already present in hosts file - skipping" "aggressive" "INFO"
            return
        }

        # Build block to append
        $block = @()
        $block += ""
        $block += $marker
        $block += "# Added by WinInit on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $block += $telemetryHosts
        $block += "# --- End WinInit Telemetry Block ---"

        Add-Content -Path $hostsFile -Value ($block -join "`r`n") -Encoding ASCII -ErrorAction Stop

        $addedCount = $telemetryHosts.Count
        Write-RiskLog "Blocked $addedCount telemetry domains via hosts file" "aggressive" "OK"
    } catch {
        Write-RiskLog "Failed to modify hosts file: $_" "aggressive" "ERROR"
    }
}

# Execute the hosts blocking function (respects $script:BlockTelemetryHosts flag)
Block-TelemetryHosts

Write-Log "Module 07-Privacy completed" "OK"
