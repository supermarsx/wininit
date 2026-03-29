# Module: 15 - Portable Tools
# C:\bin portable binaries + C:\apps portable applications

Write-Section "Portable Tools" "C:\bin binaries + C:\apps applications"

# ============================================================================
# C:\bin Portable Binaries
# ============================================================================

$binDir = "C:\bin"
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir -Force | Out-Null }

# Add C:\bin to system PATH permanently (if not already there)
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notmatch [regex]::Escape($binDir)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$binDir", "Machine")
    $env:Path = "$env:Path;$binDir"
    Write-Log "C:\bin added to system PATH" "OK"
} else {
    Write-Log "C:\bin already in PATH" "OK"
}

# --- GNU/Unix-like tools for Windows (dynamically resolved from GitHub) ---

# Define tools: Repo, asset pattern (regex), exe name, archive type
$githubTools = @(
    @{ Name="ripgrep";   Repo="BurntSushi/ripgrep";      Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="rg.exe" },
    @{ Name="fd";        Repo="sharkdp/fd";               Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="fd.exe" },
    @{ Name="bat";       Repo="sharkdp/bat";              Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="bat.exe" },
    @{ Name="fzf";       Repo="junegunn/fzf";             Pattern="windows_amd64\.zip$";             Exe="fzf.exe" },
    @{ Name="delta";     Repo="dandavison/delta";          Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="delta.exe" },
    @{ Name="lazygit";   Repo="jesseduffield/lazygit";     Pattern="(?i)windows.*x86_64\.zip$";      Exe="lazygit.exe" },
    @{ Name="eza";       Repo="eza-community/eza";         Pattern="x86_64.*windows.*\.zip$";         Exe="eza.exe" },
    @{ Name="zoxide";    Repo="ajeetdsouza/zoxide";        Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="zoxide.exe" },
    @{ Name="dust";      Repo="bootandy/dust";             Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="dust.exe" },
    @{ Name="procs";     Repo="dalance/procs";             Pattern="x86_64.*windows\.zip$";           Exe="procs.exe" },
    @{ Name="bottom";    Repo="ClementTsang/bottom";       Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="btm.exe" },
    @{ Name="hyperfine"; Repo="sharkdp/hyperfine";         Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="hyperfine.exe" },
    @{ Name="sd";        Repo="chmln/sd";                  Pattern="x86_64-pc-windows-msvc\.zip$";   Exe="sd.exe" },
    @{ Name="glow";      Repo="charmbracelet/glow";        Pattern="(?i)Windows_x86_64\.zip$";       Exe="glow.exe" },
    @{ Name="tokei";     Repo="XAMPPRocky/tokei";          Pattern="x86_64-pc-windows-msvc\.exe$";   Exe="tokei.exe"; Type="direct" }
)

Start-Spinner "Downloading CLI tools to C:\bin..." -Total $githubTools.Count

foreach ($tool in $githubTools) {
    $destExe = Join-Path $binDir $tool.Exe
    if (Test-Path $destExe) {
        Update-SpinnerProgress "$($tool.Name) (exists)"
        continue
    }
    Update-SpinnerProgress "Downloading $($tool.Name)..."

    $url = Get-GitHubReleaseUrl -Repo $tool.Repo -Pattern $tool.Pattern
    if ($url) {
        $archType = if ($tool.ContainsKey("Type")) { $tool.Type } else { "zip" }
        Install-PortableBin -Name $tool.Name -Url $url -ExeName $tool.Exe -ArchiveType $archType
    } else {
        Write-Log "$($tool.Name) - could not resolve download URL from $($tool.Repo)" "WARN"
    }
}

# Static URL tools (not on GitHub or don't need dynamic resolution)
Update-SpinnerMessage "Downloading yq..."
Install-PortableBin -Name "yq" `
    -Url "https://github.com/mikefarah/yq/releases/latest/download/yq_windows_amd64.exe" `
    -ExeName "yq.exe" -ArchiveType "direct"

Update-SpinnerMessage "Downloading wget..."
Install-PortableBin -Name "wget" `
    -Url "https://eternallybored.org/misc/wget/1.21.4/64/wget.exe" `
    -ExeName "wget.exe" -ArchiveType "direct"

Stop-Spinner -FinalMessage "C:\bin: $((Get-ChildItem $binDir -Filter '*.exe' -ErrorAction SilentlyContinue).Count) tools installed" -Status "OK"

# --- Additional C:\bin tools ---

