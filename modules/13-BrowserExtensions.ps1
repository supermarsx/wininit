# Module: 13 - Browser Extensions
# Firefox policies.json with all extensions + Chrome/Edge/Chromium registry force-install

Write-Section "Browser Extensions" "Firefox policies + Chromium force-install"

# ============================================================================
# Firefox Extensions (via policies.json)
# ============================================================================
Write-Log "Configuring Firefox extension auto-install via policies..."

# Find Firefox installation directory
$ffPaths = @(
    "$env:ProgramFiles\Mozilla Firefox",
    "${env:ProgramFiles(x86)}\Mozilla Firefox"
)
$ffDir = $null
foreach ($p in $ffPaths) {
    if (Test-Path "$p\firefox.exe") { $ffDir = $p; break }
}

if (-not $ffDir) {
    Write-Log "Firefox not found - extensions will be configured but require Firefox install first" "WARN"
    $ffDir = "$env:ProgramFiles\Mozilla Firefox"
}

$ffDistDir = Join-Path $ffDir "distribution"
if (-not (Test-Path $ffDistDir)) { New-Item -ItemType Directory -Path $ffDistDir -Force | Out-Null }

# Extension list: slug on addons.mozilla.org
# policies.json uses the full AMO URL for install
$firefoxExtensions = @(
    @{ name = "Multi-Account Containers";     slug = "multi-account-containers" },
    @{ name = "FoxyProxy Standard";           slug = "foxyproxy-standard" },
    @{ name = "GHunt Companion";              slug = "ghunt-companion" },
    @{ name = "FireShot (Capture Page)";      slug = "fireshot" },
    @{ name = "Clear Cache";                  slug = "clearcache" },
    @{ name = "ColorZilla";                   slug = "colorzilla" },
    @{ name = "Dark Reader";                  slug = "darkreader" },
    @{ name = "Always Active Window";         slug = "always-active-window" },
    @{ name = "CORS Unblock";                 slug = "cors-unblock" },
    @{ name = "Download All Images";          slug = "download-all-images" },
    @{ name = "Lighthouse";                   slug = "google-lighthouse" },
    @{ name = "LiveReload";                   slug = "livereload-web-extension" },
    @{ name = "Live Editor for CSS/Less/Sass"; slug = "live-editor-for-css-less-sass" },
    @{ name = "Return YouTube Dislike";       slug = "return-youtube-dislikes" },
    @{ name = "uBlock Origin";                slug = "ublock-origin" },
    @{ name = "Violentmonkey";                slug = "violentmonkey" },
    @{ name = "Wappalyzer";                   slug = "wappalyzer" },
    @{ name = "YouTube NonStop";              slug = "youtube-nonstop" },
    @{ name = "Stylus";                       slug = "styl-us" },
    @{ name = "NoClickjack";                  slug = "noclickjack" },
    @{ name = "MetaMask";                     slug = "ether-metamask" },
    @{ name = "Bitwarden";                    slug = "bitwarden-password-manager" }
)

# Build the extensions install list for policies.json
$extensionInstallUrls = @()
foreach ($ext in $firefoxExtensions) {
    $extensionInstallUrls += "https://addons.mozilla.org/firefox/downloads/latest/$($ext.slug)/latest.xpi"
    Write-Log "Queued Firefox extension: $($ext.name)" "INFO"
}

# Build policies.json
$policies = @{
    policies = @{
        ExtensionSettings = @{
            "*" = @{
                blocked_install_message = "Managed by WinInit"
            }
        }
        Extensions = @{
            Install = $extensionInstallUrls
        }
        # While we're here, set some sane Firefox defaults
        DisableTelemetry     = $true
        DisableFirefoxStudies = $true
        DisablePocket         = $true
        DisableSetDesktopBackground = $true
        OverrideFirstRunPage  = ""
        OverridePostUpdatePage = ""
        DontCheckDefaultBrowser = $true
        NoDefaultBookmarks    = $true
        # Disable Firefox data collection
        DisableDefaultBrowserAgent = $true
        Preferences = @{
            "datareporting.healthreport.uploadEnabled"         = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.reportingpolicy.firstRun"       = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.enabled"                        = @{ Value = $false; Status = "locked" }
            "app.shield.optoutstudies.enabled"                 = @{ Value = $false; Status = "locked" }
            "browser.newtabpage.activity-stream.feeds.telemetry" = @{ Value = $false; Status = "locked" }
            "browser.newtabpage.activity-stream.telemetry"     = @{ Value = $false; Status = "locked" }
            "browser.ping-centre.telemetry"                    = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.archive.enabled"                = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.bhrPing.enabled"                = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.firstShutdownPing.enabled"      = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.newProfilePing.enabled"         = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.shutdownPingSender.enabled"     = @{ Value = $false; Status = "locked" }
            "toolkit.telemetry.updatePing.enabled"             = @{ Value = $false; Status = "locked" }
            # Dark theme by default
            "extensions.activeThemeID"                         = @{ Value = "firefox-compact-dark@mozilla.org"; Status = "default" }
            # Smooth scrolling
            "general.smoothScroll"                             = @{ Value = $true; Status = "default" }
        }
    }
}

