# Module: 04 - OneDrive Removal
# ============================================================================
Write-Section "Section 4: OneDrive Removal" "Completely removing OneDrive and preventing reinstallation"

# Suppress progress bars and warnings from Appx/DISM cmdlets
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# --- Preflight: check if OneDrive is already fully removed ---
$odAlreadyGone = $true
# Check if OneDrive exe exists
$odSetup64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
$odSetup32 = "$env:SystemRoot\System32\OneDriveSetup.exe"
if ((Test-Path $odSetup64) -or (Test-Path $odSetup32)) { $odAlreadyGone = $false }
# Check if OneDrive is running
if (Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue) { $odAlreadyGone = $false }
# Check if OneDrive folder still exists
if (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") { $odAlreadyGone = $false }
# Check if prevention policy is set
$odPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -ErrorAction SilentlyContinue
if (-not $odPolicy -or $odPolicy.DisableFileSyncNGSC -ne 1) { $odAlreadyGone = $false }
# Check if UWP package still exists
$odAppx = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
if ($odAppx) { $odAlreadyGone = $false }

if ($odAlreadyGone) {
    Write-Log "OneDrive already fully removed (exe gone, policy set, no UWP package)" "OK"
    Write-Log "Section 4: OneDrive Removal completed (already done)" "OK"
    return
}

# -- Kill OneDrive processes --
Write-Log "Killing OneDrive processes..."
$odProcs = Get-Process -Name "OneDrive", "OneDriveSetup", "FileCoAuth" -ErrorAction SilentlyContinue
if ($odProcs) {
    $odProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Log "OneDrive processes killed" "OK"
} else {
    Write-Log "No OneDrive processes running" "OK"
}

# -- Uninstall OneDrive (multiple methods, with timeout) --
$odSetup = if (Test-Path $odSetup64) { $odSetup64 } elseif (Test-Path $odSetup32) { $odSetup32 } else { $null }
$odNeedsUninstall = ($null -ne $odSetup) -or (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe")

if ($odNeedsUninstall) {
    Start-Spinner "Uninstalling OneDrive..."

    # Method 1: winget
    $r = Invoke-Silent "winget" "uninstall --id Microsoft.OneDrive --silent --accept-source-agreements --disable-interactivity"
    if ($r.ExitCode -eq 0) {
        Write-Log "OneDrive removed via winget" "OK"
    }

    # Method 2: OneDriveSetup.exe /uninstall
    if ($odSetup -and (Test-Path $odSetup)) {
        Update-SpinnerMessage "Uninstalling OneDrive (setup.exe)..."
        $proc = Start-Process $odSetup "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $proc | Wait-Process -Timeout 60 -ErrorAction SilentlyContinue
            if (-not $proc.HasExited) {
                $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Log "OneDrive setup.exe timed out after 60s - killed" "WARN"
            }
        }
    }
    Stop-Spinner -FinalMessage "OneDrive uninstalled" -Status "OK"
} else {
    Write-Log "OneDrive already uninstalled (no setup exe found)" "OK"
}

# -- Remove OneDrive leftover directories --
Write-Log "Removing OneDrive leftover folders..."
$odFolders = @(
    "$env:USERPROFILE\OneDrive",
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:PROGRAMDATA\Microsoft OneDrive",
    "$env:SYSTEMDRIVE\OneDriveTemp",
    "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk"
)
foreach ($folder in $odFolders) {
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed: $folder" "OK"
    }
}

# -- Remove OneDrive from Explorer sidebar --
Write-Log "Removing OneDrive from Explorer navigation pane..."
# Use reg.exe directly (HKCR via PowerShell PSDrive is extremely slow)
reg add "HKCR\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >$null 2>&1
reg add "HKCR\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >$null 2>&1