# ADB (Android Debug Bridge) + dependencies
if (Test-Path (Join-Path $binDir "adb.exe")) {
    Write-Log "ADB already in C:\bin" "OK"
} else {
    Start-Spinner "Downloading ADB (platform-tools)..."
    try {
        $adbZipUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
        $adbZipPath = Join-Path $env:TEMP "platform-tools.zip"
        $adbExtract = Join-Path $env:TEMP "platform-tools-extract"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $adbZipUrl -OutFile $adbZipPath -UseBasicParsing
        Update-SpinnerMessage "Extracting ADB..."
        if (Test-Path $adbExtract) { Remove-Item $adbExtract -Recurse -Force }
        Expand-Archive -Path $adbZipPath -DestinationPath $adbExtract -Force
        Get-ChildItem (Join-Path $adbExtract "platform-tools") -File | ForEach-Object {
            Copy-Item $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
        }
        Remove-Item $adbZipPath, $adbExtract -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Spinner -FinalMessage "ADB + fastboot -> C:\bin" -Status "OK"
    } catch {
        Stop-Spinner -FinalMessage "ADB download failed" -Status "ERROR"
        Write-Log "ADB download failed: $_" "ERROR"
    }
}

# FFmpeg (full build - large download ~80MB)
if (Test-Path (Join-Path $binDir "ffmpeg.exe")) {
    Write-Log "FFmpeg already in C:\bin" "OK"
} else {
    Start-Spinner "Downloading FFmpeg (this may take a minute)..."
    try {
        $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        $ffmpegZip = Join-Path $env:TEMP "ffmpeg.zip"
        $ffmpegExtract = Join-Path $env:TEMP "ffmpeg-extract"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $ffmpegZip -UseBasicParsing
        Update-SpinnerMessage "Extracting FFmpeg..."
        if (Test-Path $ffmpegExtract) { Remove-Item $ffmpegExtract -Recurse -Force }
        Expand-Archive -Path $ffmpegZip -DestinationPath $ffmpegExtract -Force
        Get-ChildItem $ffmpegExtract -Recurse -Filter "*.exe" | Where-Object {
            $_.Name -match "^(ffmpeg|ffprobe|ffplay)\.exe$"
        } | ForEach-Object {
            Copy-Item $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
        }
        Remove-Item $ffmpegZip, $ffmpegExtract -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Spinner -FinalMessage "FFmpeg (ffmpeg, ffprobe, ffplay) -> C:\bin" -Status "OK"
    } catch {
        Stop-Spinner -FinalMessage "FFmpeg download failed" -Status "ERROR"
        Write-Log "FFmpeg download failed: $_" "ERROR"
    }
}

# PSExec (from Sysinternals - single exe)
Install-PortableBin -Name "psexec" `
    -Url "https://live.sysinternals.com/PsExec64.exe" `
    -ExeName "psexec64.exe" -ArchiveType "direct"

# TrID (file identifier)
if (Test-Path (Join-Path $binDir "trid.exe")) {
    Write-Log "TrID already in C:\bin" "OK"
} else {
    Write-Log "Downloading TrID..."
    try {
        $tridZipUrl = "https://mark0.net/download/trid_w32.zip"
        $tridDefsUrl = "https://mark0.net/download/triddefs.zip"
        $tridZip = Join-Path $env:TEMP "trid.zip"
        $tridDefsZip = Join-Path $env:TEMP "triddefs.zip"
        $tridExtract = Join-Path $env:TEMP "trid-extract"
        Invoke-WebRequest -Uri $tridZipUrl -OutFile $tridZip -UseBasicParsing
        Invoke-WebRequest -Uri $tridDefsUrl -OutFile $tridDefsZip -UseBasicParsing
        if (Test-Path $tridExtract) { Remove-Item $tridExtract -Recurse -Force }
        Expand-Archive -Path $tridZip -DestinationPath $tridExtract -Force
        Expand-Archive -Path $tridDefsZip -DestinationPath $tridExtract -Force
        Get-ChildItem $tridExtract -File | ForEach-Object {
            Copy-Item $_.FullName -Destination (Join-Path $binDir $_.Name) -Force
        }
        Remove-Item $tridZip, $tridDefsZip, $tridExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "TrID + definitions installed to C:\bin" "OK"
    } catch { Write-Log "TrID download failed: $_" "ERROR" }
}

# raw2iso removed - GitHub repo no longer exists

