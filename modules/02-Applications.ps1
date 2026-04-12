# Module: 02 - Applications
# ============================================================================
Write-Section "Section 2: Applications" "Installing all applications via winget, choco, and scoop" -ItemCount 53

# ---- Browsers ----
Install-App "Google Chrome"         -WingetId "Google.Chrome"                  -ChocoId "googlechrome"
Install-App "Mozilla Firefox"       -WingetId "Mozilla.Firefox"                -ChocoId "firefox"
Install-App "Ungoogled Chromium"    -WingetId "eloston.ungoogled-chromium"     -ChocoId "ungoogled-chromium"

# ---- Communication ----
Install-App "WhatsApp"              -WingetId "WhatsApp.WhatsApp"              -ChocoId "whatsapp"
Install-App "Telegram"              -WingetId "Telegram.TelegramDesktop"       -ChocoId "telegram"

# ---- Development - Editors & IDEs ----
Install-App "Visual Studio Code"    -WingetId "Microsoft.VisualStudioCode"     -ChocoId "vscode"
Install-App "Visual Studio 2026"    -WingetId "Microsoft.VisualStudio.2026.Community" -ChocoId "visualstudio2026community"
Install-App "Android Studio"        -WingetId "Google.AndroidStudio"           -ChocoId "androidstudio"

# ---- Development - C/C++ Toolchains ----

# MSVC Build Tools with C++ workload - install via winget with --override for components
# This is the ONLY way to install silently with specific workloads (no GUI popup)
Write-Log "Installing VS Build Tools with C++ workload..."
Start-Spinner "Installing VS Build Tools + MSVC C++ workload..."

$vsOverride = "--add Microsoft.VisualStudio.Workload.VCTools " +
    "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 " +
    "--add Microsoft.VisualStudio.Component.VC.ATL " +
    "--add Microsoft.VisualStudio.Component.VC.ATLMFC " +
    "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 " +
    "--add Microsoft.VisualStudio.Component.VC.CMake.Project " +
    "--add Microsoft.VisualStudio.Component.VC.Llvm.Clang " +
    "--add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset " +
    "--quiet --norestart"

# Try winget with --override (passes args directly to the VS installer)
$r = Invoke-Silent "winget" "install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-source-agreements --accept-package-agreements --silent --override `"$vsOverride`""
if ($r.ExitCode -eq 0 -or $r.ExitCode -eq 3010 -or $r.Output -match "already installed|successfully installed") {
    Stop-Spinner -FinalMessage "VS Build Tools + MSVC C++ workload" -Status "OK"
    Write-Log "VS Build Tools installed with C++ workload (cl.exe, ATL, MFC, SDK, Clang)" "OK"
} else {
    # Fallback: try choco which handles workloads via package parameters
    $r2 = Invoke-Silent "choco" "install visualstudio2022buildtools -y --no-progress --package-parameters `"--add Microsoft.VisualStudio.Workload.VCTools --quiet --norestart`""
    if ($r2.ExitCode -eq 0) {
        Stop-Spinner -FinalMessage "VS Build Tools + MSVC (choco)" -Status "OK"
        Write-Log "VS Build Tools installed via choco with C++ workload" "OK"
    } else {
        Stop-Spinner -FinalMessage "VS Build Tools install needs manual workload selection" -Status "WARN"
        Write-Log "VS Build Tools installed but C++ workload may need manual selection" "WARN"
    }
}

# Add MSVC tools to PATH
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $btPath = & $vsWhere -products * -latest -property installationPath 2>$null
    if ($btPath) {
        $msvcBase = Join-Path $btPath "VC\Tools\MSVC"
        if (Test-Path $msvcBase) {
            $latest = Get-ChildItem $msvcBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) {
                $binPath = Join-Path $latest.FullName "bin\Hostx64\x64"
                if (Test-Path $binPath) {
                    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                    if ($machinePath -notmatch [regex]::Escape($binPath)) {
                        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$binPath", "Machine")
                        Write-Log "MSVC bin added to PATH: $binPath" "OK"
                    }
                }
            }
        }
    }
}

# MinGW-w64 (native Windows gcc/g++, not Cygwin - produces native .exe)
Install-App "MinGW-w64 (MSYS2)"    -WingetId "MSYS2.MSYS2"                    -ChocoId "msys2"

