# Module: 09 - Services
# Fax, Insider, Phone, Retail Demo, Biometrics, bulk services disable

Write-Section "Disable Junk Services"

# Suppress progress bars and warnings from Appx/DISM cmdlets
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'

# --- 9a. Disable Fax Service ---
Write-Log "Disabling Fax service..."
Stop-Service -Name "Fax" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "Fax" -StartupType Disabled -ErrorAction SilentlyContinue
$FaxPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Fax"
if (Test-Path $FaxPath) {
    Set-ItemProperty -Path $FaxPath -Name "Start" -Value 4 -Type DWord
}
Write-Log "Fax service disabled" "OK"

# --- 9b. Disable Windows Insider Service ---
Write-Log "Disabling Windows Insider service..."
Stop-Service -Name "wisvc" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "wisvc" -StartupType Disabled -ErrorAction SilentlyContinue
$InsiderPath = "HKLM:\SYSTEM\CurrentControlSet\Services\wisvc"
if (Test-Path $InsiderPath) {
    Set-ItemProperty -Path $InsiderPath -Name "Start" -Value 4 -Type DWord
}
# Also block via policy
$FlightingPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (-not (Test-Path $FlightingPath)) { New-Item -Path $FlightingPath -Force | Out-Null }
Set-ItemProperty -Path $FlightingPath -Name "ManagePreviewBuildsPolicyValue" -Value 0 -Type DWord
Write-Log "Windows Insider service disabled" "OK"

# --- 9c. Disable Phone Service ---
Write-Log "Disabling Phone Service..."
Stop-Service -Name "PhoneSvc" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "PhoneSvc" -StartupType Disabled -ErrorAction SilentlyContinue
$PhoneSvcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PhoneSvc"
if (Test-Path $PhoneSvcPath) {
    Set-ItemProperty -Path $PhoneSvcPath -Name "Start" -Value 4 -Type DWord
}
Write-Log "Phone Service disabled" "OK"

# --- 9d. Disable Retail Demo Service ---
Write-Log "Disabling Retail Demo Service..."
Stop-Service -Name "RetailDemo" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "RetailDemo" -StartupType Disabled -ErrorAction SilentlyContinue
$RetailPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RetailDemo"
if (Test-Path $RetailPath) {
    Set-ItemProperty -Path $RetailPath -Name "Start" -Value 4 -Type DWord
}
# Also via policy
$RetailPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RetailDemo"
if (-not (Test-Path $RetailPolicy)) { New-Item -Path $RetailPolicy -Force | Out-Null }
Set-ItemProperty -Path $RetailPolicy -Name "Enabled" -Value 0 -Type DWord
Write-Log "Retail Demo Service disabled" "OK"

