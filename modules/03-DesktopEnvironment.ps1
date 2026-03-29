# Module: 03 - Desktop Environment
# ============================================================================
Write-Section "Section 3: Desktop Environment" "Dark mode, wallpaper, accent, taskbar, explorer, context menu, mouse, power, ads, telemetry annihilation"

# Suppress progress bars and warnings from Appx/DISM cmdlets
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# --- 3a. Dark Mode (System + Apps + Legacy Win32) ---
Write-Log "Enabling system-wide dark mode (including legacy apps)..."
$ThemePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
Set-ItemProperty -Path $ThemePath -Name "AppsUseLightTheme"    -Value 0 -Type DWord
Set-ItemProperty -Path $ThemePath -Name "SystemUsesLightTheme" -Value 0 -Type DWord

# Force dark mode on ALL legacy/Win32 windows (immersive dark mode)
$DWMPath = "HKCU:\Software\Microsoft\Windows\DWM"
# Dark title bars on legacy apps
Set-ItemProperty -Path $DWMPath -Name "EnableWindowColorization"     -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DWMPath -Name "AccentColorInactive"          -Value 0xFF2B2B2B -Type DWord -ErrorAction SilentlyContinue

# Force dark mode for Win32 apps via undocumented UxTheme registry
$UxTheme = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes"
Set-ItemProperty -Path $UxTheme -Name "AppsUseLightTheme" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Dark scrollbars for legacy apps
$ScrollPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
if (-not (Test-Path $ScrollPath)) { New-Item -Path $ScrollPath -Force | Out-Null }
Set-ItemProperty -Path $ScrollPath -Name "StartColorMenu"  -Value 0xFF343434 -Type DWord -ErrorAction SilentlyContinue

# High contrast dark colors for legacy dialogs (file open/save, print, etc.)
$ColorsPath = "HKCU:\Control Panel\Colors"
Set-ItemProperty -Path $ColorsPath -Name "Window"     -Value "30 30 35"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "WindowText" -Value "220 220 220" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "ButtonFace" -Value "45 45 48"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "ButtonText" -Value "220 220 220" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "GrayText"   -Value "140 140 140" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "Hilight"    -Value "80 100 120" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "HilightText" -Value "255 255 255" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "Menu"       -Value "35 35 38"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "MenuText"   -Value "220 220 220" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "Scrollbar"  -Value "40 40 43"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "Background" -Value "30 30 35"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "AppWorkspace" -Value "35 35 38" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "WindowFrame" -Value "50 50 55" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "InfoWindow" -Value "40 40 43"  -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "InfoText"   -Value "220 220 220" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "ActiveTitle" -Value "45 45 48" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "InactiveTitle" -Value "35 35 38" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "TitleText"  -Value "220 220 220" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "InactiveTitleText" -Value "160 160 160" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "ActiveBorder" -Value "50 50 55" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ColorsPath -Name "InactiveBorder" -Value "40 40 43" -Type String -ErrorAction SilentlyContinue

Write-Log "Dark mode enabled (system + apps + legacy Win32 + dark colors)" "OK"

# --- 3b. Wallpaper - Dark Graphite ---
Write-Log "Setting wallpaper to dark graphite..."
# Create a 1x1 dark graphite BMP to use as wallpaper
$wallpaperDir  = Join-Path $env:APPDATA "WinInit"
$wallpaperPath = Join-Path $wallpaperDir "graphite.bmp"
if (-not (Test-Path $wallpaperDir)) { New-Item -ItemType Directory -Path $wallpaperDir -Force | Out-Null }

Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(1, 1)
# Dark graphite: RGB(30, 30, 35) - dark but not pure black
$bmp.SetPixel(0, 0, [System.Drawing.Color]::FromArgb(30, 30, 35))
$bmp.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
$bmp.Dispose()

# Set wallpaper style: stretched (2), tiled off
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "2"
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper"  -Value "0"

# Apply wallpaper via SystemParametersInfo
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE   = 0x01;
    public const int SPIF_SENDCHANGE      = 0x02;
    public static void Set(string path) {
        SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
"@
[Wallpaper]::Set($wallpaperPath)
Write-Log "Wallpaper set to dark graphite" "OK"

# --- 3c. Accent Color - Slate ---
Write-Log "Setting accent color to slate..."
$DWMPath = "HKCU:\Software\Microsoft\Windows\DWM"
# Slate accent: ABGR format - Slate grey (#708090 RGB = 0xFF908070 ABGR)
Set-ItemProperty -Path $DWMPath    -Name "AccentColor"          -Value 0xFF908070 -Type DWord
Set-ItemProperty -Path $DWMPath    -Name "ColorizationColor"    -Value 0xFF908070 -Type DWord
Set-ItemProperty -Path $DWMPath    -Name "ColorizationAfterglow" -Value 0xFF908070 -Type DWord
# Disable accent color on Start, taskbar, action center (keep taskbar dark/neutral)
Set-ItemProperty -Path $ThemePath  -Name "ColorPrevalence"       -Value 0 -Type DWord
# Disable accent color on title bars and window borders (keep neutral)
Set-ItemProperty -Path $DWMPath    -Name "ColorPrevalence"       -Value 0 -Type DWord
# Disable transparency/glass effects (no blur, no acrylic, solid colors)
Set-ItemProperty -Path $ThemePath  -Name "EnableTransparency"    -Value 0 -Type DWord
# Disable DWM glass/blur
Set-ItemProperty -Path $DWMPath    -Name "ColorizationOpaqueBlend" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DWMPath    -Name "EnableAeroPeek"        -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $DWMPath    -Name "AlwaysHibernateThumbnails" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Also set the accent color in the Windows theme accent palette
$AccentPalette = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
if (-not (Test-Path $AccentPalette)) { New-Item -Path $AccentPalette -Force | Out-Null }
# AccentPalette is 32 bytes: 8 colors x 4 bytes (ABGR), lightest to darkest
$slatepalette = [byte[]](
    0xB0,0xC4,0xDE,0x00,  # LightSteelBlue
    0x9E,0xA8,0xBB,0x00,  # Light slate
    0x8C,0x96,0xA8,0x00,  # Medium light
    0x70,0x80,0x90,0x00,  # Slate Grey (main)
    0x5A,0x6A,0x7A,0x00,  # Medium dark
    0x47,0x53,0x5F,0x00,  # Dark slate
    0x2F,0x3B,0x47,0x00,  # Darker
    0x1E,0x28,0x32,0x00   # Darkest
)
Set-ItemProperty -Path $AccentPalette -Name "AccentPalette" -Value $slatepalette -Type Binary -ErrorAction SilentlyContinue
Set-ItemProperty -Path $AccentPalette -Name "AccentColorMenu" -Value 0xFF908070 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $AccentPalette -Name "StartColorMenu" -Value 0xFF5F4735 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Accent color set to slate" "OK"

# --- 3d. Taskbar Customization ---
Write-Log "Customizing taskbar..."
$TaskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Small taskbar icons (Windows 10) / compact mode
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarSmallIcons" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Always combine taskbar buttons - show icons only, no labels (0 = always, 1 = when full, 2 = never)
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarGlomLevel" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Win 11 23H2+: separate setting for "never combine" override
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarEndTask" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TaskbarPath -Name "MMTaskbarGlomLevel" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Hide Task View button
Set-ItemProperty -Path $TaskbarPath -Name "ShowTaskViewButton" -Value 0 -Type DWord
# Hide Search COMPLETELY (0 = hidden, 1 = icon, 2 = box)
$SearchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
if (-not (Test-Path $SearchPath)) { New-Item -Path $SearchPath -Force | Out-Null }
Set-ItemProperty -Path $SearchPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord
# === FULL BING / WEB SEARCH / CLOUD ANNIHILATION ===
# Disable Bing in Start Menu search results
Set-ItemProperty -Path $SearchPath -Name "BingSearchEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPath -Name "CortanaConsent" -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPath -Name "AllowSearchToUseLocation" -Value 0 -Type DWord
# Disable search highlights (trending searches, news, "interesting" items)
Set-ItemProperty -Path $SearchPath -Name "IsDynamicSearchBoxEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable cloud content in search (Microsoft account, OneDrive, Outlook, etc.)
$CloudSearch = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
if (-not (Test-Path $CloudSearch)) { New-Item -Path $CloudSearch -Force | Out-Null }
Set-ItemProperty -Path $CloudSearch -Name "IsAADCloudSearchEnabled"     -Value 0 -Type DWord  # Azure AD cloud search
Set-ItemProperty -Path $CloudSearch -Name "IsMSACloudSearchEnabled"     -Value 0 -Type DWord  # Microsoft Account cloud search
Set-ItemProperty -Path $CloudSearch -Name "IsDeviceSearchHistoryEnabled" -Value 0 -Type DWord  # Device search history
Set-ItemProperty -Path $CloudSearch -Name "SafeSearchMode"              -Value 0 -Type DWord  # No safe search filtering needed
# Disable search suggestions and recent searches
$SearchSuggest = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $SearchSuggest -Name "Start_SearchFiles" -Value 1 -Type DWord -ErrorAction SilentlyContinue  # 1 = don't search internet
# Policy-level: FULLY disable all web/cloud/Bing in search
$SearchPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (-not (Test-Path $SearchPolicyPath)) { New-Item -Path $SearchPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $SearchPolicyPath -Name "DisableWebSearch"              -Value 1 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "ConnectedSearchUseWeb"         -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "ConnectedSearchUseWebOverMeteredConnections" -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "AllowSearchToUseLocation"      -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "AllowCloudSearch"              -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "AllowCortana"                  -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "AllowCortanaAboveLock"         -Value 0 -Type DWord
Set-ItemProperty -Path $SearchPolicyPath -Name "EnableDynamicContentInWSB"     -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $SearchPolicyPath -Name "DisableRemovableDriveIndexing" -Value 1 -Type DWord
# Disable Bing in Start Menu via Explorer policy
$ExplorerPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $ExplorerPolicy)) { New-Item -Path $ExplorerPolicy -Force | Out-Null }
Set-ItemProperty -Path $ExplorerPolicy -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord
# Disable "Search the web" prompt in Start
$StartSearchPolicy = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
if (-not (Test-Path $StartSearchPolicy)) { New-Item -Path $StartSearchPolicy -Force | Out-Null }
Set-ItemProperty -Path $StartSearchPolicy -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord
# Block Bing domains in hosts file (belt and suspenders with existing telemetry block)
$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$bingHosts = @(
    "www.bing.com",
    "bing.com",
    "api.bing.com",
    "tse1.mm.bing.net",
    "tse2.mm.bing.net",
    "th.bing.com",
    "edgeservices.bing.com",
    "www.bingapis.com",
    "bingapis.com",
    "api.bingapis.com",
    "business.bing.com",
    "copilot.microsoft.com",
    "sydney.bing.com",
    "r.bing.com",
    "c.bing.com",
    "suggested.bing.com",
    "fd.api.iris.microsoft.com",
    "assets.msn.com",
    "api.msn.com",
    "ntp.msn.com",
    "srtb.msn.com",
    "www.msn.com",
    "arc.msn.com",
    "img-s-msn-com.akamaized.net"
)
$hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
$bingMarker = "# --- WinInit Bing/Search Block ---"
if ($hostsContent -notmatch [regex]::Escape($bingMarker)) {
    $block = "`n$bingMarker`n"
    foreach ($h in $bingHosts) {
        $block += "0.0.0.0 $h`n"
    }
    $block += "# --- End WinInit Bing/Search Block ---"
    Add-Content -Path $hostsFile -Value $block -Encoding ASCII
    Write-Log "Bing/MSN/Copilot domains blocked in hosts file ($($bingHosts.Count) entries)" "OK"
} else {
    Write-Log "Bing domains already blocked in hosts file" "OK"
}
Write-Log "Bing, web search, cloud search, search highlights - ALL killed" "OK"
# Hide Widgets button (Win 11) - registry + policy
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarDa" -Value 0 -Type DWord -ErrorAction SilentlyContinue
$WidgetsPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
if (-not (Test-Path $WidgetsPolicyPath)) { New-Item -Path $WidgetsPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $WidgetsPolicyPath -Name "AllowNewsAndInterests" -Value 0 -Type DWord
# Also disable via the Windows 10 News and Interests path
$FeedsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
if (-not (Test-Path $FeedsPath)) { New-Item -Path $FeedsPath -Force | Out-Null }
Set-ItemProperty -Path $FeedsPath -Name "EnableFeeds" -Value 0 -Type DWord
# Hide Chat icon (Win 11)
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarMn" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Left-align taskbar (Win 11: 0 = left, 1 = center)
# Centered taskbar icons (Win 11: 0 = left, 1 = center)
Set-ItemProperty -Path $TaskbarPath -Name "TaskbarAl" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Hide Copilot button
Set-ItemProperty -Path $TaskbarPath -Name "ShowCopilotButton" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Taskbar customized (search/widgets/chat/copilot all hidden)" "OK"

# --- 3d2. Unpin Default Apps & Pin Custom Apps to Taskbar ---
Write-Log "Configuring taskbar pins..."

# Unpin Edge, Store, Mail, and other default-pinned junk
# Win 11 stores pins in a binary blob - we rewrite it with only what we want
$TaskbarPinDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"

# Remove all existing shortcuts in the taskbar pin folder
if (Test-Path $TaskbarPinDir) {
    Get-ChildItem $TaskbarPinDir -Filter "*.lnk" | ForEach-Object {
        $name = $_.BaseName.ToLower()
        # Remove Edge, Store, Mail, and other MS bloat pins
        if ($name -match "edge|store|mail|outlook|office|teams|xbox|cortana|phone|your phone|todo|onedrive|skype|copilot") {
            Remove-Item $_.FullName -Force
            Write-Log "Unpinned: $($_.BaseName)" "OK"
        }
    }
}

# Also purge Outlook pin from Start Menu programs
$startMenuPaths = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
)
foreach ($smPath in $startMenuPaths) {
    if (Test-Path $smPath) {
        Get-ChildItem $smPath -Recurse -Filter "*.lnk" | Where-Object {
            $_.BaseName -match "Outlook|Edge|Microsoft Store|Store"
        } | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Removed Start Menu shortcut: $($_.BaseName)" "OK"
        }
    }
}