# signtool - comes with Windows SDK, install via winget
Install-App "Windows SDK (signtool)" -WingetId "Microsoft.WindowsSDK.10.0.26100" -ChocoId "windows-sdk-10-version-2104-windbg"

Write-Log "Additional C:\bin tools installed" "OK"

# ============================================================================
# C:\apps Portable Applications
# ============================================================================
Write-SubStep "C:\apps Portable Applications"

$appsDir = "C:\apps"
if (-not (Test-Path $appsDir)) { New-Item -ItemType Directory -Path $appsDir -Force | Out-Null }

# Add C:\apps to system PATH too (some tools need their folder)
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notmatch [regex]::Escape($appsDir)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$appsDir", "Machine")
    $env:Path = "$env:Path;$appsDir"
    Write-Log "C:\apps added to system PATH" "OK"
}

# --- NirSoft Tools ---
Install-PortableApp -Name "HashMyFiles" `
    -Url "https://www.nirsoft.net/utils/hashmyfiles-x64.zip"

Install-PortableApp -Name "BlueScreenView" `
    -Url "https://www.nirsoft.net/utils/bluescreenview-x64.zip"

Install-PortableApp -Name "ShellExView" `
    -Url "https://www.nirsoft.net/utils/shexview-x64.zip"

Install-PortableApp -Name "AppCrashView" `
    -Url "https://www.nirsoft.net/utils/appcrashview.zip"

Install-PortableApp -Name "InstalledDriversList" `
    -Url "https://www.nirsoft.net/utils/installeddriverslist-x64.zip"

Install-PortableApp -Name "USBDeview" `
    -Url "https://www.nirsoft.net/utils/usbdeview-x64.zip"

Install-PortableApp -Name "ProcessActivityView" `
    -Url "https://www.nirsoft.net/utils/processactivityview-x64.zip"

# --- Reverse Engineering / Debug / Decompilers ---

# jadx - Java/Android decompiler (with bundled JRE)
$jadxUrl = Get-GitHubReleaseUrl -Repo "skylot/jadx" -Pattern "jadx-gui-.*-with-jre-win\.zip$"
if ($jadxUrl) {
    Install-PortableApp -Name "jadx" -Url $jadxUrl
} else {
    Write-Log "jadx - could not resolve GitHub release URL" "WARN"
}

# dnSpyEx - .NET decompiler, debugger, and assembly editor
$dnspyUrl = Get-GitHubReleaseUrl -Repo "dnSpyEx/dnSpy" -Pattern "dnSpy-net-win64\.zip$"
if ($dnspyUrl) {
    Install-PortableApp -Name "dnSpy" -Url $dnspyUrl
} else {
    Write-Log "dnSpy - could not resolve GitHub release URL" "WARN"
}

# ILSpy - .NET assembly browser and decompiler
$ilspyUrl = Get-GitHubReleaseUrl -Repo "icsharpcode/ILSpy" -Pattern "ILSpy_binaries_.*-x64\.zip$"
if ($ilspyUrl) {
    Install-PortableApp -Name "ILSpy" -Url $ilspyUrl
} else {
    Write-Log "ILSpy - could not resolve GitHub release URL" "WARN"
}

# PE-bear - PE file analyzer (detailed headers, sections, imports/exports)
$pebearUrl = Get-GitHubReleaseUrl -Repo "hasherezade/pe-bear" -Pattern "PE-bear_.*_x64_win.*\.zip$"
if ($pebearUrl) {
    Install-PortableApp -Name "PE-bear" -Url $pebearUrl
} else {
    Write-Log "PE-bear - could not resolve GitHub release URL" "WARN"
}

# Detect It Easy (DIE) - packer/compiler/file type detection
$dieUrl = Get-GitHubReleaseUrl -Repo "horsicq/DIE-engine" -Pattern "die_win64_portable_.*_x64\.zip$"
if ($dieUrl) {
    Install-PortableApp -Name "DIE" -Url $dieUrl
} else {
    Write-Log "Detect It Easy - could not resolve GitHub release URL" "WARN"
}

# x64dbg - Windows debugger (dynamic URL, asset name includes timestamp)
$x64dbgUrl = Get-GitHubReleaseUrl -Repo "x64dbg/x64dbg" -Pattern "^snapshot_.*\.zip$"
if ($x64dbgUrl) {
    Install-PortableApp -Name "x64dbg" -Url $x64dbgUrl
} else {
    Write-Log "x64dbg - could not resolve GitHub release URL" "WARN"
}

Install-PortableApp -Name "HxD" `
    -Url "https://mh-nexus.de/downloads/HxDSetup.zip"

