# Module: 05 - Performance
# ============================================================================
Write-Section "Section 5: Performance" "SysMain, Game Bar, hibernation, background apps"

# Suppress progress bars and warnings from Appx/DISM cmdlets
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# --- 5a. Disable SysMain / Superfetch Completely ---
Write-Log "Disabling SysMain (Superfetch)..."
Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
# Also kill the registry key that can re-enable it
$SysMainPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SysMain"
if (Test-Path $SysMainPath) {
    Set-ItemProperty -Path $SysMainPath -Name "Start" -Value 4 -Type DWord  # 4 = Disabled
}
# Disable Prefetch as well (Superfetch companion)
$PrefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
if (Test-Path $PrefetchPath) {
    Set-ItemProperty -Path $PrefetchPath -Name "EnableSuperfetch" -Value 0 -Type DWord
    Set-ItemProperty -Path $PrefetchPath -Name "EnablePrefetcher"  -Value 0 -Type DWord
}
Write-Log "SysMain and Prefetch fully disabled" "OK"

# --- 5b. Disable Game Bar / Game DVR Completely ---
Write-Log "Disabling Game Bar and Game DVR..."
# User-level Game Bar toggle
$GameBarPath = "HKCU:\Software\Microsoft\GameBar"
if (-not (Test-Path $GameBarPath)) { New-Item -Path $GameBarPath -Force | Out-Null }
Set-ItemProperty -Path $GameBarPath -Name "AllowAutoGameMode"    -Value 0 -Type DWord
Set-ItemProperty -Path $GameBarPath -Name "AutoGameModeEnabled"  -Value 0 -Type DWord
Set-ItemProperty -Path $GameBarPath -Name "ShowStartupPanel"     -Value 0 -Type DWord
Set-ItemProperty -Path $GameBarPath -Name "GamePanelStartupTipIndex" -Value 3 -Type DWord
Set-ItemProperty -Path $GameBarPath -Name "UseNexusForGameBarEnabled" -Value 0 -Type DWord

# Game DVR
$GameDVRPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
if (-not (Test-Path $GameDVRPath)) { New-Item -Path $GameDVRPath -Force | Out-Null }
Set-ItemProperty -Path $GameDVRPath -Name "AppCaptureEnabled" -Value 0 -Type DWord

$GameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $GameDVRPolicy)) { New-Item -Path $GameDVRPolicy -Force | Out-Null }
Set-ItemProperty -Path $GameDVRPolicy -Name "AllowGameDVR" -Value 0 -Type DWord

# Game Bar via policy
$GameConfigStore = "HKCU:\System\GameConfigStore"
if (-not (Test-Path $GameConfigStore)) { New-Item -Path $GameConfigStore -Force | Out-Null }
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_Enabled"             -Value 0 -Type DWord
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_FSEBehaviorMode"     -Value 2 -Type DWord
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_FSEBehavior"         -Value 2 -Type DWord
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -Type DWord
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord
Set-ItemProperty -Path $GameConfigStore -Name "GameDVR_EFSEFeatureFlags"    -Value 0 -Type DWord

# Disable Game Mode
$GameModePath = "HKCU:\Software\Microsoft\GameBar"
Set-ItemProperty -Path $GameModePath -Name "AutoGameModeEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Remove Xbox Game Bar app
Get-AppxPackage -Name "Microsoft.XboxGamingOverlay" -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null
Get-AppxPackage -Name "Microsoft.XboxGameOverlay"   -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null
Write-Log "Game Bar, Game DVR, and Game Mode fully disabled" "OK"

# --- 5c. Disable Hibernation (frees disk space) ---
Write-Log "Disabling hibernation..."
powercfg /hibernate off >$null 2>&1
Write-Log "Hibernation disabled (hiberfil.sys freed)" "OK"

# --- 5d. Disable Background Apps ---
Write-Log "Disabling background apps..."
$BgAppsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
if (-not (Test-Path $BgAppsPath)) { New-Item -Path $BgAppsPath -Force | Out-Null }
Set-ItemProperty -Path $BgAppsPath -Name "GlobalUserDisabled" -Value 1 -Type DWord
$BgAppsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
if (-not (Test-Path $BgAppsPolicy)) { New-Item -Path $BgAppsPolicy -Force | Out-Null }
Set-ItemProperty -Path $BgAppsPolicy -Name "LetAppsRunInBackground" -Value 2 -Type DWord  # 2 = Force Deny
Write-Log "Background apps disabled" "OK"

Write-Log "Section 5: Performance completed" "OK"