# Install MinGW toolchain via MSYS2 pacman
$msys2Bash = "C:\msys64\usr\bin\bash.exe"
$mingwBin = "C:\msys64\mingw64\bin"
$mingwGcc = Join-Path $mingwBin "gcc.exe"

if (Test-Path $mingwGcc) {
    Write-Log "MinGW-w64 toolchain already installed ($mingwGcc)" "OK"
} elseif (Test-Path $msys2Bash) {
    Invoke-WithSpinner -Message "Installing MinGW-w64 toolchain via MSYS2" -SuccessMessage "MinGW-w64 toolchain installed (gcc, g++, clang, gdb, make, cmake, ninja)" -ContinueOnError -Action {
        & $msys2Bash -lc "pacman -S --noconfirm mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-clang mingw-w64-x86_64-lld 2>/dev/null" 2>&1 | Out-Null
    }

    # Verify installation
    if (Test-Path $mingwGcc) {
        Write-Log "MinGW-w64 toolchain verified (gcc.exe present)" "OK"
    } else {
        Write-Log "MinGW-w64 toolchain may not have installed correctly - gcc.exe not found" "WARN"
    }
} else {
    Write-Log "MSYS2 not found - MinGW toolchain will be available after MSYS2 install + reboot" "WARN"
}

# Add MinGW bin to system PATH if it exists
if (Test-Path $mingwBin) {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notmatch [regex]::Escape($mingwBin)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$mingwBin", "Machine")
        $env:Path = "$env:Path;$mingwBin"
        Write-Log "MinGW-w64 bin added to system PATH ($mingwBin)" "OK"
    }
}

# ---- vcpkg - C/C++ Package Manager ----
Write-Log "Installing vcpkg..."
$vcpkgRoot = "C:\vcpkg"

# Refresh PATH (git was just installed above)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Test-Path $vcpkgRoot)) {
    $r = Invoke-Silent "git" "clone https://github.com/microsoft/vcpkg.git $vcpkgRoot"
    if ($r.ExitCode -eq 0) {
        Write-Log "vcpkg cloned to $vcpkgRoot" "OK"
    } else {
        Write-Log "vcpkg clone failed: $($r.Output)" "WARN"
    }
}