# Create shortcuts for File Explorer and Windows Terminal
$WshShell = New-Object -ComObject WScript.Shell

# Pin File Explorer
$explorerLnk = Join-Path $TaskbarPinDir "File Explorer.lnk"
if (-not (Test-Path $explorerLnk)) {
    $shortcut = $WshShell.CreateShortcut($explorerLnk)
    $shortcut.TargetPath = "$env:WINDIR\explorer.exe"
    $shortcut.Description = "File Explorer"
    $shortcut.Save()
    Write-Log "Pinned File Explorer to taskbar" "OK"
}

# Pin Windows Terminal
$terminalLnk = Join-Path $TaskbarPinDir "Terminal.lnk"
if (-not (Test-Path $terminalLnk)) {
    $wtPath = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
    if (-not $wtPath) {
        $wtPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
    }
    if (Test-Path $wtPath) {
        $shortcut = $WshShell.CreateShortcut($terminalLnk)
        $shortcut.TargetPath = $wtPath
        $shortcut.Description = "Windows Terminal"
        $shortcut.Save()
        Write-Log "Pinned Windows Terminal to taskbar" "OK"
    } else {
        Write-Log "Windows Terminal not found - skipping pin" "WARN"
    }
}

# Pin Firefox
$firefoxLnk = Join-Path $TaskbarPinDir "Firefox.lnk"
if (-not (Test-Path $firefoxLnk)) {
    $ffPath = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
    if (Test-Path $ffPath) {
        $shortcut = $WshShell.CreateShortcut($firefoxLnk)
        $shortcut.TargetPath = $ffPath
        $shortcut.Description = "Mozilla Firefox"
        $shortcut.Save()
        Write-Log "Pinned Firefox to taskbar" "OK"
    }
}

# For Win 11: also manipulate the Start Menu pinned layout to remove bloat
$StartLayoutPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
# Remove all pinned Start tiles
Set-ItemProperty -Path $StartLayoutPath -Name "ShowRecentList"    -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $StartLayoutPath -Name "ShowFrequentList"  -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Taskbar pins configured" "OK"

# --- 3e. File Explorer Settings ---
Write-Log "Customizing File Explorer..."
$ExplorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# Show file extensions
Set-ItemProperty -Path $ExplorerPath -Name "HideFileExt" -Value 0 -Type DWord
# Show hidden files
Set-ItemProperty -Path $ExplorerPath -Name "Hidden" -Value 1 -Type DWord
# Show protected OS files
Set-ItemProperty -Path $ExplorerPath -Name "ShowSuperHidden" -Value 1 -Type DWord
# Show full path in title bar
Set-ItemProperty -Path $ExplorerPath -Name "FullPath" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Launch File Explorer to "This PC" instead of "Quick Access"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -Type DWord
# Expand navigation pane to current folder
Set-ItemProperty -Path $ExplorerPath -Name "NavPaneExpandToCurrentFolder" -Value 1 -Type DWord
# Disable recent files in Quick Access
Set-ItemProperty -Path $ExplorerPath -Name "Start_TrackDocs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable "Show recently used files" in Quick Access
Set-ItemProperty -Path $ExplorerPath -Name "Start_TrackProgs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable frequent folders in Quick Access
$QAPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
Set-ItemProperty -Path $QAPath -Name "ShowRecent"   -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $QAPath -Name "ShowFrequent" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Clear existing recent files and frequent folders
$recentFolder = [System.Environment]::GetFolderPath("Recent")
if (Test-Path $recentFolder) {
    Remove-Item "$recentFolder\*" -Recurse -Force -ErrorAction SilentlyContinue
}
$autoDestinations = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
if (Test-Path $autoDestinations) {
    Remove-Item "$autoDestinations\*" -Force -ErrorAction SilentlyContinue
}
$customDestinations = "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
if (Test-Path $customDestinations) {
    Remove-Item "$customDestinations\*" -Force -ErrorAction SilentlyContinue
}
Write-Log "File Explorer: no recent files, no frequent folders, opens to This PC" "OK"

# --- 3f. Context Menu - Restore Classic (Win 11) ---
Write-Log "Restoring classic right-click context menu..."
$ContextMenuKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
if (-not (Test-Path $ContextMenuKey)) {
    New-Item -Path $ContextMenuKey -Force | Out-Null
}
Set-ItemProperty -Path $ContextMenuKey -Name "(default)" -Value "" -Type String
Write-Log "Classic context menu restored" "OK"

