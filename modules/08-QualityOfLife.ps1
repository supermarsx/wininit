# Module: 08 - Quality of Life
# NumLock, sticky keys, default terminal, locale, long paths, PowerShell execution policy

Write-Section "Quality of Life"

# --- 8a. NumLock ON at Boot ---
Write-Log "Enabling NumLock at boot..."
$NumLockPath = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"
Set-ItemProperty -Path $NumLockPath -Name "InitialKeyboardIndicators" -Value "2147483650" -Type String
# Also for current user
Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name "InitialKeyboardIndicators" -Value "2147483650" -Type String
Write-Log "NumLock enabled at boot" "OK"

# --- 8b. Disable Sticky Keys & Filter Keys Completely ---
Write-Log "Disabling Sticky Keys, Filter Keys, and Toggle Keys..."
# Sticky Keys - disable the shortcut and the feature
$StickyPath = "HKCU:\Control Panel\Accessibility\StickyKeys"
Set-ItemProperty -Path $StickyPath -Name "Flags" -Value "506" -Type String   # 506 = all off
# Filter Keys
$FilterPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"
Set-ItemProperty -Path $FilterPath -Name "Flags" -Value "122" -Type String   # 122 = all off
# Toggle Keys
$TogglePath = "HKCU:\Control Panel\Accessibility\ToggleKeys"
Set-ItemProperty -Path $TogglePath -Name "Flags" -Value "58" -Type String    # 58 = all off
# Prevent the "Do you want to turn on Sticky Keys?" prompt entirely
Set-ItemProperty -Path $StickyPath -Name "HotkeyFlags" -Value "0" -Type String -ErrorAction SilentlyContinue
Write-Log "Sticky Keys, Filter Keys, and Toggle Keys fully disabled" "OK"

# --- 8c. Set Default Terminal to Windows Terminal (PowerShell 7) ---
Write-Log "Setting default terminal to Windows Terminal..."
# Win 11 default terminal setting
$ConsolePath = "HKCU:\Console\%%Startup"
if (-not (Test-Path $ConsolePath)) { New-Item -Path $ConsolePath -Force | Out-Null }
# {2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69} = Windows Terminal
Set-ItemProperty -Path $ConsolePath -Name "DelegationConsole"  -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" -Type String
Set-ItemProperty -Path $ConsolePath -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" -Type String

# Set default console font to 9pt for cmd/PowerShell/batch windows
$defaultConsole = "HKCU:\Console"
# FontSize is stored as DWORD: high word = height in pixels, 9pt ~ 0x000F0000 (15px at 96dpi)
Set-ItemProperty -Path $defaultConsole -Name "FontSize"   -Value 0x000F0000 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $defaultConsole -Name "FaceName"   -Value "FiraCode Nerd Font" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $defaultConsole -Name "FontFamily"  -Value 0x36 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $defaultConsole -Name "FontWeight"  -Value 400 -Type DWord -ErrorAction SilentlyContinue
Write-Log "Console default font set to FiraCode NF 9pt" "OK"