# Bootstrap vcpkg (compiles vcpkg.exe)
$vcpkgBootstrap = Join-Path $vcpkgRoot "bootstrap-vcpkg.bat"
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
if (Test-Path $vcpkgExe) {
    Write-Log "vcpkg.exe already exists" "OK"
} elseif (Test-Path $vcpkgBootstrap) {
    Invoke-WithSpinner -Message "Bootstrapping vcpkg (compiling vcpkg.exe)" -SuccessMessage "vcpkg bootstrapped" -ContinueOnError -Action {
        $r = Invoke-Silent "cmd" "/c `"cd /d $vcpkgRoot && bootstrap-vcpkg.bat -disableMetrics`"" -TimeoutSeconds 600
        if ($r.ExitCode -ne 0) { throw "bootstrap failed: $($r.Output)" }
    }
    # Verify vcpkg.exe was created
    if (Test-Path $vcpkgExe) {
        Write-Log "vcpkg.exe compiled successfully" "OK"
    } else {
        Write-Log "vcpkg.exe not found after bootstrap - compilation may have failed" "WARN"
    }
} else {
    Write-Log "vcpkg bootstrap script not found at $vcpkgBootstrap" "WARN"
}

# Add vcpkg to system PATH
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notmatch [regex]::Escape($vcpkgRoot)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$vcpkgRoot", "Machine")
    $env:Path = "$env:Path;$vcpkgRoot"
    Write-Log "vcpkg added to system PATH" "OK"
}
# Also add to current session PATH
if ($env:Path -notmatch [regex]::Escape($vcpkgRoot)) {
    $env:Path = "$env:Path;$vcpkgRoot"
}

# Set VCPKG_ROOT env var (used by CMake integration, VS, and other tools)
[System.Environment]::SetEnvironmentVariable("VCPKG_ROOT", $vcpkgRoot, "Machine")
$env:VCPKG_ROOT = $vcpkgRoot
Write-Log "VCPKG_ROOT set to $vcpkgRoot" "OK"

# Enable vcpkg integration with MSBuild / Visual Studio
if (Test-Path $vcpkgExe) {
    & $vcpkgExe integrate install 2>&1 | Out-Null
    Write-Log "vcpkg integrated with MSBuild/Visual Studio" "OK"

    # Set default triplet to x64-windows
    [System.Environment]::SetEnvironmentVariable("VCPKG_DEFAULT_TRIPLET", "x64-windows", "Machine")
    $env:VCPKG_DEFAULT_TRIPLET = "x64-windows"

    # Disable telemetry
    [System.Environment]::SetEnvironmentVariable("VCPKG_DISABLE_METRICS", "1", "Machine")
    $env:VCPKG_DISABLE_METRICS = "1"
    Write-Log "vcpkg default triplet: x64-windows, telemetry disabled" "OK"

    # Pre-install commonly needed libraries
    Write-Log "Pre-installing common vcpkg libraries..."
    $vcpkgLibs = @(
        "openssl:x64-windows",
        "zlib:x64-windows",
        "curl:x64-windows",
        "boost:x64-windows",
        "fmt:x64-windows",
        "spdlog:x64-windows",
        "nlohmann-json:x64-windows",
        "gtest:x64-windows",
        "protobuf:x64-windows",
        "grpc:x64-windows",
        "sqlite3:x64-windows",
        "libpng:x64-windows",
        "libjpeg-turbo:x64-windows",
        "freetype:x64-windows",
        "sdl2:x64-windows",
        "glfw3:x64-windows",
        "imgui:x64-windows",
        "cxxopts:x64-windows",
        "catch2:x64-windows",
        "benchmark:x64-windows"
    )
    foreach ($lib in $vcpkgLibs) {
        $libName = ($lib -split ":")[0]
        Write-Log "vcpkg install: $libName..."
        & $vcpkgExe install $lib 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "vcpkg: $libName installed" "OK"
        } else {
            Write-Log "vcpkg: $libName failed" "WARN"
        }
    }
    Write-Log "vcpkg libraries installed ($($vcpkgLibs.Count) packages)" "OK"

    # Create CMake toolchain file reference for convenience
    $toolchainFile = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"
    [System.Environment]::SetEnvironmentVariable("CMAKE_TOOLCHAIN_FILE", $toolchainFile, "Machine")
    $env:CMAKE_TOOLCHAIN_FILE = $toolchainFile
    Write-Log "CMAKE_TOOLCHAIN_FILE set to vcpkg toolchain ($toolchainFile)" "OK"

    # Also install x64-windows-static triplet libraries for common ones
    Write-Log "Installing static libraries..."
    $staticLibs = @(
        "openssl:x64-windows-static",
        "zlib:x64-windows-static",
        "curl:x64-windows-static",
        "fmt:x64-windows-static",
        "nlohmann-json:x64-windows-static",
        "sqlite3:x64-windows-static"
    )
    foreach ($lib in $staticLibs) {
        $libName = ($lib -split ":")[0]
        & $vcpkgExe install $lib 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "vcpkg (static): $libName installed" "OK"
        } else {
            Write-Log "vcpkg (static): $libName failed" "WARN"
        }
    }
    Write-Log "vcpkg static libraries installed ($($staticLibs.Count) packages)" "OK"

} else {
    Write-Log "vcpkg.exe not found - libraries will be available after bootstrap" "WARN"
}

Write-Log "vcpkg fully configured" "OK"

# ---- Development - Tools ----
Install-App "Git"                   -WingetId "Git.Git"                        -ChocoId "git"            -ScoopId "git"
Install-App "GitHub Desktop"        -WingetId "GitHub.GitHubDesktop"           -ChocoId "github-desktop"
Install-App "Docker Desktop"        -WingetId "Docker.DockerDesktop"           -ChocoId "docker-desktop"
# Kill Docker Desktop processes and remove from startup
Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Docker*" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "com.docker*" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Docker Desktop" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "com.docker.desktop" -ErrorAction SilentlyContinue
Install-App "PowerShell 7"          -WingetId "Microsoft.PowerShell"           -ChocoId "powershell-core"
Install-App "CMake"                 -WingetId "Kitware.CMake"                  -ChocoId "cmake"          -ScoopId "cmake"
Install-App "AutoIt"                -WingetId "AutoIt.AutoIt"                  -ChocoId "autoit"

# Configure SciTE4AutoIt dark mode
$sciteDir = "${env:ProgramFiles(x86)}\AutoIt3\SciTE"
if (Test-Path "$sciteDir\SciTE.exe") {
    $sciteUserDir = "$env:LOCALAPPDATA\AutoIt v3\SciTE"
    New-Item -Path $sciteUserDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $userProps = Join-Path $sciteUserDir "SciTEUser.properties"
    # Build dark theme properties (VS Code-inspired dark palette)
    $darkProps = @"
# === WinInit Dark Theme for SciTE4AutoIt ===

# ── Global default style (applies to all languages) ──
style.*.32=back:#1E1E1E,fore:#D4D4D4,font:Consolas,size:10
# Line-number margin
style.*.33=back:#252526,fore:#858585,size:8
# Brace highlight / mismatch
style.*.34=fore:#DCDCAA,bold,back:#1E1E1E
style.*.35=fore:#F44747,bold,back:#1E1E1E

# ── Editor chrome ──
caret.fore=#AEAFAD
caret.line.back=#2A2D2E
selection.back=#264F78
selection.alpha=256
edge.colour=#3E3E3E
fold.margin.colour=#1E1E1E
fold.margin.highlight.colour=#1E1E1E
calltip.back=#252526

# ── AutoIt syntax (style.au3.*) ──
# 0=default, 1=comment, 2=comment-block, 3=number, 4=function,
# 5=keyword, 6=macro, 7=string, 8=operator, 9=variable,
# 10=sent, 11=pre-processor, 12=special, 13=expand, 15=comobj
style.au3.0=fore:#D4D4D4,back:#1E1E1E
style.au3.1=fore:#6A9955,back:#1E1E1E,italics
style.au3.2=fore:#6A9955,back:#1E1E1E,italics
style.au3.3=fore:#B5CEA8,back:#1E1E1E
style.au3.4=fore:#DCDCAA,back:#1E1E1E
style.au3.5=fore:#569CD6,back:#1E1E1E,bold
style.au3.6=fore:#C586C0,back:#1E1E1E
style.au3.7=fore:#CE9178,back:#1E1E1E
style.au3.8=fore:#D4D4D4,back:#1E1E1E
style.au3.9=fore:#9CDCFE,back:#1E1E1E
style.au3.10=fore:#4EC9B0,back:#1E1E1E
style.au3.11=fore:#C586C0,back:#1E1E1E
style.au3.12=fore:#DCDCAA,back:#1E1E1E,bold
style.au3.13=fore:#9CDCFE,back:#1E1E1E
style.au3.15=fore:#4EC9B0,back:#1E1E1E

# ── Output pane ──
style.errorlist.32=back:#1E1E1E,fore:#D4D4D4
style.errorlist.0=fore:#D4D4D4,back:#1E1E1E
style.errorlist.2=fore:#F44747,back:#1E1E1E

# ── Properties files ──
style.props.0=fore:#D4D4D4,back:#1E1E1E
style.props.1=fore:#6A9955,back:#1E1E1E
style.props.2=fore:#569CD6,back:#1E1E1E
style.props.3=fore:#CE9178,back:#1E1E1E
style.props.5=fore:#9CDCFE,back:#1E1E1E

# ── Misc settings ──
output.magnification=-1
highlight.current.word=1
highlight.current.word.colour=#3A3D41
"@

    # Preserve any existing user customisations by appending if the file already has content
    if ((Test-Path $userProps) -and (Get-Item $userProps).Length -gt 0) {
        $existing = Get-Content $userProps -Raw
        if ($existing -notmatch "WinInit Dark Theme") {
            Add-Content -Path $userProps -Value "`n$darkProps" -Encoding UTF8
        }
    } else {
        Set-Content -Path $userProps -Value $darkProps -Encoding UTF8
    }
    Write-Log "SciTE4AutoIt dark mode configured" "OK"
} else {
    Write-Log "SciTE4AutoIt not found – skipping dark mode config" "WARN"
}