# --- Remove WinMerge from context menu ---
Write-Log "Removing WinMerge from context menu..."
# Use reg.exe directly - much faster than Test-Path on HKCR
$wmKeys = @(
    "HKCR\*\shellex\ContextMenuHandlers\WinMerge",
    "HKCR\Directory\shellex\ContextMenuHandlers\WinMerge",
    "HKCR\Directory\Background\shellex\ContextMenuHandlers\WinMerge",
    "HKCR\Folder\shellex\ContextMenuHandlers\WinMerge",
    "HKCR\*\shell\WinMerge",
    "HKCR\Directory\shell\WinMerge"
)
foreach ($key in $wmKeys) {
    reg delete $key /f >$null 2>&1
}
Write-Log "WinMerge removed from context menu" "OK"

# --- 3g. Mouse & Cursor ---
Write-Log "Disabling mouse acceleration..."
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed"      -Value "0"
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0"
Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0"
Write-Log "Mouse acceleration disabled" "OK"

# --- 3h. Disable Windows Search Service ---
Write-Log "Disabling Windows Search service and indexing..."
# Stop and disable the WSearch service
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
# Disable indexing on all drives via fsutil (most reliable, works on all volumes)
$drives = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in @(2, 3) }
foreach ($drv in $drives) {
    $letter = $drv.DeviceID  # e.g. "C:"
    try {
        # fsutil behavior set disableindexing 1 per-volume
        fsutil behavior set disable8dot3 "$letter" 1 >$null 2>&1
        # Disable content indexing attribute on drive root
        $root = "$letter\"
        if (Test-Path $root) {
            $dirInfo = New-Object System.IO.DirectoryInfo($root)
            if ($dirInfo.Attributes -band [System.IO.FileAttributes]::NotContentIndexed) {
                Write-Log "Indexing already disabled on $letter" "OK"
            } else {
                $dirInfo.Attributes = $dirInfo.Attributes -bor [System.IO.FileAttributes]::NotContentIndexed
                Write-Log "Indexing disabled on $letter" "OK"
            }
        }
    } catch {
        Write-Log "Could not disable indexing on $letter - $_" "WARN"
    }
}
# Also try WMI method as belt-and-suspenders (silently, some volumes reject Put())
$wmiVolumes = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter IS NOT NULL" -ErrorAction SilentlyContinue
foreach ($vol in $wmiVolumes) {
    try {
        if ($vol.IndexingEnabled) {
            $vol.IndexingEnabled = $false
            $vol.Put() | Out-Null
        }
    } catch {}
}
# Disable search indexer via policy
$SearchIdxPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (-not (Test-Path $SearchIdxPolicy)) { New-Item -Path $SearchIdxPolicy -Force | Out-Null }
Set-ItemProperty -Path $SearchIdxPolicy -Name "AllowSearchToUseLocation" -Value 0 -Type DWord
Set-ItemProperty -Path $SearchIdxPolicy -Name "PreventIndexingLowDiskSpaceMB" -Value 999999 -Type DWord
# Disable indexer globally via policy
Set-ItemProperty -Path $SearchIdxPolicy -Name "PreventIndexOnBattery" -Value 1 -Type DWord
Set-ItemProperty -Path $SearchIdxPolicy -Name "DisableBackoff" -Value 1 -Type DWord
# Note: "Everything" app replaces Windows Search with superior performance
Write-Log "Windows Search service disabled (use Everything app instead)" "OK"

# --- 3i. Power Settings (prevent sleep on AC) ---
Write-Log "Setting power plan: never sleep on AC..."
powercfg /change standby-timeout-ac 0 >$null 2>&1
powercfg /change monitor-timeout-ac 15 >$null 2>&1
powercfg /change hibernate-timeout-ac 0 >$null 2>&1
Write-Log "Power settings configured" "OK"

# --- 3i. Disable Lock Screen Ads & Tips ---
Write-Log "Disabling tips, ads, and suggestions..."
$ContentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$cdKeys = @(
    "SubscribedContent-338389Enabled",   # Windows Tips
    "SubscribedContent-310093Enabled",   # Suggested apps in Start
    "SubscribedContent-338388Enabled",   # Suggestions in timeline
    "SubscribedContent-353694Enabled",   # Suggested content in Settings
    "SubscribedContent-353696Enabled",   # Suggested content in Settings
    "SoftLandingEnabled",               # Tips about Windows
    "RotatingLockScreenOverlayEnabled", # Fun facts on lock screen
    "SystemPaneSuggestionsEnabled"      # Suggested apps in Start
)
foreach ($key in $cdKeys) {
    Set-ItemProperty -Path $ContentDelivery -Name $key -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "Tips, ads, and suggestions disabled" "OK"

# --- 3j. Disable Startup Delay ---
Write-Log "Disabling startup app delay..."
$SerializePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
if (-not (Test-Path $SerializePath)) { New-Item -Path $SerializePath -Force | Out-Null }
Set-ItemProperty -Path $SerializePath -Name "StartupDelayInMSec" -Value 0 -Type DWord
Write-Log "Startup delay disabled" "OK"

# --- 3k. Privacy - FULL Telemetry Annihilation ---
Write-Log "Nuking telemetry, diagnostics, and tracking..."

# -- Activity History --
$ActivityPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $ActivityPath)) { New-Item -Path $ActivityPath -Force | Out-Null }
Set-ItemProperty -Path $ActivityPath -Name "EnableActivityFeed"       -Value 0 -Type DWord
Set-ItemProperty -Path $ActivityPath -Name "PublishUserActivities"    -Value 0 -Type DWord
Set-ItemProperty -Path $ActivityPath -Name "UploadUserActivities"     -Value 0 -Type DWord

# -- Telemetry level to 0 (Security/Off) --
$TelemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-not (Test-Path $TelemetryPath)) { New-Item -Path $TelemetryPath -Force | Out-Null }
Set-ItemProperty -Path $TelemetryPath -Name "AllowTelemetry"                  -Value 0 -Type DWord
Set-ItemProperty -Path $TelemetryPath -Name "MaxTelemetryAllowed"             -Value 0 -Type DWord
Set-ItemProperty -Path $TelemetryPath -Name "DoNotShowFeedbackNotifications"  -Value 1 -Type DWord
Set-ItemProperty -Path $TelemetryPath -Name "DisableTelemetryOptInChangeNotification" -Value 1 -Type DWord
Set-ItemProperty -Path $TelemetryPath -Name "DisableEnterpriseAuthProxy"      -Value 1 -Type DWord

# Also set HKLM current version telemetry
$TelAlt = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
if (-not (Test-Path $TelAlt)) { New-Item -Path $TelAlt -Force | Out-Null }
Set-ItemProperty -Path $TelAlt -Name "AllowTelemetry" -Value 0 -Type DWord

# -- Disable DiagTrack + dmwappushservice (the actual telemetry daemons) --
$telemetryServices = @("DiagTrack", "dmwappushservice")
foreach ($svc in $telemetryServices) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Log "Service $svc stopped and disabled" "OK"
}

# -- Disable Connected User Experiences (telemetry pipeline) --
$CUXPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $CUXPath)) { New-Item -Path $CUXPath -Force | Out-Null }
Set-ItemProperty -Path $CUXPath -Name "DisableCloudOptimizedContent"    -Value 1 -Type DWord
Set-ItemProperty -Path $CUXPath -Name "DisableWindowsConsumerFeatures"  -Value 1 -Type DWord
Set-ItemProperty -Path $CUXPath -Name "DisableSoftLanding"              -Value 1 -Type DWord
Set-ItemProperty -Path $CUXPath -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord

# -- Disable Advertising ID --
$AdvIdPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
if (-not (Test-Path $AdvIdPath)) { New-Item -Path $AdvIdPath -Force | Out-Null }
Set-ItemProperty -Path $AdvIdPath -Name "Enabled" -Value 0 -Type DWord
$AdvPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
if (-not (Test-Path $AdvPolicyPath)) { New-Item -Path $AdvPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $AdvPolicyPath -Name "DisabledByGroupPolicy" -Value 1 -Type DWord

# -- Disable Feedback frequency --
$SiufPath = "HKCU:\Software\Microsoft\Siuf\Rules"
if (-not (Test-Path $SiufPath)) { New-Item -Path $SiufPath -Force | Out-Null }
Set-ItemProperty -Path $SiufPath -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord
Remove-ItemProperty -Path $SiufPath -Name "PeriodInNanoSeconds" -ErrorAction SilentlyContinue

# -- Disable App Launch Tracking --
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -Type DWord

# ============================================================================
# FULL INK / HANDWRITING / INPUT TELEMETRY ANNIHILATION
# ============================================================================

# -- Disable Input Personalization (typing/inking telemetry) --
$InputPath = "HKCU:\Software\Microsoft\InputPersonalization"
if (-not (Test-Path $InputPath)) { New-Item -Path $InputPath -Force | Out-Null }
Set-ItemProperty -Path $InputPath -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord
Set-ItemProperty -Path $InputPath -Name "RestrictImplicitInkCollection"  -Value 1 -Type DWord
Set-ItemProperty -Path $InputPath -Name "EnableAutoLearning"             -Value 0 -Type DWord -ErrorAction SilentlyContinue
$InputTrainPath = "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"
if (-not (Test-Path $InputTrainPath)) { New-Item -Path $InputTrainPath -Force | Out-Null }
Set-ItemProperty -Path $InputTrainPath -Name "HarvestContacts" -Value 0 -Type DWord

# -- Disable Ink Workspace entirely --
$InkWorkspace = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace"
if (-not (Test-Path $InkWorkspace)) { New-Item -Path $InkWorkspace -Force | Out-Null }
Set-ItemProperty -Path $InkWorkspace -Name "AllowWindowsInkWorkspace"          -Value 0 -Type DWord  # 0 = fully disabled
Set-ItemProperty -Path $InkWorkspace -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Value 0 -Type DWord
Write-Log "Windows Ink Workspace fully disabled" "OK"

# -- Disable handwriting data sharing --
$HandwritingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports"
if (-not (Test-Path $HandwritingPath)) { New-Item -Path $HandwritingPath -Force | Out-Null }
Set-ItemProperty -Path $HandwritingPath -Name "PreventHandwritingErrorReports" -Value 1 -Type DWord

$TabletTips = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC"
if (-not (Test-Path $TabletTips)) { New-Item -Path $TabletTips -Force | Out-Null }
Set-ItemProperty -Path $TabletTips -Name "PreventHandwritingDataSharing" -Value 1 -Type DWord
Write-Log "Handwriting error reports and data sharing disabled" "OK"

# -- Disable pen/ink telemetry and personalization --
$PenWorkspace = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"
if (-not (Test-Path $PenWorkspace)) { New-Item -Path $PenWorkspace -Force | Out-Null }
Set-ItemProperty -Path $PenWorkspace -Name "PenWorkspaceButtonDesiredVisibility" -Value 0 -Type DWord  # hide pen button

# -- Disable text input / typing telemetry --
$TextInput = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput"
if (-not (Test-Path $TextInput)) { New-Item -Path $TextInput -Force | Out-Null }
Set-ItemProperty -Path $TextInput -Name "AllowLinguisticDataCollection" -Value 0 -Type DWord
Write-Log "Linguistic data collection disabled" "OK"

# -- Disable Online Speech Recognition (voice data to Microsoft) --
$SpeechPath = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"
if (-not (Test-Path $SpeechPath)) { New-Item -Path $SpeechPath -Force | Out-Null }
Set-ItemProperty -Path $SpeechPath -Name "HasAccepted" -Value 0 -Type DWord
$SpeechPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
if (-not (Test-Path $SpeechPolicy)) { New-Item -Path $SpeechPolicy -Force | Out-Null }
Set-ItemProperty -Path $SpeechPolicy -Name "AllowInputPersonalization" -Value 0 -Type DWord
Write-Log "Online speech recognition disabled" "OK"

# -- Disable Diagnostic Data Viewer / Diagnostic Data upload --
$DiagDataPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-not (Test-Path $DiagDataPath)) { New-Item -Path $DiagDataPath -Force | Out-Null }
Set-ItemProperty -Path $DiagDataPath -Name "AllowTelemetry"                          -Value 0 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "MaxTelemetryAllowed"                     -Value 0 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "DisableDiagnosticDataViewer"             -Value 1 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "DisableOneSettingsDownloads"             -Value 1 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "DoNotShowFeedbackNotifications"          -Value 1 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "LimitDiagnosticLogCollection"            -Value 1 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "LimitDumpCollection"                     -Value 1 -Type DWord
Set-ItemProperty -Path $DiagDataPath -Name "LimitEnhancedDiagnosticDataWindowsAnalytics" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# -- Disable Tailored Experiences (data sent to MSFT for "personalized tips") --
$TailoredPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"
if (-not (Test-Path $TailoredPath)) { New-Item -Path $TailoredPath -Force | Out-Null }
Set-ItemProperty -Path $TailoredPath -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Type DWord
Write-Log "Tailored experiences disabled" "OK"

# -- Disable KMS Client Online AVS Validation (phoning home for activation) --
$KMSPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
if (-not (Test-Path $KMSPath)) { New-Item -Path $KMSPath -Force | Out-Null }
Set-ItemProperty -Path $KMSPath -Name "NoGenTicket" -Value 1 -Type DWord -ErrorAction SilentlyContinue

# -- Disable Wi-Fi HotSpot auto-reporting --
$WifiReport = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"
if (-not (Test-Path $WifiReport)) { New-Item -Path $WifiReport -Force | Out-Null }
Set-ItemProperty -Path $WifiReport -Name "Value" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# -- Disable Application Telemetry --
$AppTel = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
if (-not (Test-Path $AppTel)) { New-Item -Path $AppTel -Force | Out-Null }
Set-ItemProperty -Path $AppTel -Name "AITEnable"        -Value 0 -Type DWord
Set-ItemProperty -Path $AppTel -Name "DisableInventory"  -Value 1 -Type DWord
Set-ItemProperty -Path $AppTel -Name "DisableUAR"        -Value 1 -Type DWord  # User Activity Reporting
Set-ItemProperty -Path $AppTel -Name "DisablePCA"        -Value 1 -Type DWord  # Program Compat Assistant telemetry

# -- Disable Edge telemetry and data collection --
$EdgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $EdgePolicy)) { New-Item -Path $EdgePolicy -Force | Out-Null }
Set-ItemProperty -Path $EdgePolicy -Name "PersonalizationReportingEnabled"     -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "MetricsReportingEnabled"             -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "SendSiteInfoToImproveServices"       -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "DiagnosticData"                      -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "SpotlightExperiencesAndRecommendationsEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "ShowRecommendationsEnabled"          -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "ConfigureDoNotTrack"                 -Value 1 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "EdgeShoppingAssistantEnabled"        -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "MicrosoftEdgeInsiderPromotionEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "UserFeedbackAllowed"                 -Value 0 -Type DWord
Set-ItemProperty -Path $EdgePolicy -Name "AutoImportAtFirstRun"                -Value 4 -Type DWord  # 4 = don't import
Write-Log "Edge telemetry and data collection disabled" "OK"

# -- Disable .NET / Visual Studio telemetry --
[System.Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "Machine")
[System.Environment]::SetEnvironmentVariable("DOTNET_TELEMETRY_OPTOUT", "1", "Machine")
[System.Environment]::SetEnvironmentVariable("VSCODE_TELEMETRY_OPTOUT", "1", "Machine")
[System.Environment]::SetEnvironmentVariable("POWERSHELL_TELEMETRY_OPTOUT", "1", "Machine")
Write-Log ".NET / VS Code / PowerShell telemetry env vars set to opt-out" "OK"

# -- Disable Recall / AI features if present (Win 11 24H2+) --
$RecallPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
if (-not (Test-Path $RecallPolicy)) { New-Item -Path $RecallPolicy -Force | Out-Null }
Set-ItemProperty -Path $RecallPolicy -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
Set-ItemProperty -Path $RecallPolicy -Name "TurnOffSavingSnapshots"  -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Windows Recall / AI data analysis disabled" "OK"

# -- Additional telemetry services to kill --
$extraTelServices = @("diagnosticshub.standardcollector.service", "DcpSvc", "lfsvc")
foreach ($svc in $extraTelServices) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
}
Write-Log "Additional diagnostic services disabled" "OK"

# -- Block additional telemetry/data domains in hosts --
$hostsFile2 = "$env:WINDIR\System32\drivers\etc\hosts"
$extraTelHosts = @(
    "data.microsoft.com",
    "msedge.api.cdp.microsoft.com",
    "config.edge.skype.com",
    "browser.events.data.msn.com",
    "self.events.data.microsoft.com",
    "mobile.events.data.microsoft.com",
    "v10.events.data.microsoft.com",
    "v20.events.data.microsoft.com",
    "us.configsvc1.live.com.akadns.net",
    "kmwatsonc.events.data.microsoft.com",
    "ceuswatcab01.blob.core.windows.net",
    "ceuswatcab02.blob.core.windows.net",
    "eaus2watcab01.blob.core.windows.net",
    "eaus2watcab02.blob.core.windows.net",
    "weus2watcab01.blob.core.windows.net",
    "weus2watcab02.blob.core.windows.net",
    "umwatsonc.events.data.microsoft.com",
    "ceuswatcab01.blob.core.windows.net",
    "inference.location.live.net",
    "activity.windows.com",
    "dmd.metaservices.microsoft.com",
    "ris.api.iris.microsoft.com",
    "settings-win.data.microsoft.com",
    "vortex-win.data.microsoft.com",
    "odinvzc.azureedge.net",
    "nexus.officeapps.live.com",
    "nexusrules.officeapps.live.com",
    "officeclient.microsoft.com",
    "store-images.s-microsoft.com"
)
$hostsContent2 = Get-Content $hostsFile2 -Raw -ErrorAction SilentlyContinue
$extraMarker = "# --- WinInit Extended Telemetry Block ---"
if ($hostsContent2 -notmatch [regex]::Escape($extraMarker)) {
    $block2 = "`n$extraMarker`n"
    foreach ($h in $extraTelHosts) {
        $block2 += "0.0.0.0 $h`n"
    }
    $block2 += "# --- End WinInit Extended Telemetry Block ---"
    Add-Content -Path $hostsFile2 -Value $block2 -Encoding ASCII
    Write-Log "Extended telemetry hosts blocked ($($extraTelHosts.Count) additional entries)" "OK"
} else {
    Write-Log "Extended telemetry hosts already blocked" "OK"
}