# Configure Windows Terminal to use PowerShell 7 as default profile
# Uses safe helpers from common.ps1; falls back to direct JSON if unavailable
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
try {
    if (Get-Command Read-WTSettings -ErrorAction SilentlyContinue) {
        $wtConfig = Read-WTSettings
        if ($wtConfig) {
            $wtConfig | Add-Member -NotePropertyName "defaultProfile" -NotePropertyValue "{574e775e-4f2a-5b96-ac1e-a2962a402336}" -Force
            Write-WTSettings -Config $wtConfig | Out-Null
        } else {
            $wtConfig = Repair-WTSettings
        }
    } else {
        # Fallback: direct file manipulation if helpers not loaded
        $wtSettingsDir = Split-Path $wtSettingsPath
        if (-not (Test-Path $wtSettingsDir)) { New-Item -ItemType Directory -Path $wtSettingsDir -Force | Out-Null }
        if (Test-Path $wtSettingsPath) {
            $raw = Get-Content $wtSettingsPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $raw = $raw -replace '(?m)^\s*//.*$', '' -replace ',\s*([}\]])', '$1'
            $wtObj = $raw | ConvertFrom-Json -ErrorAction Stop
            $wtObj | Add-Member -NotePropertyName "defaultProfile" -NotePropertyValue "{574e775e-4f2a-5b96-ac1e-a2962a402336}" -Force
            $wtObj | ConvertTo-Json -Depth 20 | Set-Content $wtSettingsPath -Encoding UTF8
        } else {
            $wtDefault = @{
                defaultProfile = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"
                profiles = @{
                    defaults = @{}
                    list = @(
                        @{ guid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"; name = "PowerShell"; commandline = "powershell.exe -NoLogo"; hidden = $false }
                        @{ guid = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"; name = "PowerShell 7"; commandline = "pwsh.exe -NoLogo"; source = "Windows.Terminal.PowershellCore"; hidden = $false }
                        @{ guid = "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}"; name = "Command Prompt"; commandline = "cmd.exe"; hidden = $false }
                    )
                }
            }
            $wtDefault | ConvertTo-Json -Depth 20 | Set-Content $wtSettingsPath -Encoding UTF8
        }
    }
    Write-Log "Windows Terminal default profile set to PowerShell 7" "OK"
} catch {
    Write-Log "Windows Terminal settings config failed: $_ (will be fixed in module 17)" "WARN"
}
Write-Log "Default terminal set to Windows Terminal" "OK"

# --- Make "Open in Terminal" always visible (no Shift needed) ---
Write-Log "Making 'Open in Terminal' always available without Shift..."
# Directory background context menu
$openTermBg = "HKLM:\SOFTWARE\Classes\Directory\Background\shell\OpenInTerminal"
if (Test-Path $openTermBg) {
    Remove-ItemProperty -Path $openTermBg -Name "Extended" -ErrorAction SilentlyContinue
}
# Directory context menu
$openTermDir = "HKLM:\SOFTWARE\Classes\Directory\shell\OpenInTerminal"
if (Test-Path $openTermDir) {
    Remove-ItemProperty -Path $openTermDir -Name "Extended" -ErrorAction SilentlyContinue
}
# Also handle the LibraryFolder variant
$openTermLib = "HKLM:\SOFTWARE\Classes\LibraryFolder\Background\shell\OpenInTerminal"
if (Test-Path $openTermLib) {
    Remove-ItemProperty -Path $openTermLib -Name "Extended" -ErrorAction SilentlyContinue
}
# Remove HideBasedOnVelocityId which can also hide the entry
foreach ($termKey in @($openTermBg, $openTermDir, $openTermLib)) {
    if (Test-Path $termKey) {
        Remove-ItemProperty -Path $termKey -Name "HideBasedOnVelocityId" -ErrorAction SilentlyContinue
    }
}
Write-Log "'Open in Terminal' always visible in context menu (no Shift required)" "OK"

# --- 8d. Set EVERYTHING to en-US ---
Write-Log "Setting all locales globally to en-US..."

# --- Language Pack ---
$installedLangs = Get-WinUserLanguageList
$hasEnUS = $installedLangs | Where-Object { $_.LanguageTag -eq "en-US" }
if (-not $hasEnUS) {
    Write-Log "Installing en-US language pack..."

    # Try Install-Language with a 3 minute timeout (it can hang forever)
    $langJob = Start-Job -ScriptBlock {
        try { Install-Language -Language "en-US" -ErrorAction SilentlyContinue } catch {}
    }

    $completed = $langJob | Wait-Job -Timeout 180
    if ($completed) {
        Receive-Job $langJob -ErrorAction SilentlyContinue | Out-Null
        Write-Log "en-US language pack installed" "OK"
    } else {
        Stop-Job $langJob -ErrorAction SilentlyContinue
        Write-Log "en-US language pack timed out (180s) - will apply after reboot" "WARN"
    }
    Remove-Job $langJob -Force -ErrorAction SilentlyContinue
} else {
    Write-Log "en-US language pack already installed" "OK"
}

# --- User Language List (en-US only, US keyboard) ---
$langList = New-WinUserLanguageList "en-US"
$langList[0].InputMethodTips.Clear()
$langList[0].InputMethodTips.Add("0409:00000409")  # en-US QWERTY keyboard
Set-WinUserLanguageList $langList -Force
Write-Log "User language list set to en-US" "OK"

# --- System Locale (non-Unicode programs) ---
Set-WinSystemLocale -SystemLocale "en-US" -ErrorAction SilentlyContinue

# --- UI Language Override ---
Set-WinUILanguageOverride -Language "en-US" -ErrorAction SilentlyContinue

# --- Culture (date/time/number formatting) ---
Set-Culture -CultureInfo "en-US" -ErrorAction SilentlyContinue

# --- Home Location (region for content) ---
Set-WinHomeLocation -GeoId 244 -ErrorAction SilentlyContinue   # 244 = United States

# --- Current User Regional Settings (full) ---
$IntlPath = "HKCU:\Control Panel\International"
$intlSettings = @{
    "LocaleName"       = "en-US"
    "sLanguage"        = "ENU"
    "sCountry"         = "United States"
    "sCurrency"        = "$"
    "sShortDate"       = "M/d/yyyy"
    "sLongDate"        = "dddd, MMMM d, yyyy"
    "sShortTime"       = "h:mm tt"
    "sTimeFormat"      = "h:mm:ss tt"
    "iFirstDayOfWeek"  = "6"        # 6 = Sunday
    "iMeasure"         = "1"        # 1 = US (imperial)
    "sDecimal"         = "."
    "sThousand"        = ","
    "sGrouping"        = "3;0"
    "sNativeDigits"    = "0123456789"
    "iNegNumber"       = "1"        # -1.1
    "iCurrDigits"      = "2"
    "iDigits"          = "2"
    "NumShape"         = "1"        # Western digits
    "sMonDecimalSep"   = "."
    "sMonThousandSep"  = ","
    "sMonGrouping"     = "3;0"
    "iCurrency"        = "0"        # $1.1
    "iNegCurr"         = "0"        # ($1.1)
    "s1159"            = "AM"
    "s2359"            = "PM"
}
foreach ($key in $intlSettings.Keys) {
    Set-ItemProperty -Path $IntlPath -Name $key -Value $intlSettings[$key] -Type String -ErrorAction SilentlyContinue
}
Write-Log "User regional settings set to en-US (date/time/number/currency)" "OK"

# --- System Default Language ---
$CopyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language"
Set-ItemProperty -Path $CopyPath -Name "Default"        -Value "0409" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $CopyPath -Name "InstallLanguage" -Value "0409" -Type String -ErrorAction SilentlyContinue

# --- System Locale (NLS) ---
$NlsLocale = "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Locale"
if (Test-Path $NlsLocale) {
    Set-ItemProperty -Path $NlsLocale -Name "(default)" -Value "00000409" -Type String -ErrorAction SilentlyContinue
}

# --- Default User Profile (new user accounts get en-US) ---
$defaultUserIntl = "Registry::HKU\.DEFAULT\Control Panel\International"
if (Test-Path $defaultUserIntl) {
    foreach ($key in $intlSettings.Keys) {
        Set-ItemProperty -Path $defaultUserIntl -Name $key -Value $intlSettings[$key] -Type String -ErrorAction SilentlyContinue
    }
    Write-Log "Default user profile set to en-US" "OK"
}

# --- Welcome Screen / Login Screen ---
# Copy current user settings to welcome screen
$welcomeReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $welcomeReg)) { New-Item -Path $welcomeReg -Force | Out-Null }
# Copy settings to welcome screen via registry (no UI)
$welcomeIntl = "Registry::HKU\S-1-5-18\Control Panel\International"
if (Test-Path $welcomeIntl) {
    foreach ($key in $intlSettings.Keys) {
        Set-ItemProperty -Path $welcomeIntl -Name $key -Value $intlSettings[$key] -Type String -ErrorAction SilentlyContinue
    }
}
Write-Log "Welcome/login screen set to en-US" "OK"