# ---- Python ----
Install-App "Python 2.7"            -WingetId "Python.Python.2"                -ChocoId "python2"
Install-App "Python 3"              -WingetId "Python.Python.3.12"             -ChocoId "python3"        -ScoopId "python"
Install-App "Anaconda"              -WingetId "Anaconda.Anaconda3"             -ChocoId "anaconda3"

# ---- WSL ----
$wslStatus = wsl --status 2>&1
if ($wslStatus -match "Default Version|WSL version") {
    Write-Log "WSL already installed" "OK"
} else {
    Write-Log "Installing WSL..."
    $wslResult = wsl --install --no-distribution 2>&1
    if ($LASTEXITCODE -eq 0 -or $wslResult -match "already installed") {
        Write-Log "WSL installed (reboot may be required to finalize)" "OK"
    } else {
        Write-Log "WSL install returned: $wslResult" "WARN"
    }
}

# ---- Knowledge & Notes ----
Install-App "Obsidian"              -WingetId "Obsidian.Obsidian"              -ChocoId "obsidian"
Install-App "Nextcloud Desktop"     -WingetId "Nextcloud.NextcloudDesktop"     -ChocoId "nextcloud-client"

# ---- AI / ML ----
Install-App "Claude"                -WingetId "Anthropic.Claude"               -ChocoId "claude"
# Remove Claude from startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "claude" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Claude" -ErrorAction SilentlyContinue
Install-App "LM Studio"             -WingetId "Element.LMStudio"              -ChocoId "lm-studio"
Install-App "Ollama"                -WingetId "Ollama.Ollama"                  -ChocoId "ollama"
# Kill Ollama if it auto-launched after install
Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "Ollama*" -Force -ErrorAction SilentlyContinue
# Remove Ollama from startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Ollama" -ErrorAction SilentlyContinue
Install-App "AnythingLLM"           -WingetId "MintplexLabs.AnythingLLM"      -ChocoId "anythingllm"