# APIMonitor - rohitab.com unreliable, use Internet Archive mirror
Install-PortableApp -Name "APIMonitor" `
    -Url "https://archive.org/download/api-monitor-v2r13-setup-x86/api-monitor-v2r13-x86-x64.zip"

# --- Screen / Remote ---
# scrcpy - dynamic URL (version in filename)
$scrcpyUrl = Get-GitHubReleaseUrl -Repo "Genymobile/scrcpy" -Pattern "scrcpy-win64-v[\d.]+\.zip$"
if ($scrcpyUrl) {
    Install-PortableApp -Name "scrcpy" -Url $scrcpyUrl
} else {
    Write-Log "scrcpy - could not resolve GitHub release URL" "WARN"
}

# UltraVNC - direct download from uvnc.eu
Install-PortableApp -Name "UltraVNC" `
    -Url "https://uvnc.eu/download/1640/UltraVNC_1640.zip"

# --- CEF Binary (Chromium Embedded Framework) ---
# CEF builds change URL with each Chromium version - try spotifycdn, fall back gracefully
Install-PortableApp -Name "CEFBinary" `
    -Url "https://cef-builds.spotifycdn.com/cef_binary_146.0.7%2Bga6b143f%2Bchromium-146.0.7680.165_windows64_minimal.tar.bz2" `
    -ArchiveType "7z"

# --- Compression / Binary ---
# UPX - dynamic URL (version in filename)
$upxUrl = Get-GitHubReleaseUrl -Repo "upx/upx" -Pattern "upx-[\d.]+-win64\.zip$"
if ($upxUrl) {
    Install-PortableApp -Name "UPX" -Url $upxUrl
} else {
    Write-Log "UPX - could not resolve GitHub release URL" "WARN"
}

# --- Network ---
# DNSBench removed - GRC discontinued free version, now paid product

Install-PortableApp -Name "TFTPD64" `
    -Url "https://github.com/PJO2/tftpd64/releases/download/v4.74/tftpd64_portable_v4.74.zip"

# --- Bulk Rename ---
Install-PortableApp -Name "BulkRenameUtility" `
    -Url "https://www.bulkrenameutility.co.uk/Downloads/BRU_NoInstall.zip"

# --- System Performance ---
# DPC Latency Checker removed - discontinued by Thesycon, no longer available