# --- Keyboard Layout (remove all except US) ---
$kbdPath = "HKCU:\Keyboard Layout\Preload"
if (Test-Path $kbdPath) {
    # Clear all existing layouts
    Get-ItemProperty -Path $kbdPath -ErrorAction SilentlyContinue | ForEach-Object {
        $_.PSObject.Properties | Where-Object {
            $_.Name -match "^\d+$"
        } | ForEach-Object {
            Remove-ItemProperty -Path $kbdPath -Name $_.Name -ErrorAction SilentlyContinue
        }
    }
    # Set only US keyboard
    Set-ItemProperty -Path $kbdPath -Name "1" -Value "00000409" -Type String
}
Write-Log "Keyboard layout set to US English only" "OK"

# --- System Geo (location for apps) ---
$geoPath = "HKCU:\Control Panel\International\Geo"
if (-not (Test-Path $geoPath)) { New-Item -Path $geoPath -Force | Out-Null }
Set-ItemProperty -Path $geoPath -Name "Nation" -Value "244" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $geoPath -Name "Name"   -Value "US"  -Type String -ErrorAction SilentlyContinue

# --- PowerShell / Console encoding ---
[System.Environment]::SetEnvironmentVariable("LANG", "en_US.UTF-8", "User")
[System.Environment]::SetEnvironmentVariable("LC_ALL", "en_US.UTF-8", "User")

# --- Git locale ---
git config --global core.quotepath false >$null 2>&1
git config --global i18n.logoutputencoding utf-8 >$null 2>&1
git config --global i18n.commitencoding utf-8 >$null 2>&1

Write-Log "All locales globally set to en-US" "OK"

# --- 8e. Enable Long Path Support (remove 260 char limit) ---
Write-Log "Enabling long path support..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord
# Also enable via group policy path
$LongPathPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\FileSystem"
if (-not (Test-Path $LongPathPolicy)) { New-Item -Path $LongPathPolicy -Force | Out-Null }
Set-ItemProperty -Path $LongPathPolicy -Name "LongPathsEnabled" -Value 1 -Type DWord
# Enable for Git as well
git config --global core.longpaths true >$null 2>&1
Write-Log "Long path support enabled (260 char limit removed)" "OK"

# --- 8f. Set PowerShell Execution Policy to Unrestricted ---
Write-Log "Setting PowerShell execution policy..."
try { Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Stop } catch { Write-Log "ExecutionPolicy LocalMachine: $_" "WARN" }
try { Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope CurrentUser  -Force -ErrorAction Stop } catch { Write-Log "ExecutionPolicy CurrentUser: $_" "WARN" }
# Also set for PowerShell 7 specifically via registry
$PS7PolicyPath = "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions"
$PSPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\PowerShellCore"
if (-not (Test-Path $PSPolicyPath)) { New-Item -Path $PSPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $PSPolicyPath -Name "EnableScripts" -Value 1 -Type DWord
Set-ItemProperty -Path $PSPolicyPath -Name "ExecutionPolicy" -Value "Unrestricted" -Type String
Write-Log "PowerShell execution policy set to Unrestricted (all scopes)" "OK"

Write-Log "Module 08-QualityOfLife completed" "OK"
