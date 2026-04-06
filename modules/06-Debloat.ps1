# Module: 06 - Debloat
# ============================================================================
Write-Section "Section 6: UWP Bloatware Removal" "Removing pre-installed UWP bloatware and preventing reinstallation"

$bloatApps = @(
    # Games & entertainment junk
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.BingFinance",
    "Microsoft.BingSports",
    "Microsoft.GamingApp",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.Xbox.TCUI",
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    # Communication bloat
    "Microsoft.People",
    "microsoft.windowscommunicationsapps",  # Mail & Calendar
    "Microsoft.YourPhone",
    "Microsoft.WindowsMaps",
    "Microsoft.Todos",
    "Microsoft.OutlookForWindows",
    # Media junk
    "Microsoft.ZuneMusic",          # Groove Music
    "Microsoft.ZuneVideo",          # Movies & TV
    "Microsoft.WindowsSoundRecorder",
    "Microsoft.MicrosoftOfficeHub",
    # Clipchamp & creative junk
    "Clipchamp.Clipchamp",
    "Microsoft.Windows.Photos",      # legacy photos app
    "Microsoft.ScreenSketch",
    "Microsoft.WindowsNotepad",       # Windows Ink Notepad (not Notepad++)
    "Microsoft.Whiteboard",           # Microsoft Whiteboard
    "Microsoft.SketchPad",            # Sketch Pad
    "Microsoft.MicrosoftJournal",     # Microsoft Journal (ink)
    "*Ink*",                           # Any remaining ink apps
    # Third-party promoted trash
    "SpotifyAB.SpotifyMusic",
    "*CandyCrush*",
    "*BubbleWitch*",
    "*Dolby*",
    "*Disney*",
    "*TikTok*",
    "*Twitter*",
    "*Instagram*",
    "*Facebook*",
    "*Netflix*",
    "*Hulu*",
    "*Amazon*",
    "*LinkedIn*",
    "*AdobeExpress*",
    # MS junk
    "Microsoft.Getstarted",          # Tips
    "Microsoft.GetHelp",             # Get Help app
    "Microsoft.BingSearch",          # Bing Search
    "Microsoft.Office.OneNote",      # OneNote UWP
    "Microsoft.MicrosoftOffice.OneNote",  # OneNote alternative package name
    "*OneNote*",                     # Any remaining OneNote
    "Microsoft.MixedReality.Portal",
    "Microsoft.3DBuilder",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.Print3D",
    "Microsoft.OneConnect",
    "Microsoft.WindowsAlarms",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.Copilot",
    "Microsoft.549981C3F5F10",       # Cortana
    "MicrosoftCorporationII.QuickAssist",
    "MicrosoftTeams",
    "MSTeams",
    "Microsoft.MicrosoftStickyNotes"
)

# Suppress all progress bars from Appx cmdlets
$ProgressPreference = 'SilentlyContinue'

# Pre-check: get list of currently installed packages (once, fast)
$installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$installedProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageName)

# Filter to only apps that are actually still installed
$bloatPresent = @()
foreach ($app in $bloatApps) {
    $pattern = $app -replace '\*', '.*'
    $found = $installedAppx | Where-Object { $_ -match $pattern }
    $foundProv = $installedProv | Where-Object { $_ -match $pattern }
    if ($found -or $foundProv) { $bloatPresent += $app }
}

if ($bloatPresent.Count -eq 0) {
    Write-Log "UWP bloatware already removed (all $($bloatApps.Count) targets gone)" "OK"
} else {
    Write-Log "Removing $($bloatPresent.Count) UWP bloat packages (of $($bloatApps.Count) targeted)..."
    Start-Spinner "Removing $($bloatPresent.Count) UWP bloat packages..."

    $removedCount = 0
    foreach ($app in $bloatPresent) {
        try {
            Get-AppxPackage -Name $app -ErrorAction SilentlyContinue |
                Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null
        } catch {}
        try {
            Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue |
                Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue 2>$null | Out-Null
        } catch {}
        try {
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.PackageName -like "*$app*" } |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 2>$null | Out-Null
        } catch {}
        $removedCount++
        $script:SpinnerSync.Message = "UWP debloat: $removedCount/$($bloatPresent.Count)"
    }
    Stop-Spinner -FinalMessage "UWP bloatware: $removedCount packages processed" -Status "OK"

    # Post-verify: check how many are still lingering
    $remainingAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $stillPresent = 0
    foreach ($app in $bloatPresent) {
        $pattern = $app -replace '\*', '.*'
        if ($remainingAppx | Where-Object { $_ -match $pattern }) { $stillPresent++ }
    }
    if ($stillPresent -eq 0) {
        Write-Log "UWP debloat verified: all targeted packages removed" "OK"
    } else {
        Write-Log "UWP debloat: $stillPresent packages could not be fully removed (may need reboot)" "WARN"
    }
}