Install-PortableApp -Name "UnparkCPU" `
    -Url "https://coderbag.com/assets/downloads/disable-cpu-core-parking/Unpark-CPU-App.zip"

# ThrottleStop - TechPowerUp CDN requires referral headers, direct URLs 404
# Use package managers instead (they handle auth), then fall back to winget install to apps
if (-not (Test-Path "C:\apps\ThrottleStop")) {
    $throttleInstalled = $false

    # Method 1: winget (handles TechPowerUp auth)
    $r = Invoke-Silent "winget" "install --id TechPowerUp.ThrottleStop -e --accept-source-agreements --accept-package-agreements --silent --disable-interactivity"
    if ($r.ExitCode -eq 0 -or $r.Output -match "already installed|successfully installed") {
        # winget installs to Program Files - copy to C:\apps for consistency
        $wingetThrottle = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "ThrottleStop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $wingetThrottle) {
            $wingetThrottle = Get-ChildItem "C:\Program Files" -Recurse -Filter "ThrottleStop.exe" -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($wingetThrottle) {
            $tsDir = "C:\apps\ThrottleStop"
            New-Item -ItemType Directory -Path $tsDir -Force | Out-Null
            Copy-Item (Join-Path $wingetThrottle.DirectoryName "*") $tsDir -Recurse -Force
            $throttleInstalled = $true
            Write-Log "ThrottleStop installed via winget" "OK"
        }
    }

    # Method 2: scoop (also handles auth via its manifest)
    if (-not $throttleInstalled) {
        $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
        if ($scoopCmd) {
            $r = Invoke-Silent "scoop" "install extras/throttlestop"
            $scoopTs = "$env:USERPROFILE\scoop\apps\throttlestop\current\ThrottleStop.exe"
            if (Test-Path $scoopTs) {
                $tsDir = "C:\apps\ThrottleStop"
                New-Item -ItemType Directory -Path $tsDir -Force | Out-Null
                Copy-Item (Join-Path (Split-Path $scoopTs) "*") $tsDir -Recurse -Force
                $throttleInstalled = $true
                Write-Log "ThrottleStop installed via scoop" "OK"
            }
        }
    }

    # Method 3: choco
    if (-not $throttleInstalled) {
        $r = Invoke-Silent "choco" "install throttlestop -y --no-progress"
        if ($r.ExitCode -eq 0) {
            $chocoTs = Get-ChildItem "C:\ProgramData\chocolatey\lib\throttlestop" -Recurse -Filter "ThrottleStop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($chocoTs) {
                $tsDir = "C:\apps\ThrottleStop"
                New-Item -ItemType Directory -Path $tsDir -Force | Out-Null
                Copy-Item (Join-Path $chocoTs.DirectoryName "*") $tsDir -Recurse -Force
                $throttleInstalled = $true
                Write-Log "ThrottleStop installed via choco" "OK"
            }
        }
    }

    if (-not $throttleInstalled) { Write-Log "ThrottleStop - all methods failed (winget/scoop/choco)" "WARN" }
} else {
    Write-Log "ThrottleStop already in C:\apps" "OK"
}

# --- Bootable USB creators (portable) ---
Write-Log "Downloading YUMI tools..."
$yumiDir = Join-Path $appsDir "YUMI"
if (-not (Test-Path $yumiDir)) { New-Item -ItemType Directory -Path $yumiDir -Force | Out-Null }

# YUMI UEFI
$yumiUefi = Join-Path $yumiDir "YUMI-UEFI.exe"
if (-not (Test-Path $yumiUefi)) {
    try {
        Invoke-WebRequest -Uri "https://www.pendrivelinux.com/downloads/YUMI/YUMI-UEFI-0.0.4.3.exe" `
            -OutFile $yumiUefi -UseBasicParsing
        Write-Log "YUMI UEFI downloaded" "OK"
    } catch { Write-Log "YUMI UEFI download failed: $_" "ERROR" }
}

# YUMI exFAT (legacy/x64)
$yumiExfat = Join-Path $yumiDir "YUMI-exFAT.exe"
if (-not (Test-Path $yumiExfat)) {
    try {
        Invoke-WebRequest -Uri "https://www.pendrivelinux.com/downloads/YUMI/YUMI-exFAT-1.0.2.8.exe" `
            -OutFile $yumiExfat -UseBasicParsing
        Write-Log "YUMI exFAT downloaded" "OK"
    } catch { Write-Log "YUMI exFAT download failed: $_" "ERROR" }
}

Write-Log "C:\apps populated with portable applications" "OK"
Write-Log "Apps directory: C:\apps - $(( Get-ChildItem $appsDir -Directory ).Count) tools extracted" "OK"

# ============================================================================
# Archive tools in PATH (7z, unrar, etc.)
# ============================================================================
Write-Log "Ensuring archive tools are available in PATH..."

# 7-Zip - add to PATH so 7z.exe works from any terminal
$7zDir = "C:\Program Files\7-Zip"
if (Test-Path $7zDir) {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notmatch [regex]::Escape($7zDir)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$7zDir", "Machine")
        $env:Path = "$env:Path;$7zDir"
        Write-Log "7-Zip added to PATH (7z, 7za available from terminal)" "OK"
    }
} else {
    Write-Log "7-Zip not found at $7zDir - install 7-Zip first" "WARN"
}

# unrar - download standalone unrar.exe to C:\bin
Install-PortableBin -Name "unrar" `
    -Url "https://www.rarlab.com/rar/unrarw64.exe" `
    -ExeName "unrar.exe" -ArchiveType "direct"

# xz - standalone xz.exe for .xz/.lzma archives
Install-PortableBin -Name "xz" `
    -Url "https://github.com/tukaani-project/xz/releases/download/v5.8.2/xz-5.8.2-windows.zip" `
    -ExeName "xz.exe"

# zstd - Facebook's fast compression
$zstdUrl = Get-GitHubReleaseUrl -Repo "facebook/zstd" -Pattern "zstd-v[\d.]+-win64\.zip$"
if ($zstdUrl) {
    Install-PortableBin -Name "zstd" -Url $zstdUrl -ExeName "zstd.exe"
}

Write-Log "Archive tools (7z, unrar, xz, zstd) available in PATH" "OK"

Write-Log "Module 15 - Portable Tools completed" "OK"