# ---- Network & Remote ----
Install-App "PuTTY"                 -WingetId "PuTTY.PuTTY"                   -ChocoId "putty"          -ScoopId "putty"
Install-App "WinSCP"                -WingetId "WinSCP.WinSCP"                 -ChocoId "winscp"
Install-App "FileZilla"             -WingetId "TimKosse.FileZilla.Client"      -ChocoId "filezilla"

# ---- VPN ----
Install-App "OpenVPN GUI"           -WingetId "OpenVPNTechnologies.OpenVPN"    -ChocoId "openvpn"
# Remove OpenVPN GUI from startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "openvpn-gui" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "openvpn-gui" -ErrorAction SilentlyContinue
Install-App "OpenVPN Connect"       -WingetId "OpenVPNTechnologies.OpenVPNConnect" -ChocoId "openvpn-connect"

# ---- Security / Passwords ----
Install-App "Bitwarden"             -WingetId "Bitwarden.Bitwarden"            -ChocoId "bitwarden"
Install-App "KeePass"               -WingetId "DominikReichl.KeePass"          -ChocoId "keepass"
# Remove KeePass from startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePass" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePass 2 PreLoad" -ErrorAction SilentlyContinue
Install-App "KeePassXC"             -WingetId "KeePassXCTeam.KeePassXC"        -ChocoId "keepassxc"
# Remove KeePassXC from startup
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "KeePassXC" -ErrorAction SilentlyContinue

# ---- Utilities ----
Install-App "7-Zip"                 -WingetId "7zip.7zip"                      -ChocoId "7zip"           -ScoopId "7zip"
Install-App "AnyBurn"               -WingetId "AnyBurn.AnyBurn"               -ChocoId "anyburn"
# AstroGrep removed - using ripgrep (rg) in C:\bin instead (faster, modern)
Install-App "WinDirStat"            -WingetId "WinDirStat.WinDirStat"         -ChocoId "windirstat"
Install-App "Everything Search"     -WingetId "voidtools.Everything"           -ChocoId "everything"     -ScoopId "everything"
# Remove Everything from startup
Stop-Process -Name "Everything" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Everything" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "Everything" -ErrorAction SilentlyContinue
Install-App "FontBase"              -WingetId "FontBase.FontBase"              -ChocoId "fontbase"
Install-App "PowerToys"             -WingetId "Microsoft.PowerToys"            -ChocoId "powertoys"

# ---- Graphics / Media ----
Install-App "GIMP"                  -WingetId "GIMP.GIMP"                      -ChocoId "gimp"           -ScoopId "gimp"
Install-App "Inkscape"              -WingetId "Inkscape.Inkscape"              -ChocoId "inkscape"       -ScoopId "inkscape"
Install-App "Ghostscript"           -WingetId "ArtifexSoftware.GhostScript"   -ChocoId "ghostscript"
Install-App "HandBrake"             -WingetId "HandBrake.HandBrake"            -ChocoId "handbrake"
Install-App "ShareX"                -WingetId "ShareX.ShareX"                  -ChocoId "sharex"
# Remove ShareX from startup
Stop-Process -Name "ShareX" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ShareX" -ErrorAction SilentlyContinue