Write-Log "Full ink/input/diverse telemetry annihilation complete" "OK"

# -- Disable Location Tracking --
$LocationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
if (-not (Test-Path $LocationPath)) { New-Item -Path $LocationPath -Force | Out-Null }
Set-ItemProperty -Path $LocationPath -Name "DisableLocation"         -Value 1 -Type DWord
Set-ItemProperty -Path $LocationPath -Name "DisableWindowsLocationProvider" -Value 1 -Type DWord
Set-ItemProperty -Path $LocationPath -Name "DisableLocationScripting" -Value 1 -Type DWord

# -- Disable Cortana --
$CortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
if (-not (Test-Path $CortanaPath)) { New-Item -Path $CortanaPath -Force | Out-Null }
Set-ItemProperty -Path $CortanaPath -Name "AllowCortana"           -Value 0 -Type DWord
Set-ItemProperty -Path $CortanaPath -Name "AllowCortanaAboveLock"  -Value 0 -Type DWord
Set-ItemProperty -Path $CortanaPath -Name "AllowCloudSearch"       -Value 0 -Type DWord

# -- Disable App Diagnostics access --
$AppDiagPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{2297E4E2-5DBE-466D-A12B-0F8286F0D9CA}"
if (-not (Test-Path $AppDiagPath)) { New-Item -Path $AppDiagPath -Force | Out-Null }
Set-ItemProperty -Path $AppDiagPath -Name "Value" -Value "Deny" -Type String

# -- Disable Camera/Microphone for apps by default --
$CamPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
if (-not (Test-Path $CamPolicyPath)) { New-Item -Path $CamPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessCamera"      -Value 2 -Type DWord   # 2 = Force Deny
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessMicrophone"  -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessLocation"    -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessCallHistory" -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessContacts"    -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessEmail"       -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessMessaging"   -Value 2 -Type DWord
Set-ItemProperty -Path $CamPolicyPath -Name "LetAppsAccessAccountInfo" -Value 2 -Type DWord

# -- Disable Windows Error Reporting --
$WERPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
if (-not (Test-Path $WERPath)) { New-Item -Path $WERPath -Force | Out-Null }
Set-ItemProperty -Path $WERPath -Name "Disabled" -Value 1 -Type DWord
Stop-Service -Name WerSvc -Force -ErrorAction SilentlyContinue
Set-Service  -Name WerSvc -StartupType Disabled -ErrorAction SilentlyContinue

# -- Disable Customer Experience Improvement Program --
$CEIPPath = "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"
if (-not (Test-Path $CEIPPath)) { New-Item -Path $CEIPPath -Force | Out-Null }
Set-ItemProperty -Path $CEIPPath -Name "CEIPEnable" -Value 0 -Type DWord

# -- Disable Inventory Collector --
$InvPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
if (-not (Test-Path $InvPath)) { New-Item -Path $InvPath -Force | Out-Null }
Set-ItemProperty -Path $InvPath -Name "DisableInventory" -Value 1 -Type DWord
Set-ItemProperty -Path $InvPath -Name "AITEnable"        -Value 0 -Type DWord

# -- Block telemetry IPs via hosts file (belt and suspenders) --
Write-Log "Blocking known telemetry hostnames via hosts file..."
$hostsFile = "$env:WINDIR\System32\drivers\etc\hosts"
$telemetryHosts = @(
    "vortex.data.microsoft.com",
    "vortex-win.data.microsoft.com",
    "telecommand.telemetry.microsoft.com",
    "telecommand.telemetry.microsoft.com.nsatc.net",
    "oca.telemetry.microsoft.com",
    "oca.telemetry.microsoft.com.nsatc.net",
    "sqm.telemetry.microsoft.com",
    "sqm.telemetry.microsoft.com.nsatc.net",
    "watson.telemetry.microsoft.com",
    "watson.telemetry.microsoft.com.nsatc.net",
    "redir.metaservices.microsoft.com",
    "choice.microsoft.com",
    "choice.microsoft.com.nsatc.net",
    "df.telemetry.microsoft.com",
    "reports.wes.df.telemetry.microsoft.com",
    "wes.df.telemetry.microsoft.com",
    "services.wes.df.telemetry.microsoft.com",
    "sqm.df.telemetry.microsoft.com",
    "telemetry.microsoft.com",
    "watson.ppe.telemetry.microsoft.com",
    "telemetry.appex.bing.net",
    "telemetry.urs.microsoft.com",
    "telemetry.appex.bing.net:443",
    "settings-sandbox.data.microsoft.com",
    "vortex-sandbox.data.microsoft.com",
    "survey.watson.microsoft.com",
    "watson.live.com",
    "statsfe2.ws.microsoft.com",
    "corpext.msitadfs.glbdns2.microsoft.com",
    "compatexchange.cloudapp.net",
    "cs1.wpc.v0cdn.net",
    "a-0001.a-msedge.net",
    "statsfe2.update.microsoft.com.akadns.net",
    "diagnostics.support.microsoft.com",
    "corp.sts.microsoft.com",
    "statsfe1.ws.microsoft.com",
    "pre.footprintpredict.com",
    "i1.services.social.microsoft.com",
    "feedback.windows.com",
    "feedback.microsoft-hohm.com",
    "feedback.search.microsoft.com"
)
$hostsContent = Get-Content $hostsFile -Raw -ErrorAction SilentlyContinue
$marker = "# --- WinInit Telemetry Block ---"
if ($hostsContent -notmatch [regex]::Escape($marker)) {
    $block = "`n$marker`n"
    foreach ($h in $telemetryHosts) {
        $block += "0.0.0.0 $h`n"
    }
    $block += "# --- End WinInit Telemetry Block ---"
    Add-Content -Path $hostsFile -Value $block -Encoding ASCII
    Write-Log "Telemetry hosts blocked in hosts file ($($telemetryHosts.Count) entries)" "OK"
} else {
    Write-Log "Telemetry hosts already blocked in hosts file" "OK"
}

# -- Scheduled tasks: disable telemetry-related ones --
Write-Log "Disabling telemetry scheduled tasks..."
$telemetryTasks = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Application Experience\AitAgent",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting",
    "\Microsoft\Windows\PI\Sqm-Tasks",
    "\Microsoft\Windows\NetTrace\GatherNetworkInfo",
    "\Microsoft\Windows\Maps\MapsUpdateTask",
    "\Microsoft\Windows\Maps\MapsToastTask",
    "\Microsoft\Windows\Maintenance\WinSAT",
    "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask",
    "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
    "\Microsoft\Windows\Shell\FamilySafetyMonitor",
    "\Microsoft\Windows\Shell\FamilySafetyRefreshTask"
)
foreach ($task in $telemetryTasks) {
    schtasks /Change /TN $task /Disable >$null 2>&1
}
Write-Log "Telemetry scheduled tasks disabled ($($telemetryTasks.Count) tasks)" "OK"

# Hard-kill CompatTelRunner - disable the executable itself so nothing can invoke it
Write-Log "Neutralizing CompatTelRunner executable..."
$compatTelPaths = @(
    "$env:WINDIR\System32\CompatTelRunner.exe",
    "$env:WINDIR\SysWOW64\CompatTelRunner.exe"
)
foreach ($exePath in $compatTelPaths) {
    if (Test-Path $exePath) {
        # Take ownership, then deny execute permissions
        takeown /f $exePath >$null 2>&1
        icacls $exePath /deny "Everyone:(X)" >$null 2>&1
        # Rename as backup so it can't run at all
        $backupPath = "$exePath.bak"
        if (-not (Test-Path $backupPath)) {
            Rename-Item $exePath $backupPath -Force -ErrorAction SilentlyContinue
            Write-Log "CompatTelRunner neutralized: $exePath" "OK"
        }
    }
}

# Also kill DeviceCensus (another telemetry collector)
$deviceCensus = "$env:WINDIR\System32\DeviceCensus.exe"
if (Test-Path $deviceCensus) {
    takeown /f $deviceCensus >$null 2>&1
    icacls $deviceCensus /deny "Everyone:(X)" >$null 2>&1
    Rename-Item $deviceCensus "$deviceCensus.bak" -Force -ErrorAction SilentlyContinue
    Write-Log "DeviceCensus.exe neutralized" "OK"
}

Write-Log "Telemetry annihilation complete" "OK"

# ============================================================================
# Microsoft Account Nag / Login Prompts - Full Removal
# ============================================================================
Write-Log "Removing Microsoft Account nags, Defender nags, and Office nags..."

# --- Disable "Finish setting up your device" / "Let's finish setting up" ---
$OOBE = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
if (-not (Test-Path $OOBE)) { New-Item -Path $OOBE -Force | Out-Null }
Set-ItemProperty -Path $OOBE -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord
Write-Log "Disabled 'Finish setting up your device' nag" "OK"

# --- Disable "Get even more out of Windows" / Microsoft Account prompts in Settings ---
$ContentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-338393Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-353694Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-353696Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-353698Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-88000326Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Disabled Settings page MS Account suggestions" "OK"