$policiesJson = $policies | ConvertTo-Json -Depth 10
Set-Content -Path (Join-Path $ffDistDir "policies.json") -Value $policiesJson -Encoding UTF8
Write-Log "Firefox policies.json written with $($firefoxExtensions.Count) extensions" "OK"
Write-Log "Extensions will auto-install on next Firefox launch" "OK"

# ============================================================================
# Chrome / Edge / Chromium Extensions (via registry force-install)
# ============================================================================
Write-Log "Configuring Chromium browser extensions..."

# Chromium-based browsers support force-install via registry ExtensionInstallForcelist
# Format: "extensionID;https://clients2.google.com/service/update2/crx"

$chromeExtensions = @(
    @{ id = "cpelbbaiigmeokpdbpfmicohjpoabehb"; name = "Claude" },
    @{ id = "ifbmpadnjkicnmceipommidoolbpfookn"; name = "Live Editor for CSS (Magic CSS)" },
    @{ id = "bhlhnicpbhignbdhedgjhgdocnmhomnp"; name = "ColorZilla" },
    @{ id = "gebbhagfogifgklhldgnhbkdgdpfbpnj"; name = "Return YouTube Dislike" },
    @{ id = "mpiodijhokgodhhofbcjdecpffjipkle"; name = "SingleFile" },
    @{ id = "clngdbkpkpeebahjckkjfobafhncgmne"; name = "Stylus" },
    @{ id = "dhdgffkkebhmkfjojejmpbldmpobfkfo"; name = "Tampermonkey" },
    @{ id = "gppongmhjkpfnbhagpmjfkannfbllamg"; name = "Wappalyzer" },
    @{ id = "blipmdconlkpinefehnmjammfjpmpbjk"; name = "Lighthouse" },
    @{ id = "fdpohaocaechififmbbbbbknoalclacl"; name = "GoFullPage" }
)
$updateUrl = "https://clients2.google.com/service/update2/crx"

# Registry paths for each browser's force-install policy
$browserPolicies = @(
    @{ name = "Google Chrome";        path = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" },
    @{ name = "Microsoft Edge";       path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist" },
    @{ name = "Ungoogled Chromium";   path = "HKLM:\SOFTWARE\Policies\Chromium\ExtensionInstallForcelist" }
)

foreach ($browser in $browserPolicies) {
    Write-Log "Configuring extensions for $($browser.name)..."

    # Create the registry key if it doesn't exist
    if (-not (Test-Path $browser.path)) {
        New-Item -Path $browser.path -Force | Out-Null
    }

    # Get existing entries to avoid duplicates and find next index
    $existing = Get-ItemProperty -Path $browser.path -ErrorAction SilentlyContinue
    $existingValues = @()
    if ($existing) {
        $existingValues = $existing.PSObject.Properties |
            Where-Object { $_.Name -match "^\d+$" } |
            ForEach-Object { $_.Value }
    }
    $nextIndex = 0
    if ($existing) {
        $maxIdx = ($existing.PSObject.Properties |
            Where-Object { $_.Name -match "^\d+$" } |
            ForEach-Object { [int]$_.Name } |
            Measure-Object -Maximum).Maximum
        if ($maxIdx) { $nextIndex = $maxIdx + 1 }
    }

    foreach ($ext in $chromeExtensions) {
        $entry = "$($ext.id);$updateUrl"
        if ($existingValues -contains $entry) {
            Write-Log "$($ext.name) already configured for $($browser.name)" "OK"
        } else {
            Set-ItemProperty -Path $browser.path -Name "$nextIndex" -Value $entry -Type String
            Write-Log "$($ext.name) force-installed for $($browser.name)" "OK"
            $nextIndex++
        }
    }
}

# Also enable extension install from Chrome Web Store for Edge (it blocks by default)
$EdgeCompatPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $EdgeCompatPath)) { New-Item -Path $EdgeCompatPath -Force | Out-Null }
# Allow Chrome Web Store extensions in Edge
$EdgeAllowedStores = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallSources"
if (-not (Test-Path $EdgeAllowedStores)) { New-Item -Path $EdgeAllowedStores -Force | Out-Null }
Set-ItemProperty -Path $EdgeAllowedStores -Name "1" -Value "https://clients2.google.com/service/update2/crx" -Type String
Set-ItemProperty -Path $EdgeAllowedStores -Name "2" -Value "https://chrome.google.com/webstore/*" -Type String

Write-Log "Chromium browser extensions configured (all 3 browsers)" "OK"

Write-Log "Module 13 - Browser Extensions completed" "OK"