# -- Prevent OneDrive from reinstalling --
Write-Log "Preventing OneDrive reinstallation..."
$odPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
if (-not (Test-Path $odPolicyPath)) { New-Item -Path $odPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $odPolicyPath -Name "DisableFileSyncNGSC"   -Value 1 -Type DWord
Set-ItemProperty -Path $odPolicyPath -Name "DisableFileSync"       -Value 1 -Type DWord
Set-ItemProperty -Path $odPolicyPath -Name "DisableMeteredNetworkFileSync" -Value 1 -Type DWord
Set-ItemProperty -Path $odPolicyPath -Name "DisableLibrariesDefaultSaveToOneDrive" -Value 1 -Type DWord

# -- Remove OneDrive from startup --
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue

# -- Remove OneDrive scheduled tasks --
$odTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match "OneDrive" }
foreach ($t in $odTasks) {
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log "Removed scheduled task: $($t.TaskName)" "OK"
}

# -- Remove OneDrive from right-click context menu --
reg delete "HKCR\*\shellex\ContextMenuHandlers\FileSyncEx" /f >$null 2>&1
reg delete "HKCR\Directory\Background\shellex\ContextMenuHandlers\FileSyncEx" /f >$null 2>&1
reg delete "HKCR\Directory\shellex\ContextMenuHandlers\FileSyncEx" /f >$null 2>&1
Write-Log "OneDrive context menu entries removed" "OK"

# -- Reset default save locations away from OneDrive --
$UserShellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
$shellDefaults = @{
    "Personal"    = "$env:USERPROFILE\Documents"
    "My Pictures" = "$env:USERPROFILE\Pictures"
    "My Video"    = "$env:USERPROFILE\Videos"
    "My Music"    = "$env:USERPROFILE\Music"
    "{374DE290-123F-4565-9164-39C4925E467B}" = "$env:USERPROFILE\Downloads"
    "Desktop"     = "$env:USERPROFILE\Desktop"
}
foreach ($key in $shellDefaults.Keys) {
    $currentVal = (Get-ItemProperty -Path $UserShellFolders -Name $key -ErrorAction SilentlyContinue).$key
    if ($currentVal -and $currentVal -match "OneDrive") {
        Set-ItemProperty -Path $UserShellFolders -Name $key -Value $shellDefaults[$key] -Type ExpandString
        Write-Log "Redirected shell folder '$key' from OneDrive to local" "OK"
    }
}

# -- Remove OneDrive icon overlay handlers (sync status icons on files) --
Write-Log "Removing OneDrive icon overlays..."
$overlayRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers"
if (Test-Path $overlayRoot) {
    $odOverlays = Get-ChildItem $overlayRoot -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "OneDrive|SkyDrive|SharePoint"
    }
    foreach ($overlay in $odOverlays) {
        Remove-Item $overlay.PSPath -Force -ErrorAction SilentlyContinue
        Write-Log "Removed icon overlay: $($overlay.PSChildName)" "OK"
    }
}
# Also clean up spaces-prefixed overlays (OneDrive pads with spaces to sort first)
$overlayNames = Get-ChildItem $overlayRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName
foreach ($name in $overlayNames) {
    if ($name.Trim() -match "OneDrive|SkyDrive|ErrorOverlay|SharedOverlay|UpToDatePinnedOverlay|UpToDateUnpinnedOverlay|SyncingOverlay") {
        Remove-Item (Join-Path $overlayRoot $name) -Force -ErrorAction SilentlyContinue
        Write-Log "Removed padded overlay: '$name'" "OK"
    }
}
Write-Log "OneDrive icon overlays removed" "OK"

# -- Remove OneDrive UWP app if present --
$odUwp = Get-AppxPackage -Name "*OneDrive*" -AllUsers -ErrorAction SilentlyContinue
if ($odUwp) {
    Write-Log "Removing OneDrive UWP package..."
    $odUwp | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -match "OneDrive" } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 3>$null | Out-Null
    Write-Log "OneDrive UWP package removed" "OK"
} else {
    Write-Log "OneDrive UWP package already removed" "OK"
}