# --- Disable "Sign in with Microsoft" banner in Settings ---
$SettingsNag = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $SettingsNag -Name "Start_AccountNotifications" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Disabled Settings account notification banner" "OK"

# --- Disable Windows Security (Defender) account protection nag ---
# This removes the yellow warning "Sign in to your Microsoft account" in Windows Security
$DefenderNag = "HKCU:\Software\Microsoft\Windows Security Health\State"
if (-not (Test-Path $DefenderNag)) { New-Item -Path $DefenderNag -Force | Out-Null }
Set-ItemProperty -Path $DefenderNag -Name "AccountProtection_MicrosoftAccount_Disconnected" -Value 1 -Type DWord
Write-Log "Disabled Defender 'Account Protection' MS Account nag" "OK"

# Also dismiss the notification via the provider
$DefenderNotif = "HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Notifications"
if (-not (Test-Path $DefenderNotif)) { New-Item -Path $DefenderNotif -Force | Out-Null }
Set-ItemProperty -Path $DefenderNotif -Name "DisableEnhancedNotifications" -Value 1 -Type DWord
Set-ItemProperty -Path $DefenderNotif -Name "DisableNotifications"         -Value 1 -Type DWord
Write-Log "Disabled Defender enhanced notifications" "OK"

# --- Disable "Recommend settings" and "Benefits" in Windows Security ---
$SecurityHealth = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray"
if (-not (Test-Path $SecurityHealth)) { New-Item -Path $SecurityHealth -Force | Out-Null }
Set-ItemProperty -Path $SecurityHealth -Name "HideSystray" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# --- Disable Office / Microsoft 365 nags & "Try Office" promotions ---
$OfficeSub = "HKCU:\Software\Microsoft\Office\16.0\Common\General"
if (-not (Test-Path $OfficeSub)) { New-Item -Path $OfficeSub -Force | Out-Null }
Set-ItemProperty -Path $OfficeSub -Name "ShownFirstRunOptin" -Value 1 -Type DWord   # Skip first-run
Set-ItemProperty -Path $OfficeSub -Name "SkipOpenAndSavePlacesForNewOnboarding" -Value 1 -Type DWord -ErrorAction SilentlyContinue

# Disable Office sign-in prompt and cloud features
$OfficeIdentity = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity"
if (-not (Test-Path $OfficeIdentity)) { New-Item -Path $OfficeIdentity -Force | Out-Null }
Set-ItemProperty -Path $OfficeIdentity -Name "EnableADAL" -Value 0 -Type DWord   # Disable Azure AD auth prompt

# Disable "Get Office" / "Microsoft 365" app if still present
Get-AppxPackage -Name "Microsoft.MicrosoftOfficeHub" -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null
Get-AppxPackage -Name "Microsoft.Office.Desktop" -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null

# Policy: prevent Office from nagging about sign-in
$OfficePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\General"
if (-not (Test-Path $OfficePolicyPath)) { New-Item -Path $OfficePolicyPath -Force | Out-Null }
Set-ItemProperty -Path $OfficePolicyPath -Name "ShownFirstRunOptin" -Value 1 -Type DWord
Set-ItemProperty -Path $OfficePolicyPath -Name "DisableBackgrounds" -Value 0 -Type DWord -ErrorAction SilentlyContinue

$OfficeSignIn = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Signin"
if (-not (Test-Path $OfficeSignIn)) { New-Item -Path $OfficeSignIn -Force | Out-Null }
Set-ItemProperty -Path $OfficeSignIn -Name "SignInOptions" -Value 3 -Type DWord   # 3 = None (no sign-in)
Write-Log "Disabled Office sign-in prompt and first-run nag" "OK"

# --- Disable "Link your phone" / "Your Phone" nag ---
$PhoneNag = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Mobility"
if (-not (Test-Path $PhoneNag)) { New-Item -Path $PhoneNag -Force | Out-Null }
Set-ItemProperty -Path $PhoneNag -Name "OptedIn" -Value 0 -Type DWord
Write-Log "Disabled 'Link your phone' nag" "OK"

# --- Disable "Welcome Experience" after updates ---
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ContentDelivery -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

# --- Disable "Ways to get the most out of Windows" / Tips nag ---
$TipsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $TipsPolicy)) { New-Item -Path $TipsPolicy -Force | Out-Null }
Set-ItemProperty -Path $TipsPolicy -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path $TipsPolicy -Name "DisableSoftLanding"             -Value 1 -Type DWord
Set-ItemProperty -Path $TipsPolicy -Name "DisableCloudOptimizedContent"   -Value 1 -Type DWord
Write-Log "Disabled Windows consumer features / tips / welcome experience" "OK"

# --- Disable Microsoft Account requirement enforcement (local accounts) ---
$MSAccountPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $MSAccountPolicy)) { New-Item -Path $MSAccountPolicy -Force | Out-Null }
Set-ItemProperty -Path $MSAccountPolicy -Name "NoConnectedUser" -Value 3 -Type DWord  # 3 = block MS account sign-in completely
# Also block via Group Policy
$AccountsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
if (-not (Test-Path $AccountsPolicy)) { New-Item -Path $AccountsPolicy -Force | Out-Null }
Set-ItemProperty -Path $AccountsPolicy -Name "DisableUserAuth" -Value 1 -Type DWord
Write-Log "Microsoft Account sign-in prompts blocked system-wide" "OK"

# --- Hide "Accounts" suggestions in Settings page ---
$SettingsVis = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $SettingsVis)) { New-Item -Path $SettingsVis -Force | Out-Null }
Set-ItemProperty -Path $SettingsVis -Name "SettingsPageVisibility" -Value "hide:sync;backup;findmydevice;windowsinsider" -Type String -ErrorAction SilentlyContinue
Write-Log "Hidden sync/backup/find-my-device/insider from Settings" "OK"

Write-Log "Microsoft Account / Defender / Office nag removal complete" "OK"

# ============================================================================
# FULL DECLOUDIFICATION & DECRAPPIFICATION
# ============================================================================
Write-Log "Starting full decloudification..."

# --- Fully remove Widgets (not just hide - kill the package) ---
Write-Log "Fully removing Widgets..."
Get-AppxPackage -Name "*WebExperience*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage -Name "*MicrosoftWindows.Client.WebExperience*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.PackageName -match "WebExperience" } |
    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 3>$null | Out-Null
# Kill the widgets process
Stop-Process -Name "Widgets" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "WidgetService" -Force -ErrorAction SilentlyContinue
# Disable widgets service
Stop-Service -Name "WidgetService" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WidgetService" -StartupType Disabled -ErrorAction SilentlyContinue
# Policy: fully block widgets
$widgetPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
if (-not (Test-Path $widgetPolicy)) { New-Item -Path $widgetPolicy -Force | Out-Null }
Set-ItemProperty -Path $widgetPolicy -Name "AllowNewsAndInterests" -Value 0 -Type DWord
# Win 11 specific
$taskbarWidget = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $taskbarWidget -Name "TaskbarDa" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Widgets fully removed (package + service + policy)" "OK"

# --- Remove Pen Menu from taskbar ---
Write-Log "Removing Pen menu from taskbar..."
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace" -Name "PenWorkspaceButtonDesiredVisibility" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Also hide via taskbar settings
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarSn" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Pen menu hidden from taskbar" "OK"

# --- Remove Storage Sense / cloud offloading ---
Write-Log "Disabling Storage Sense..."
$storageSense = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"
if (-not (Test-Path $storageSense)) { New-Item -Path $storageSense -Force | Out-Null }
Set-ItemProperty -Path $storageSense -Name "01" -Value 0 -Type DWord   # Disable Storage Sense
Set-ItemProperty -Path $storageSense -Name "04" -Value 0 -Type DWord   # Don't delete temp files
Set-ItemProperty -Path $storageSense -Name "08" -Value 0 -Type DWord   # Don't cloud-offload files
Set-ItemProperty -Path $storageSense -Name "32" -Value 0 -Type DWord   # Don't clean downloads
Set-ItemProperty -Path $storageSense -Name "128" -Value 0 -Type DWord  # Don't dehydrate OneDrive files
Set-ItemProperty -Path $storageSense -Name "256" -Value 0 -Type DWord  # Don't clean recycle bin
$storageSensePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense"
if (-not (Test-Path $storageSensePolicy)) { New-Item -Path $storageSensePolicy -Force | Out-Null }
Set-ItemProperty -Path $storageSensePolicy -Name "AllowStorageSenseGlobal" -Value 0 -Type DWord
Write-Log "Storage Sense fully disabled" "OK"

# --- Disable App Install Recommendations ---
Write-Log "Disabling app install recommendations..."
$appInstall = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\SmartScreen"
if (-not (Test-Path $appInstall)) { New-Item -Path $appInstall -Force | Out-Null }
Set-ItemProperty -Path $appInstall -Name "ConfigureAppInstallControlEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable "Recommended apps" in Settings > Apps
$appRec = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $appRec -Name "Start_IrisRecommendations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable "App Install Control" nag
$appControl = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
Set-ItemProperty -Path $appControl -Name "AicEnabled" -Value "Anywhere" -Type String -ErrorAction SilentlyContinue
Write-Log "App install recommendations disabled" "OK"