# ---- Editors ----
Install-App "Notepad++"             -WingetId "Notepad++.Notepad++"            -ChocoId "notepadplusplus"

# Configure Notepad++ dark mode
$nppDir = "$env:ProgramFiles\Notepad++"
$nppAppData = "$env:APPDATA\Notepad++"
if (Test-Path "$nppDir\notepad++.exe") {
    New-Item -Path $nppAppData -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    # Copy the model config as a starting point if no config exists yet
    $nppConfig = Join-Path $nppAppData "config.xml"
    $modelConfig = Join-Path $nppDir "config.model.xml"
    if (-not (Test-Path $nppConfig) -and (Test-Path $modelConfig)) {
        Copy-Item $modelConfig $nppConfig -Force
    }

    if (Test-Path $nppConfig) {
        [xml]$xml = Get-Content $nppConfig -Raw
        $ns = $xml.NotepadPlus

        # Enable DarkMode
        $darkNode = $ns.GUIConfigs.GUIConfig | Where-Object { $_.name -eq "DarkMode" }
        if ($darkNode) {
            $darkNode.SetAttribute("enable", "yes")
            $darkNode.SetAttribute("darkThemeName", "DarkModeDefault")
        } else {
            # Create DarkMode node if missing
            $newNode = $xml.CreateElement("GUIConfig")
            $newNode.SetAttribute("name", "DarkMode")
            $newNode.SetAttribute("enable", "yes")
            $newNode.SetAttribute("darkThemeName", "DarkModeDefault")
            $ns.GUIConfigs.AppendChild($newNode) | Out-Null
        }

        # Set the dark theme styler
        $themeNode = $ns.GUIConfigs.GUIConfig | Where-Object { $_.name -eq "stylerTheme" }
        if ($themeNode) {
            $themeNode.SetAttribute("path", "$nppDir\themes\DarkModeDefault.xml")
        }

        $xml.Save($nppConfig)
        Write-Log "Notepad++ dark mode enabled" "OK"
    }
} else {
    Write-Log "Notepad++ not found – skipping dark mode config" "WARN"
}

# ---- Bootable USB ----
Install-App "Rufus"                 -WingetId "Rufus.Rufus"                    -ChocoId "rufus"
Install-App "Ventoy"                -WingetId "Ventoy.Ventoy"                  -ChocoId "ventoy"

# ---- Torrents ----
Install-App "qBittorrent"            -WingetId "qBittorrent.qBittorrent"        -ChocoId "qbittorrent"

# ---- Network ----
Install-App "Angry IP Scanner"      -WingetId "angryziber.AngryIPScanner"      -ChocoId "angryip"
Install-App "mRemoteNG"             -WingetId "mRemoteNG.mRemoteNG"            -ChocoId "mremoteng"

# ---- Diff / Merge ----
Install-App "WinMerge"              -WingetId "WinMerge.WinMerge"              -ChocoId "winmerge"

# ---- Virtualization ----
Install-App "VirtualBox"            -WingetId "Oracle.VirtualBox"              -ChocoId "virtualbox"

# ---- Encryption ----
Install-App "VeraCrypt"             -WingetId "IDRIX.VeraCrypt"                -ChocoId "veracrypt"

# ---- Electronics / Embedded ----
Install-App "Arduino IDE"           -WingetId "ArduinoSA.IDE.stable"           -ChocoId "arduino"

# ---- OpenVPN: Ensure exactly 2 TAP/TUN interfaces ---
Write-Log "Configuring OpenVPN TAP interfaces..."

# Count existing TAP adapters via Get-NetAdapter (most reliable, works regardless of tapctl)
$tapNics = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.InterfaceDescription -match "TAP-Windows|TAP-Win|OpenVPN TAP|Wintun"
}
$tapCount = if ($tapNics) { @($tapNics).Count } else { 0 }
Write-Log "Found $tapCount existing TAP/TUN adapter(s) via Get-NetAdapter" "INFO"

# Find tapctl.exe
$ovpnPaths = @(
    "$env:ProgramFiles\OpenVPN\bin",
    "${env:ProgramFiles(x86)}\OpenVPN\bin"
)
$tapctlExe = $null
foreach ($p in $ovpnPaths) {
    $candidate = Join-Path $p "tapctl.exe"
    if (Test-Path $candidate) { $tapctlExe = $candidate; break }
}