# -- Remove OneDrive from notification area / system tray --
Write-Log "Removing OneDrive from system tray..."
$notifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
$odNotifKeys = Get-ChildItem $notifPath -ErrorAction SilentlyContinue | Where-Object {
    $_.PSChildName -match "OneDrive|Microsoft.SkyDrive"
}
foreach ($key in $odNotifKeys) {
    Set-ItemProperty -Path $key.PSPath -Name "Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Log "OneDrive notifications disabled" "OK"

# -- Remove OneDrive file type associations --
Write-Log "Removing OneDrive file handlers..."
$odHandlerGuids = @(
    "{A78ED123-AB77-406B-9962-2A5D9D2F7F30}",   # OneDrive namespace
    "{CB3D0F55-BC2C-4C1A-85ED-23ED75B5106B}",   # OneDrive property handler
    "{71DCE5D6-4B57-496B-AC21-CD5B54EB93FD}",   # OneDrive thumbnail handler
    "{F241C880-6982-4CE5-8CF7-7085BA96DA5A}"     # OneDrive status column
)
foreach ($guid in $odHandlerGuids) {
    reg delete "HKCR\CLSID\$guid" /f >$null 2>&1
}

# -- Remove OneDrive from "Add a place" in Office --
$officePlaces = "HKCU:\Software\Microsoft\Office\16.0\Common\Internet\Server Cache"
if (Test-Path $officePlaces) {
    $odPlaces = Get-ChildItem $officePlaces -ErrorAction SilentlyContinue | Where-Object {
        (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue)."(default)" -match "onedrive|1drv"
    }
    foreach ($place in $odPlaces) {
        Remove-Item $place.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Log "OneDrive removed from Office places" "OK"

# -- Remove OneDrive environment variable if set --
$odEnvPath = [System.Environment]::GetEnvironmentVariable("OneDrive", "User")
if ($odEnvPath) {
    [System.Environment]::SetEnvironmentVariable("OneDrive", $null, "User")
    Write-Log "OneDrive environment variable removed" "OK"
}
$odEnvCommercial = [System.Environment]::GetEnvironmentVariable("OneDriveCommercial", "User")
if ($odEnvCommercial) {
    [System.Environment]::SetEnvironmentVariable("OneDriveCommercial", $null, "User")
}
$odEnvConsumer = [System.Environment]::GetEnvironmentVariable("OneDriveConsumer", "User")
if ($odEnvConsumer) {
    [System.Environment]::SetEnvironmentVariable("OneDriveConsumer", $null, "User")
}

# -- Remove OneDrive from Explorer "This PC" namespace --
$odNamespaces = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{04271989-C4D2-0190-0000-000000000000}"
)
foreach ($ns in $odNamespaces) {
    if (Test-Path $ns) {
        Remove-Item $ns -Force -ErrorAction SilentlyContinue
        Write-Log "Removed OneDrive namespace: $ns" "OK"
    }
}

# -- Clean OneDrive cache folders --
$odCachePaths = @(
    "$env:LOCALAPPDATA\OneDrive",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\setup",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\Update",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs"
)
foreach ($cp in $odCachePaths) {
    if (Test-Path $cp) {
        Remove-Item $cp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed OneDrive cache: $cp" "OK"
    }
}

# -- Remove OneDrive from Settings page --
$settingsVis = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $settingsVis)) { New-Item -Path $settingsVis -Force | Out-Null }
$currentVis = (Get-ItemProperty $settingsVis -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue).SettingsPageVisibility
if ($currentVis -and $currentVis -notmatch "onedrive") {
    Set-ItemProperty -Path $settingsVis -Name "SettingsPageVisibility" -Value "$currentVis;hide:onedrive" -Type String -ErrorAction SilentlyContinue
} elseif (-not $currentVis) {
    Set-ItemProperty -Path $settingsVis -Name "SettingsPageVisibility" -Value "hide:onedrive" -Type String -ErrorAction SilentlyContinue
}
Write-Log "OneDrive hidden from Settings" "OK"

# -- Verify OneDrive is gone --
$verifyFail = @()
if (Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue) { $verifyFail += "process still running" }
if (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") { $verifyFail += "exe still exists" }
$verifyPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -ErrorAction SilentlyContinue
if (-not $verifyPolicy -or $verifyPolicy.DisableFileSyncNGSC -ne 1) { $verifyFail += "prevention policy not set" }
if (Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue) { $verifyFail += "UWP package still present" }

if ($verifyFail.Count -eq 0) {
    Write-Log "OneDrive has been completely annihilated (verified)" "OK"
} else {
    Write-Log "OneDrive mostly removed but: $($verifyFail -join ', ')" "WARN"
}

Write-Log "Section 4: OneDrive Removal completed" "OK"
