# Module: 11 - Visual / UX Tweaks
# Transparency, aero shake, start menu, desktop icons, This PC sidebar cleanup

Write-Section "Visual / UX Tweaks"

# --- 11a. Disable Transparency / Glass / Blur Effects ---
Write-Log "Disabling all transparency, glass, and blur effects..."
$themePers = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-ItemProperty -Path $themePers -Name "EnableTransparency" -Value 0 -Type DWord
$dwmPath = "HKCU:\Software\Microsoft\Windows\DWM"
Set-ItemProperty -Path $dwmPath -Name "EnableAeroPeek"          -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $dwmPath -Name "ColorizationOpaqueBlend" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Disable all visual animations (menu fade, window animate, tooltip fade, etc.)
$visualFx = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
if (-not (Test-Path $visualFx)) { New-Item -Path $visualFx -Force | Out-Null }
Set-ItemProperty -Path $visualFx -Name "VisualFXSetting" -Value 3 -Type DWord  # 3 = custom
# Granular visual effects via UserPreferencesMask
$desktopPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $desktopPath -Name "DragFullWindows"   -Value "1" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $desktopPath -Name "FontSmoothing"     -Value "2" -Type String -ErrorAction SilentlyContinue
# Disable window animations
$desktopWM = "HKCU:\Control Panel\Desktop\WindowMetrics"
Set-ItemProperty -Path $desktopWM -Name "MinAnimate" -Value "0" -Type String -ErrorAction SilentlyContinue
Write-Log "Transparency, glass, blur, and animations disabled" "OK"

# --- 11a2. Disable Aero Shake ---
Write-Log "Disabling Aero Shake (minimize all by shaking)..."
$ShakePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $ShakePath -Name "DisallowShaking" -Value 1 -Type DWord
# Also via policy
$ShakePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $ShakePolicyPath)) { New-Item -Path $ShakePolicyPath -Force | Out-Null }
Set-ItemProperty -Path $ShakePolicyPath -Name "NoWindowMinimizingShortcuts" -Value 1 -Type DWord
Write-Log "Aero Shake disabled" "OK"

# --- 11b. Disable Start Menu Recommendations & Categories ---
Write-Log "Disabling Start Menu recommendations and categories..."
$StartPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Disable "Show recommendations" in Start
Set-ItemProperty -Path $StartPath -Name "Start_IrisRecommendations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable "Show recently added apps"
Set-ItemProperty -Path $StartPath -Name "Start_TrackProgs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable "Show most used apps"
Set-ItemProperty -Path $StartPath -Name "Start_TrackDocs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable account-related notifications in Start
Set-ItemProperty -Path $StartPath -Name "Start_AccountNotifications" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Policy level: disable recommendations/tips
$StartPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $StartPolicyPath)) { New-Item -Path $StartPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $StartPolicyPath -Name "HideRecommendedSection" -Value 1 -Type DWord
Set-ItemProperty -Path $StartPolicyPath -Name "HideRecentlyAddedApps"  -Value 1 -Type DWord

# Disable Start layout categories (Win 11 22H2+)
$StartLayout = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
Set-ItemProperty -Path $StartLayout -Name "ShowRecentList"    -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $StartLayout -Name "ShowFrequentList"  -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Set Start layout to "More pins" = pins only, no recommendations
Set-ItemProperty -Path $StartPath -Name "Start_Layout" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Hide "All apps" button completely
Set-ItemProperty -Path $StartLayout -Name "ShowAllApps" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $StartPath -Name "ShowAllApps" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Policy: hide all apps list and most used apps
$StartAllAppsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $StartAllAppsPolicy)) { New-Item -Path $StartAllAppsPolicy -Force | Out-Null }
Set-ItemProperty -Path $StartAllAppsPolicy -Name "ShowOrHideMostUsedApps" -Value 2 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $StartAllAppsPolicy -Name "HideRecommendedPersonalizedSites" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# VisiblePlaces: empty = hide both Recommended AND All Apps sections
# Setting to all zeros hides everything except pins
Set-ItemProperty -Path $StartLayout -Name "VisiblePlaces" -Value ([byte[]]@(
    0x86, 0x08, 0x73, 0x52, 0xAA, 0x51, 0x43, 0x42,
    0x9F, 0x7B, 0x27, 0x76, 0x58, 0x4E, 0xE7, 0x5A,
    0xBC, 0x24, 0x8A, 0x14, 0x0C, 0xD6, 0x89, 0x42,
    0xA8, 0x63, 0xBA, 0x64, 0x5C, 0x22, 0x3C, 0xB6
)) -Type Binary -ErrorAction SilentlyContinue
# Also set via the Advanced key
Set-ItemProperty -Path $StartPath -Name "VisiblePlaces" -Value ([byte[]]@(
    0x86, 0x08, 0x73, 0x52, 0xAA, 0x51, 0x43, 0x42,
    0x9F, 0x7B, 0x27, 0x76, 0x58, 0x4E, 0xE7, 0x5A,
    0xBC, 0x24, 0x8A, 0x14, 0x0C, 0xD6, 0x89, 0x42,
    0xA8, 0x63, 0xBA, 0x64, 0x5C, 0x22, 0x3C, 0xB6
)) -Type Binary -ErrorAction SilentlyContinue
# Hide the "All apps" toggle button at top right of Start
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Start" /v "ShowAllApps" /t REG_DWORD /d 0 /f >$null 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_Layout" /t REG_DWORD /d 1 /f >$null 2>&1
Write-Log "Start Menu: pins only, all apps/recommendations/groups hidden" "OK"