# --- 9e. Disable Windows Biometric Service ---
Write-Log "Disabling Windows Biometric Service..."
Stop-Service -Name "WbioSrvc" -Force -ErrorAction SilentlyContinue
Set-Service  -Name "WbioSrvc" -StartupType Disabled -ErrorAction SilentlyContinue
$BioPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WbioSrvc"
if (Test-Path $BioPath) {
    Set-ItemProperty -Path $BioPath -Name "Start" -Value 4 -Type DWord
}
# Also disable via policy
$BioPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Biometrics"
if (-not (Test-Path $BioPolicyPath)) { New-Item -Path $BioPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $BioPolicyPath -Name "Enabled" -Value 0 -Type DWord
Write-Log "Windows Biometric Service disabled" "OK"

# --- 9f. Disable Bulk Services (performance) ---
Write-Log "Disabling unnecessary services in bulk..."

$junkServices = @(
    @{ name = "lfsvc";          desc = "Geolocation Service" },
    @{ name = "MapsBroker";     desc = "Downloaded Maps Manager" },
    @{ name = "PcaSvc";         desc = "Program Compatibility Assistant" },
    @{ name = "CDPSvc";         desc = "Connected Devices Platform" },
    @{ name = "CDPUserSvc";     desc = "Connected Devices Platform User" },
    @{ name = "TrkWks";         desc = "Distributed Link Tracking Client" },
    @{ name = "WpcMonSvc";      desc = "Parental Controls" },
    @{ name = "TabletInputService"; desc = "Touch Keyboard and Handwriting" },
    @{ name = "XboxGipSvc";     desc = "Xbox Accessory Management" },
    @{ name = "XblAuthManager"; desc = "Xbox Live Auth Manager" },
    @{ name = "XblGameSave";    desc = "Xbox Live Game Save" },
    @{ name = "XboxNetApiSvc";  desc = "Xbox Live Networking" }
)

foreach ($svc in $junkServices) {
    Stop-Service -Name $svc.name -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $svc.name -StartupType Disabled -ErrorAction SilentlyContinue
    $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.name)"
    if (Test-Path $svcRegPath) {
        Set-ItemProperty -Path $svcRegPath -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Log "$($svc.desc) ($($svc.name)) disabled" "OK"
}

# CDPUserSvc is a per-user service template - also disable the template
$CDPTemplate = "HKLM:\SYSTEM\CurrentControlSet\Services\CDPUserSvc"
if (Test-Path $CDPTemplate) {
    Set-ItemProperty -Path $CDPTemplate -Name "Start" -Value 4 -Type DWord
}

Write-Log "Bulk services disabled ($($junkServices.Count) services)" "OK"

# --- Full Windows Ink / Handwriting / Pen Removal ---
Write-Log "Fully removing Windows Ink components..."

# Disable Ink Workspace via registry
$InkWS = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace"
if (-not (Test-Path $InkWS)) { New-Item -Path $InkWS -Force | Out-Null }
Set-ItemProperty -Path $InkWS -Name "AllowWindowsInkWorkspace" -Value 0 -Type DWord
Set-ItemProperty -Path $InkWS -Name "AllowSuggestedAppsInWindowsInkWorkspace" -Value 0 -Type DWord

# Hide Pen/Ink from taskbar
$PenWS = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace"
if (-not (Test-Path $PenWS)) { New-Item -Path $PenWS -Force | Out-Null }
Set-ItemProperty -Path $PenWS -Name "PenWorkspaceButtonDesiredVisibility" -Value 0 -Type DWord
Set-ItemProperty -Path $PenWS -Name "PenWorkspaceAppSuggestionsEnabled"   -Value 0 -Type DWord -ErrorAction SilentlyContinue

# Remove Windows Ink optional feature
try { Disable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-TabletPC-Optional-Package" -NoRestart -ErrorAction Stop 3>$null | Out-Null } catch {}
Write-Log "Windows Ink optional feature disabled" "OK"

# Remove ink-related apps
$inkApps = @(
    "Microsoft.ScreenSketch",
    "Microsoft.Whiteboard",
    "Microsoft.SketchPad",
    "Microsoft.MicrosoftJournal"
)
foreach ($app in $inkApps) {
    Get-AppxPackage -Name $app -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue 2>$null | Out-Null
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$app*" } |
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue 3>$null | Out-Null
}
Write-Log "Ink-related UWP apps removed" "OK"

# Kill handwriting recognition services
$inkServices = @("TabletInputService", "TouchInputService", "PenService")
foreach ($svc in $inkServices) {
    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    $svcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
    if (Test-Path $svcPath) {
        Set-ItemProperty -Path $svcPath -Name "Start" -Value 4 -Type DWord -ErrorAction SilentlyContinue
    }
}
Write-Log "Ink/touch/pen services disabled" "OK"

# Disable handwriting panel scheduled tasks
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -match "InputPersonalization|Handwriting|Pen|Ink|Tablet"
} | ForEach-Object {
    Disable-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue 3>$null | Out-Null
}

# Disable handwriting data sharing and error reports
$HWPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports"
if (-not (Test-Path $HWPath)) { New-Item -Path $HWPath -Force | Out-Null }
Set-ItemProperty -Path $HWPath -Name "PreventHandwritingErrorReports" -Value 1 -Type DWord

$TabletPC = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC"
if (-not (Test-Path $TabletPC)) { New-Item -Path $TabletPC -Force | Out-Null }
Set-ItemProperty -Path $TabletPC -Name "PreventHandwritingDataSharing" -Value 1 -Type DWord

# Disable touch keyboard auto-invoke
$TouchKB = "HKCU:\Software\Microsoft\TabletTip\1.7"
if (-not (Test-Path $TouchKB)) { New-Item -Path $TouchKB -Force | Out-Null }
Set-ItemProperty -Path $TouchKB -Name "TipbandDesiredVisibility" -Value 0 -Type DWord
Set-ItemProperty -Path $TouchKB -Name "EnableAutoCorrection"      -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TouchKB -Name "EnableSpellchecking"       -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TouchKB -Name "EnableTextPrediction"      -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TouchKB -Name "EnablePredictionSpaceInsertion" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $TouchKB -Name "EnableDoubleTapSpace"      -Value 0 -Type DWord -ErrorAction SilentlyContinue

Write-Log "Windows Ink fully removed and disabled" "OK"

Write-Log "Module 09-Services completed" "OK"