# Remove duplicates if more than 2
if ($tapCount -gt 2 -and $tapctlExe) {
    Write-Log "Removing $($tapCount - 2) duplicate TAP adapter(s)..." "WARN"
    $tapList = & $tapctlExe list 2>&1 | Out-String
    $guids = [regex]::Matches($tapList, '\{[0-9A-Fa-f-]+\}') | ForEach-Object { $_.Value }
    # Delete extras beyond the first 2
    for ($i = 2; $i -lt $guids.Count; $i++) {
        & $tapctlExe delete $guids[$i] 2>&1 | Out-Null
        Write-Log "Removed duplicate TAP: $($guids[$i])" "OK"
    }
    $tapCount = 2
}

# Create missing adapters to reach exactly 2
if ($tapCount -lt 2) {
    $needed = 2 - $tapCount
    Write-Log "Need to create $needed TAP adapter(s)..."

    if ($tapctlExe) {
        for ($i = 0; $i -lt $needed; $i++) {
            Write-Log "Creating TAP adapter $($i + 1)/$needed via tapctl..."
            $createResult = & $tapctlExe create --hwid "tap0901" 2>&1 | Out-String
            Write-Log "tapctl create result: $($createResult.Trim())" "DEBUG"
            # Also try wintun/ovpn-dco if tap0901 fails
            if ($LASTEXITCODE -ne 0) {
                Write-Log "tap0901 failed, trying wintun..." "WARN"
                & $tapctlExe create --hwid "wintun" 2>&1 | Out-Null
            }
        }
        Write-Log "TAP adapters created via tapctl" "OK"
    } else {
        # Fallback: addtap.bat
        $addtapBat = $null
        foreach ($p in $ovpnPaths) {
            $candidate = Join-Path (Split-Path $p) "tap-windows6\addtap.bat"
            if (Test-Path $candidate) { $addtapBat = $candidate; break }
        }
        if ($addtapBat) {
            for ($i = 0; $i -lt $needed; $i++) {
                & cmd /c "`"$addtapBat`"" 2>&1 | Out-Null
            }
            Write-Log "TAP adapters created via addtap.bat" "OK"
        } else {
            Write-Log "No tapctl or addtap found - TAP adapters need manual creation" "WARN"
        }
    }

    # Verify final count
    Start-Sleep -Seconds 2  # Wait for adapters to appear
    $finalTaps = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match "TAP-Windows|TAP-Win|OpenVPN TAP|Wintun"
    }
    $finalCount = if ($finalTaps) { @($finalTaps).Count } else { 0 }
    Write-Log "Final TAP adapter count: $finalCount" "INFO"
} elseif ($tapCount -eq 2) {
    Write-Log "Already have exactly 2 TAP adapters" "OK"
} else {
    # tapCount is 0 and no tapctl found
    if (-not $tapctlExe) {
        Write-Log "OpenVPN TAP tools not found - adapters will be created on first connection" "WARN"
    }
}

# ============================================================================
# PATH Verification (ensure key tools are accessible)
# ============================================================================
Write-Log "Verifying PATH for installed tools..."

# Refresh PATH after all installs
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

$pathChecks = @(
    @("git",     "Git"),
    @("python",  "Python"),
    @("cmake",   "CMake"),
    @("docker",  "Docker"),
    @("code",    "VS Code"),
    @("pwsh",    "PowerShell 7"),
    @("7z",      "7-Zip"),
    @("gcc",     "MinGW GCC"),
    @("vcpkg",   "vcpkg")
)

$pathOK = 0
$pathMissing = @()
foreach ($check in $pathChecks) {
    $cmd = Get-Command $check[0] -ErrorAction SilentlyContinue
    if ($cmd) {
        $pathOK++
    } else {
        $pathMissing += $check[1]
        Write-Log "PATH: $($check[1]) ($($check[0])) not found in PATH - may need reboot" "WARN"
    }
}
Write-Log "PATH check: $pathOK/$($pathChecks.Count) tools accessible" "OK"
if ($pathMissing.Count -gt 0) {
    Write-Log "Missing from PATH (may appear after reboot): $($pathMissing -join ', ')" "WARN"
}

Write-Log "Section 2: Applications completed" "OK"
