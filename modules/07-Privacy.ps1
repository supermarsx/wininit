# Module: 07 - Privacy
# Wi-Fi Sense, clipboard cloud sync, timeline, SmartScreen, delivery optimization

Write-Section "Privacy (Additional)"

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
Write-Log "Wi-Fi Sense disabled" "OK"

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
Write-Log "Clipboard cloud sync disabled" "OK"

# --- 7c. Disable Timeline ---
Write-Log "Disabling Timeline..."
# Already partially done in telemetry section, reinforce here
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed"    -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities"  -Value 0 -Type DWord
Write-Log "Timeline disabled" "OK"

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
Write-Log "SmartScreen for apps disabled" "OK"

# --- 7e. Disable Delivery Optimization (P2P Updates) ---
Write-Log "Disabling Delivery Optimization..."
$DOPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
if (-not (Test-Path $DOPath)) { New-Item -Path $DOPath -Force | Out-Null }
Set-ItemProperty -Path $DOPath -Name "DODownloadMode" -Value 0 -Type DWord  # 0 = off
$DOUserPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
if (-not (Test-Path $DOUserPath)) { New-Item -Path $DOUserPath -Force | Out-Null }
Set-ItemProperty -Path $DOUserPath -Name "DODownloadMode" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Delivery Optimization (P2P updates) disabled" "OK"

Write-Log "Module 07-Privacy completed" "OK"