# --- 11c. Hide ALL Desktop Icons ---
Write-Log "Hiding all desktop icons..."
$DesktopIconPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $DesktopIconPath -Name "HideIcons" -Value 1 -Type DWord
# Also disable the default icons (This PC, Recycle Bin, Network, etc.)
$NewStartPanel = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
if (-not (Test-Path $NewStartPanel)) { New-Item -Path $NewStartPanel -Force | Out-Null }
# This PC
Set-ItemProperty -Path $NewStartPanel -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 1 -Type DWord
# Recycle Bin
Set-ItemProperty -Path $NewStartPanel -Name "{645FF040-5081-101B-9F08-00AA002F954E}" -Value 1 -Type DWord
# Network
Set-ItemProperty -Path $NewStartPanel -Name "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}" -Value 1 -Type DWord
# User Files
Set-ItemProperty -Path $NewStartPanel -Name "{59031a47-3f72-44a7-89c5-5595fe6b30ee}" -Value 1 -Type DWord
# Control Panel
Set-ItemProperty -Path $NewStartPanel -Name "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}" -Value 1 -Type DWord
Write-Log "All desktop icons hidden" "OK"

# --- 11d. Remove 3D Objects, Music, Videos, Pictures from This PC Sidebar ---
Write-Log "Removing 3D Objects, Music, Videos, Pictures from This PC sidebar..."
$thisPcFolders = @{
    # 3D Objects
    "{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" = "3D Objects"
    # Music
    "{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}" = "Music"
    # Videos
    "{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}" = "Videos"
    # Pictures
    "{24ad3ad4-a569-4530-98e1-ab02f9417aa8}" = "Pictures"
}

foreach ($guid in $thisPcFolders.Keys) {
    $name = $thisPcFolders[$guid]
    # 64-bit path
    $path64 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\$guid"
    if (Test-Path $path64) {
        Remove-Item $path64 -Force -ErrorAction SilentlyContinue
        Write-Log "Removed $name from This PC (64-bit)" "OK"
    }
    # 32-bit (WOW6432Node) path
    $path32 = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\$guid"
    if (Test-Path $path32) {
        Remove-Item $path32 -Force -ErrorAction SilentlyContinue
        Write-Log "Removed $name from This PC (32-bit)" "OK"
    }
    # Also hide from "This PC" folder listing via ThisPCPolicy
    $folderDescPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$guid\PropertyBag"
    if (-not (Test-Path $folderDescPath)) { New-Item -Path $folderDescPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $folderDescPath -Name "ThisPCPolicy" -Value "Hide" -Type String -ErrorAction SilentlyContinue
}
Write-Log "3D Objects, Music, Videos, Pictures removed from This PC sidebar" "OK"

Write-Log "Module 11-VisualUX completed" "OK"