$ProgressPreference = 'Continue'

# --- Uninstall OneNote desktop version ---
Write-Log "Removing OneNote desktop version..."
# Use Invoke-Silent so winget doesn't leak output
Invoke-Silent "winget" "uninstall --id Microsoft.Office.OneNote --silent --accept-source-agreements --disable-interactivity" >$null 2>&1
Invoke-Silent "winget" "uninstall --id ONENOTE --silent --accept-source-agreements --disable-interactivity" >$null 2>&1
# Office Click-to-Run: use Invoke-Silent to prevent GUI popup
$officeC2R = "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeClickToRun.exe"
if (Test-Path $officeC2R) {
    Invoke-Silent $officeC2R "scenario=install scenariosubtype=ARP sourcetype=None productstoremove=OneNoteRetail.16_en-us_x-none culture=en-us version.16=16.0 DisplayLevel=False" >$null 2>&1
}
Write-Log "OneNote desktop version removed" "OK"

# Prevent Store from auto-reinstalling removed apps
$StoreContentPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
Set-ItemProperty -Path $StoreContentPath -Name "SilentInstalledAppsEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $StoreContentPath -Name "PreInstalledAppsEnabled"    -Value 0 -Type DWord
Set-ItemProperty -Path $StoreContentPath -Name "PreInstalledAppsEverEnabled" -Value 0 -Type DWord
Set-ItemProperty -Path $StoreContentPath -Name "OemPreInstalledAppsEnabled" -Value 0 -Type DWord
Write-Log "Store auto-reinstall of bloatware disabled" "OK"

# --- Full Xbox Component Annihilation ---
Write-Log "Fully uninstalling all Xbox components..."

# Remove ALL Xbox-related packages (broader wildcard sweep)
$ProgressPreference = 'SilentlyContinue'
$xboxPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "Xbox|GamingApp|GamingOverlay|GameOverlay|XblAuth|XblGame|XboxSpeech|XboxGip|Xbox\.TCUI"
}
foreach ($pkg in $xboxPackages) {
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue 2>$null | Out-Null
    } catch {}
}
Write-Log "Xbox Appx packages removed" "OK"

# Remove provisioned Xbox packages (prevents reinstall for new users)
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
    $_.PackageName -match "Xbox|GamingApp|GamingOverlay|GameOverlay|XblAuth|XblGame"
} | ForEach-Object {
    try {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue 2>$null | Out-Null
    } catch {}
}
$ProgressPreference = 'Continue'
Write-Log "Xbox provisioned packages removed" "OK"

# Disable ALL Xbox services
$xboxServices = @(
    "XblAuthManager",      # Xbox Live Auth Manager
    "XblGameSave",         # Xbox Live Game Save
    "XboxNetApiSvc",       # Xbox Live Networking Service
    "XboxGipSvc",          # Xbox Accessory Management Service
    "GamingServices",      # Gaming Services
    "GamingServicesNet"    # Gaming Services Network
)
foreach ($svc in $xboxServices) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path $svcRegPath) {
        Set-ItemProperty -Path $svcRegPath -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Log "Xbox service disabled: $svc" "OK"
}

# Disable Xbox scheduled tasks
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match "Xbox" -or $_.TaskPath -match "Xbox"
} | ForEach-Object {
    Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue 3>$null | Out-Null
}

# Block Xbox via Group Policy
$XboxPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
if (-not (Test-Path $XboxPolicy)) { New-Item -Path $XboxPolicy -Force | Out-Null }
Set-ItemProperty -Path $XboxPolicy -Name "AllowGameDVR" -Value 0 -Type DWord

# Append gaming/debloat pages to existing SettingsPageVisibility (don't overwrite modules 03/04)
$debloatPages = "gaming-gamebar;gaming-gamedvr;gaming-gamemode;gaming-trueplay;gaming-xboxnetworking"
$svPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $svPath)) { New-Item -Path $svPath -Force | Out-Null }
$currentSV = (Get-ItemProperty -Path $svPath -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue).SettingsPageVisibility
if ($currentSV) {
    # Append only pages not already present
    $existing = $currentSV -replace "^hide:", ""
    $new = ($debloatPages -split ";") | Where-Object { $existing -notmatch [regex]::Escape($_) }
    if ($new) { $currentSV = "$currentSV;$($new -join ';')" }
    Set-ItemProperty -Path $svPath -Name "SettingsPageVisibility" -Value $currentSV -Type String
} else {
    Set-ItemProperty -Path $svPath -Name "SettingsPageVisibility" -Value "hide:$debloatPages" -Type String
}

Write-Log "Xbox components fully uninstalled and blocked" "OK"

Write-Log "Section 6: UWP Bloatware Removal completed" "OK"