# --- Disable Cloud Clipboard Sync ---
Write-Log "Disabling cloud clipboard sync..."
$clipPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $clipPolicy)) { New-Item -Path $clipPolicy -Force | Out-Null }
Set-ItemProperty -Path $clipPolicy -Name "AllowCrossDeviceClipboard" -Value 0 -Type DWord
$clipUser = "HKCU:\Software\Microsoft\Clipboard"
if (-not (Test-Path $clipUser)) { New-Item -Path $clipUser -Force | Out-Null }
Set-ItemProperty -Path $clipUser -Name "EnableClipboardHistory" -Value 0 -Type DWord
Set-ItemProperty -Path $clipUser -Name "CloudClipboardAutomaticUpload" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Cloud clipboard sync disabled" "OK"

# --- Disable Settings Sync (cloud) ---
Write-Log "Disabling settings sync..."
$syncPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync"
if (-not (Test-Path $syncPolicy)) { New-Item -Path $syncPolicy -Force | Out-Null }
Set-ItemProperty -Path $syncPolicy -Name "DisableSettingSync" -Value 2 -Type DWord
Set-ItemProperty -Path $syncPolicy -Name "DisableSettingSyncUserOverride" -Value 1 -Type DWord
# Disable all sync categories
$syncCategories = @(
    "DisableApplicationSettingSync",
    "DisableAppSyncSettingSync",
    "DisableCredentialsSettingSync",
    "DisableDesktopThemeSettingSync",
    "DisablePersonalizationSettingSync",
    "DisableStartLayoutSettingSync",
    "DisableWebBrowserSettingSync",
    "DisableWindowsSettingSync"
)
foreach ($cat in $syncCategories) {
    Set-ItemProperty -Path $syncPolicy -Name $cat -Value 2 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $syncPolicy -Name "${cat}UserOverride" -Value 1 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "All settings sync categories disabled" "OK"

# --- Disable Find My Device ---
Write-Log "Disabling Find My Device..."
$findMyDevice = "HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice"
if (-not (Test-Path $findMyDevice)) { New-Item -Path $findMyDevice -Force | Out-Null }
Set-ItemProperty -Path $findMyDevice -Name "AllowFindMyDevice" -Value 0 -Type DWord
Set-ItemProperty -Path $findMyDevice -Name "LocationSyncEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Find My Device disabled" "OK"

# --- Disable Device Activity History Upload ---
Write-Log "Disabling device activity history..."
$activityPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $activityPolicy)) { New-Item -Path $activityPolicy -Force | Out-Null }
Set-ItemProperty -Path $activityPolicy -Name "EnableActivityFeed" -Value 0 -Type DWord
Set-ItemProperty -Path $activityPolicy -Name "PublishUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path $activityPolicy -Name "UploadUserActivities" -Value 0 -Type DWord
Set-ItemProperty -Path $activityPolicy -Name "EnableCdp" -Value 0 -Type DWord  # Connected Devices Platform
Write-Log "Device activity history upload disabled" "OK"

# --- Prevent new Outlook from replacing Mail app ---
Write-Log "Preventing new Outlook from replacing Mail..."
$outlookPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Preferences"
if (-not (Test-Path $outlookPolicy)) { New-Item -Path $outlookPolicy -Force | Out-Null }
Set-ItemProperty -Path $outlookPolicy -Name "DisableNewOutlookMigration" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Block the new Outlook toggle
$outlookToggle = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General"
if (-not (Test-Path $outlookToggle)) { New-Item -Path $outlookToggle -Force | Out-Null }
Set-ItemProperty -Path $outlookToggle -Name "HideNewOutlookToggle" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Remove new Outlook if installed
Get-AppxPackage -Name "*OutlookForWindows*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.PackageName -match "OutlookForWindows" } |
    Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 3>$null | Out-Null
Write-Log "New Outlook migration blocked and removed" "OK"

# --- Remove Family Safety / Family menu ---
Write-Log "Removing Family features..."
$familyPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Set-ItemProperty -Path $familyPolicy -Name "EnableFontProviders" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable Family Safety services
Stop-Service -Name "WpcMonSvc" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WpcMonSvc" -StartupType Disabled -ErrorAction SilentlyContinue
# Disable Family Safety scheduled tasks
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match "Family" -or $_.TaskPath -match "Family"
} | ForEach-Object {
    Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue | Out-Null
}
# Hide family from Settings
$familySafety = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Set-ItemProperty -Path $familySafety -Name "EnableFamilySafety" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Remove Family Safety app
Get-AppxPackage -Name "*Family*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Write-Log "Family features removed" "OK"

# --- Disable Cloud Content Pipeline (suggested apps, pre-installed junk) ---
Write-Log "Disabling cloud content pipeline..."
$cloudContent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $cloudContent)) { New-Item -Path $cloudContent -Force | Out-Null }
Set-ItemProperty -Path $cloudContent -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableConsumerAccountStateContent" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableSoftLanding" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsSpotlightOnActionCenter" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsSpotlightWindowsWelcomeExperience" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cloudContent -Name "DisableWindowsSpotlightOnSettings" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $cloudContent -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Type DWord
Set-ItemProperty -Path $cloudContent -Name "DisableThirdPartySuggestions" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# User-level content delivery
$contentDelivery = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
$cdmKeys = @(
    "ContentDeliveryAllowed",
    "FeatureManagementEnabled",
    "OemPreInstalledAppsEnabled",
    "PreInstalledAppsEnabled",
    "PreInstalledAppsEverEnabled",
    "SilentInstalledAppsEnabled",
    "SoftLandingEnabled",
    "SubscribedContentEnabled",
    "SystemPaneSuggestionsEnabled",
    "RotatingLockScreenEnabled",
    "RotatingLockScreenOverlayEnabled"
)
foreach ($key in $cdmKeys) {
    Set-ItemProperty -Path $contentDelivery -Name $key -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "Cloud content pipeline fully disabled" "OK"

# --- Remove Microsoft Account from Settings entirely ---
Write-Log "Removing Microsoft Account integration from Settings..."
# Hide accounts-related Settings pages
$settingsExplorer = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $settingsExplorer)) { New-Item -Path $settingsExplorer -Force | Out-Null }
Set-ItemProperty -Path $settingsExplorer -Name "SettingsPageVisibility" `
    -Value "hide:sync;backup;findmydevice;windowsinsider;onedrive;yourinfo;emailandaccounts;signinoptions-launchfaceenrollment;signinoptions-launchfingerprintenrollment;signinoptions-launchsecuritykeyenrollment;recovery;otherusers" `
    -Type String -ErrorAction SilentlyContinue
# Disable Windows Backup service
Stop-Service -Name "WBackup" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WBackup" -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name "SDRSVC" -Force -ErrorAction SilentlyContinue
Set-Service -Name "SDRSVC" -StartupType Disabled -ErrorAction SilentlyContinue
# Block MS Account sign-in
$msAcct = "HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftAccount"
if (-not (Test-Path $msAcct)) { New-Item -Path $msAcct -Force | Out-Null }
Set-ItemProperty -Path $msAcct -Name "DisableUserAuth" -Value 1 -Type DWord
# Block "Accounts" suggestions in OOBE / first-run
$oobe = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
if (-not (Test-Path $oobe)) { New-Item -Path $oobe -Force | Out-Null }
Set-ItemProperty -Path $oobe -Name "DisablePrivacyExperience" -Value 1 -Type DWord
# Block sign-in suggestions
$signInSuggest = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
if (-not (Test-Path $signInSuggest)) { New-Item -Path $signInSuggest -Force | Out-Null }
Set-ItemProperty -Path $signInSuggest -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord
Write-Log "Microsoft Account integration stripped from Settings" "OK"

# --- Disable Copilot fully ---
Write-Log "Disabling Windows Copilot..."
$copilotPolicy = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $copilotPolicy)) { New-Item -Path $copilotPolicy -Force | Out-Null }
Set-ItemProperty -Path $copilotPolicy -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
$copilotPolicyLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
if (-not (Test-Path $copilotPolicyLM)) { New-Item -Path $copilotPolicyLM -Force | Out-Null }
Set-ItemProperty -Path $copilotPolicyLM -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord
# Hide Copilot button from taskbar
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Remove Copilot app
Get-AppxPackage -Name "*Copilot*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
# Disable Win+C shortcut for Copilot
$copilotHotkey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $copilotHotkey -Name "ShowCopilotButton" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Windows Copilot fully disabled" "OK"

# --- Disable Suggested Actions (clipboard AI) ---
Write-Log "Disabling Suggested Actions..."
$suggestedActions = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SmartActionPlatform\SmartClipboard"
if (-not (Test-Path $suggestedActions)) { New-Item -Path $suggestedActions -Force | Out-Null }
Set-ItemProperty -Path $suggestedActions -Name "Disabled" -Value 1 -Type DWord -ErrorAction SilentlyContinue
$saPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Set-ItemProperty -Path $saPolicy -Name "EnableSmartClipboard" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Suggested Actions disabled" "OK"

# --- Disable Phone Link / Cross-device ---
Write-Log "Disabling Phone Link and cross-device features..."
Get-AppxPackage -Name "*YourPhone*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage -Name "*PhoneLink*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
$phoneLinkPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
Set-ItemProperty -Path $phoneLinkPolicy -Name "EnableMmx" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $phoneLinkPolicy -Name "RSoPLogging" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable CDP (Connected Devices Platform)
Stop-Service -Name "CDPSvc" -Force -ErrorAction SilentlyContinue
Set-Service -Name "CDPSvc" -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name "CDPUserSvc" -Force -ErrorAction SilentlyContinue
Set-Service -Name "CDPUserSvc" -StartupType Disabled -ErrorAction SilentlyContinue
Write-Log "Phone Link and cross-device features removed" "OK"

Write-Log "Full decloudification complete" "OK"

# ============================================================================
# Tips, Suggestions, Jump Lists, First Run, Drive Labels
# ============================================================================

# --- Disable ALL tips and suggestions everywhere ---
Write-Log "Disabling all tips and suggestions..."
$advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# "Get tips, tricks, and suggestions as you use Windows"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# "Suggest ways I can finish setting up my device"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# "Show me suggested content in the Settings app"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353696Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# "Get tips and suggestions when using Windows" (notification)
$notifPolicy = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested"
if (-not (Test-Path $notifPolicy)) { New-Item -Path $notifPolicy -Force | Out-Null }
Set-ItemProperty -Path $notifPolicy -Name "Enabled" -Value 0 -Type DWord
# "Show suggestions occasionally in Start"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# "Show me the Windows welcome experience after updates"
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Notifications: disable "Suggest ways to get the most out of Windows"
$notifSuggest = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.HelloFace"
if (-not (Test-Path $notifSuggest)) { New-Item -Path $notifSuggest -Force | Out-Null }
Set-ItemProperty -Path $notifSuggest -Name "Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Policy level: disable tips
$tipsPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $tipsPolicy)) { New-Item -Path $tipsPolicy -Force | Out-Null }
Set-ItemProperty -Path $tipsPolicy -Name "DisableSoftLanding" -Value 1 -Type DWord
Write-Log "All tips and suggestions disabled everywhere" "OK"

# --- Disable Jump Lists and recently opened items in Start ---
Write-Log "Disabling Jump Lists and recent items in Start..."
$startPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
# "Show recently opened items in Start, Jump Lists, and File Explorer"
Set-ItemProperty -Path $startPath -Name "Start_TrackDocs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# "Show recently added apps"
Set-ItemProperty -Path $startPath -Name "Start_TrackProgs" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable Jump Lists
Set-ItemProperty -Path $startPath -Name "TaskbarGlomLevel" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Policy: disable recent/frequent
$startLayout = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
if (-not (Test-Path $startLayout)) { New-Item -Path $startLayout -Force | Out-Null }
Set-ItemProperty -Path $startLayout -Name "ShowRecentList" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $startLayout -Name "ShowFrequentList" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Clear all Jump List data
$jumpListPaths = @(
    "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations",
    "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations"
)
foreach ($jlp in $jumpListPaths) {
    if (Test-Path $jlp) {
        Remove-Item "$jlp\*" -Force -ErrorAction SilentlyContinue
    }
}
Write-Log "Jump Lists and recent items disabled and cleared" "OK"

# --- Bypass First Run Experience (all apps) ---
Write-Log "Bypassing first-run experiences..."
# Edge first run
$edgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $edgePolicy)) { New-Item -Path $edgePolicy -Force | Out-Null }
Set-ItemProperty -Path $edgePolicy -Name "HideFirstRunExperience" -Value 1 -Type DWord
# Windows OOBE
$oobePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"
if (-not (Test-Path $oobePolicy)) { New-Item -Path $oobePolicy -Force | Out-Null }
Set-ItemProperty -Path $oobePolicy -Name "DisablePrivacyExperience" -Value 1 -Type DWord
# Office first run
$officeGeneral = "HKCU:\Software\Microsoft\Office\16.0\Common\General"
if (-not (Test-Path $officeGeneral)) { New-Item -Path $officeGeneral -Force | Out-Null }
Set-ItemProperty -Path $officeGeneral -Name "ShownFirstRunOptin" -Value 1 -Type DWord
# IE/Legacy first run
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Chrome first run (suppress)
$chromePolicy = "HKLM:\SOFTWARE\Policies\Google\Chrome"
if (-not (Test-Path $chromePolicy)) { New-Item -Path $chromePolicy -Force | Out-Null }
Set-ItemProperty -Path $chromePolicy -Name "SuppressFirstRunBubble" -Value 1 -Type DWord -ErrorAction SilentlyContinue
# Firefox first run (already handled in policies.json but reinforce)
$ffPolicy = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
if (-not (Test-Path $ffPolicy)) { New-Item -Path $ffPolicy -Force | Out-Null }
Set-ItemProperty -Path $ffPolicy -Name "OverrideFirstRunPage" -Value "" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $ffPolicy -Name "OverridePostUpdatePage" -Value "" -Type String -ErrorAction SilentlyContinue
Write-Log "First-run experiences bypassed (Windows, Edge, Office, Chrome, Firefox)" "OK"

# --- Set Display Zoom/Scale to 100% ---
Write-Log "Setting display scale to 100%..."
# Get all active monitors and set scale to 100% (96 DPI)
$displayPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $displayPath -Name "LogPixels" -Value 96 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $displayPath -Name "Win8DpiScaling" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Per-monitor DPI: set all to 100% via the new settings path
$dpiPath = "HKCU:\Control Panel\Desktop\PerMonitorSettings"
if (Test-Path $dpiPath) {
    Get-ChildItem $dpiPath | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "DpiValue" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
}
# System-wide DPI override
$displaySettingsPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
Set-ItemProperty -Path $displaySettingsPath -Name "AppliedDPI" -Value 96 -Type DWord -ErrorAction SilentlyContinue
# Also set via the modern display config
$monitorPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors"
if (Test-Path $monitorPath) {
    Get-ChildItem $monitorPath -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "BIOSProbedScale" -Value 100 -Type DWord -ErrorAction SilentlyContinue
    }
}
$configPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration"
if (Test-Path $configPath) {
    Get-ChildItem $configPath -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $_.Property -contains "Scaling"
    } | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name "Scaling" -Value 100 -Type DWord -ErrorAction SilentlyContinue
    }
}
Write-Log "Display scale set to 100% (96 DPI)" "OK"

# --- Lock Screen: disable widgets / weather / news ---
Write-Log "Disabling lock screen widgets and weather..."
# Disable lock screen widgets (Win 11 22H2+)
$lockWidgets = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
if (-not (Test-Path $lockWidgets)) { New-Item -Path $lockWidgets -Force | Out-Null }
Set-ItemProperty -Path $lockWidgets -Name "EnableFeeds" -Value 0 -Type DWord
# Disable lock screen notifications
$lockNotif = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
if (-not (Test-Path $lockNotif)) { New-Item -Path $lockNotif -Force | Out-Null }
Set-ItemProperty -Path $lockNotif -Name "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $lockNotif -Name "NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable lock screen spotlight/tips/fun facts
$lockContent = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $lockContent -Name "RotatingLockScreenEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $lockContent -Name "RotatingLockScreenOverlayEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $lockContent -Name "SubscribedContent-338387Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Disable weather/news on lock screen (Win 11)
$lockWidgetPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $lockWidgetPath -Name "LockScreenWeather" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Policy: disable lock screen app notifications
$lockPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
if (-not (Test-Path $lockPolicy)) { New-Item -Path $lockPolicy -Force | Out-Null }
Set-ItemProperty -Path $lockPolicy -Name "DisableLockScreenAppNotifications" -Value 1 -Type DWord
# Disable lock screen camera
Set-ItemProperty -Path $lockPolicy -Name "AllowDomainPINLogon" -Value 0 -Type DWord -ErrorAction SilentlyContinue
# Set lock screen to plain (no spotlight, no windows hello prompt)
$personalization = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
if (-not (Test-Path $personalization)) { New-Item -Path $personalization -Force | Out-Null }
Set-ItemProperty -Path $personalization -Name "NoLockScreen" -Value 0 -Type DWord  # Keep lock screen but clean
Set-ItemProperty -Path $personalization -Name "LockScreenOverlaysDisabled" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Lock screen widgets, weather, notifications, spotlight all disabled" "OK"

# --- Set Drive Labels ---
Write-Log "Setting drive labels..."
# System drive (C:) = "1984"
$sysDrive = Get-WmiObject Win32_Volume -Filter "DriveLetter = 'C:'" -ErrorAction SilentlyContinue
if ($sysDrive) {
    $sysDrive.Label = "1984"
    $sysDrive.Put() | Out-Null
    Write-Log "System drive C: labeled '1984'" "OK"
} else {
    # Fallback via label command
    label C: 1984 >$null 2>&1
    Write-Log "System drive C: labeled '1984' (via label command)" "OK"
}
# Secondary drive (D:) = "2012" (if it exists)
$secDrive = Get-WmiObject Win32_Volume -Filter "DriveLetter = 'D:'" -ErrorAction SilentlyContinue
if ($secDrive) {
    $secDrive.Label = "2012"
    $secDrive.Put() | Out-Null
    Write-Log "Secondary drive D: labeled '2012'" "OK"
} else {
    Write-Log "No D: drive found - skipping label" "WARN"
}

Write-Log "Section 3: Desktop Environment completed" "OK"
