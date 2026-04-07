# Module: 14 - Dev Tools
# CLI Dev Tools (Node.js/npm, Copilot CLI, Codex CLI, GitHub CLI, NVM) + WSL config + Hacker/security tools

Write-Section "Dev Tools" "CLI tools, WSL config, security/pentesting tools"

# ============================================================================
# EARLY LAUNCH: Kick off slow background tasks immediately
# These run in parallel with all other installs below
# ============================================================================

# --- Background: Android SDK command-line tools download ---
$androidSdkRoot = "C:\android-sdk"
$bgAndroidJob = $null
$cmdlineToolsDir = Join-Path $androidSdkRoot "cmdline-tools"
if (-not (Test-Path "$cmdlineToolsDir\latest\bin\sdkmanager.bat")) {
    Write-Log "Background: starting Android SDK cmdline-tools download..." "INFO"
    $bgAndroidJob = Start-Job -ScriptBlock {
        param($sdkRoot, $cmdDir)
        $ProgressPreference = 'SilentlyContinue'
        $cmdlineZip = Join-Path $env:TEMP "android-cmdline-tools.zip"
        $cmdlineUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
        try {
            Invoke-WebRequest -Uri $cmdlineUrl -OutFile $cmdlineZip -UseBasicParsing -TimeoutSec 300
            $extractDir = Join-Path $env:TEMP "android-cmdline-extract"
            if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
            Expand-Archive -Path $cmdlineZip -DestinationPath $extractDir -Force
            $latestDir = Join-Path $cmdDir "latest"
            if (-not (Test-Path $cmdDir)) { New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null }
            if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force }
            Move-Item (Join-Path $extractDir "cmdline-tools") $latestDir -Force
            Remove-Item $cmdlineZip, $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            return @{ ok = $true }
        } catch { return @{ ok = $false; error = $_.ToString() } }
    } -ArgumentList $androidSdkRoot, $cmdlineToolsDir
}

# --- Background: pip upgrade + install globals ---
$bgPipJob = $null
$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if ($pythonExe) {
    # Check if pip globals are already installed
    $pipCheckBg = (python -m pip list --format=columns 2>$null) -join "`n"
    $pipAllBg = @("cookiecutter", "pre-commit", "yt-dlp", "httpie", "poetry", "build", "wheel", "setuptools", "bandit")
    $pipNeededBg = @($pipAllBg | Where-Object { $pipCheckBg -notmatch "(?i)^$_\s" })
    if ($pipNeededBg.Count -gt 0) {
        Write-Log "Background: starting pip upgrade + $($pipNeededBg.Count) package installs..." "INFO"
        $bgPipJob = Start-Job -ScriptBlock {
            param($packages)
            $results = @{ upgraded = $false; installed = @(); failed = @() }
            try {
                # Helper: run python without deadlocking (redirect to files, not pipes)
                function Run-Pip {
                    param([string]$Arguments)
                    $id = Get-Random
                    $outFile = "$env:TEMP\wininit-pip-$id.log"
                    $errFile = "$env:TEMP\wininit-pip-$id.err"
                    & cmd /c "python $Arguments >""$outFile"" 2>""$errFile"""
                    $code = $LASTEXITCODE
                    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
                    return $code
                }

                # Upgrade pip
                $code = Run-Pip "-m pip install --upgrade pip"
                $results.upgraded = ($code -eq 0)

                # Batch install: no-deps first pass (fast), then full install
                $allPkgs = $packages -join " "
                Run-Pip "-m pip install --user --no-deps $allPkgs" | Out-Null
                Run-Pip "-m pip install --user $allPkgs" | Out-Null

                # Check which actually installed
                $installedStr = (& python -m pip list --format=columns 2>$null) -join "`n"
                foreach ($pkg in $packages) {
                    if ($installedStr -match "(?i)^$($pkg -replace '-','[-_]')\s") {
                        $results.installed += $pkg
                    } else {
                        $results.failed += $pkg
                    }
                }
            } catch { $results.failed += "EXCEPTION: $($_.ToString())" }
            return $results
        } -ArgumentList (,$pipNeededBg)
    } else {
        Write-Log "Background: pip globals already installed, skipping" "OK"
    }
}

Write-Log "Background tasks launched (SDK + pip will finish during other installs)" "OK"

# ============================================================================
# CLI Dev Tools (npm, GitHub Copilot CLI, Codex CLI)
# ============================================================================

# --- npm (comes with Node.js) ---
# Check if node/npm already exist before trying to install
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
$nodePath = Get-Command node -ErrorAction SilentlyContinue
$npmPath = Get-Command npm -ErrorAction SilentlyContinue
$nodeDir = $null

if ($nodePath -and $npmPath) {
    Write-Log "Node.js already installed: $(node --version 2>$null)" "OK"
} else {
    Write-Log "Installing Node.js..."

    # Method 1 (fastest): direct zip download from nodejs.org — no package manager overhead
    $nodeInstalled = $false
    try {
        $ProgressPreference = 'SilentlyContinue'
        Start-Spinner "Downloading Node.js LTS from nodejs.org..."
        $nodeIndex = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -TimeoutSec 15
        $latestLts = $nodeIndex | Where-Object { $_.lts } | Select-Object -First 1
        $nodeVer = $latestLts.version

        if ($nodeVer) {
            $script:SpinnerSync.Message = "Downloading Node.js $nodeVer..."
            $nodeZipUrl = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-win-x64.zip"
            $nodeZipPath = Join-Path $env:TEMP "node-lts-fast.zip"
            Invoke-WebRequest -Uri $nodeZipUrl -OutFile $nodeZipPath -UseBasicParsing -TimeoutSec 120

            $script:SpinnerSync.Message = "Extracting Node.js $nodeVer..."
            $nodeExtract = Join-Path $env:TEMP "node-lts-fast-extract"
            if (Test-Path $nodeExtract) { Remove-Item $nodeExtract -Recurse -Force }
            Expand-Archive -Path $nodeZipPath -DestinationPath $nodeExtract -Force

            $targetDir = "C:\Program Files\nodejs"
            $extractedDir = @(Get-ChildItem $nodeExtract -Directory)[0]
            if ($extractedDir) {
                if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
                Move-Item $extractedDir.FullName $targetDir -Force

                # Add to PATH
                $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($machinePath -notmatch [regex]::Escape($targetDir)) {
                    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$targetDir", "Machine")
                }
                $npmGlobalDir = "$env:APPDATA\npm"
                if (-not (Test-Path $npmGlobalDir)) { New-Item -ItemType Directory -Path $npmGlobalDir -Force | Out-Null }
                if ($machinePath -notmatch [regex]::Escape($npmGlobalDir)) {
                    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$npmGlobalDir", "Machine")
                }
                $env:Path = "$targetDir;$npmGlobalDir;$env:Path"
                $nodeInstalled = $true
                Stop-Spinner -FinalMessage "Node.js $nodeVer installed (direct download)" -Status "OK"
            }
            Remove-Item $nodeZipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $nodeExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
        $ProgressPreference = 'Continue'
    } catch {
        $ProgressPreference = 'Continue'
        if ($script:SpinnerSync.Active) { Stop-Spinner -FinalMessage "Direct download failed, trying package managers" -Status "WARN" }
    }

    # Check if direct download succeeded or node exists from a previous install
    if (-not $nodeInstalled) {
        # Maybe it's already there from a previous run but wasn't on PATH
        $existingNode = @(
            "C:\Program Files\nodejs\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
            "$env:USERPROFILE\scoop\apps\nodejs-lts\current\node.exe"
        )
        foreach ($np in $existingNode) {
            if (Test-Path $np) {
                $nd = Split-Path $np
                $env:Path = "$nd;$env:Path"
                $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($machinePath -notmatch [regex]::Escape($nd)) {
                    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$nd", "Machine")
                }
                $nodeInstalled = $true
                Write-Log "Node.js found at $nd (added to PATH)" "OK"
                break
            }
        }
    }

    # Method 2: winget/choco/scoop (only if nothing else worked)
    if (-not $nodeInstalled -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
        Install-App "Node.js LTS" -WingetId "OpenJS.NodeJS.LTS" -ChocoId "nodejs-lts" -ScoopId "nodejs-lts"
    }

    # Refresh PATH
    Start-Sleep -Seconds 1
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Find node and npm - retry PATH refresh
$nodePath = $null
$npmPath = $null
$nodeDir = $null

for ($retryPath = 0; $retryPath -lt 3; $retryPath++) {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    $nodePath = Get-Command node -ErrorAction SilentlyContinue
    $npmPath = Get-Command npm -ErrorAction SilentlyContinue
    if ($nodePath -and $npmPath) { break }
    if ($retryPath -lt 2) { Start-Sleep -Seconds 2 }
}

if (-not $nodePath -or -not $npmPath) {
    Write-Log "node/npm not on PATH after install - searching system..." "INFO"

    # Comprehensive list of possible Node.js install locations
    $nodeCandidates = @(
        "$env:ProgramFiles\nodejs",
        "C:\Program Files\nodejs",
        "${env:ProgramFiles(x86)}\nodejs",
        "$env:LOCALAPPDATA\Programs\nodejs",
        "$env:APPDATA\nvm\current",                          # NVM for Windows (symlink)
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links"           # WinGet shim directory
    )

    # Also check NVM versions directory (nvm install puts node here)
    $nvmDir = [System.Environment]::GetEnvironmentVariable("NVM_HOME", "User")
    if ($nvmDir -and (Test-Path $nvmDir)) {
        $nvmVersions = Get-ChildItem $nvmDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^v?\d+" } | Sort-Object Name -Descending
        foreach ($v in $nvmVersions) {
            $nodeCandidates += $v.FullName
        }
    }

    # Check scoop shims
    $scoopShims = "$env:USERPROFILE\scoop\shims"
    if (Test-Path "$scoopShims\node.exe") { $nodeCandidates += $scoopShims }

    # Try where.exe as another discovery method
    $whereResult = where.exe node 2>$null
    if ($whereResult) {
        foreach ($wp in @($whereResult)) {
            $nodeCandidates += (Split-Path $wp)
        }
    }

    # Deep scan: search Program Files for node.exe if still not found
    if (-not ($nodeCandidates | Where-Object { Test-Path "$_\node.exe" })) {
        $deepSearch = Get-ChildItem "$env:ProgramFiles" -Filter "node.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($deepSearch) { $nodeCandidates += $deepSearch.DirectoryName }
        $deepSearch2 = Get-ChildItem "$env:LOCALAPPDATA" -Filter "node.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($deepSearch2) { $nodeCandidates += $deepSearch2.DirectoryName }
    }

    foreach ($dir in ($nodeCandidates | Select-Object -Unique)) {
        if (Test-Path "$dir\node.exe") {
            $nodeDir = $dir
            $env:Path = "$dir;$env:Path"
            Write-Log "Node.js found at $dir" "OK"
            break
        }
    }

    if ($nodeDir) {
        # Add node dir to machine PATH permanently
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($nodeDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$nodeDir", "Machine")
            Write-Log "Node.js added to system PATH: $nodeDir" "OK"
        }

        # Ensure npm global prefix dir is on PATH too
        $npmGlobalDir = "$env:APPDATA\npm"
        if (-not (Test-Path $npmGlobalDir)) { New-Item -ItemType Directory -Path $npmGlobalDir -Force | Out-Null }
        if ($env:Path -notmatch [regex]::Escape($npmGlobalDir)) {
            $env:Path = "$npmGlobalDir;$env:Path"
        }
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($npmGlobalDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$npmGlobalDir", "Machine")
            Write-Log "npm global bin added to system PATH: $npmGlobalDir" "OK"
        }

        $nodePath = Get-Command node -ErrorAction SilentlyContinue
        $npmPath = Get-Command npm -ErrorAction SilentlyContinue

        # Last resort: if npm.cmd not on PATH, invoke it directly by full path
        if (-not $npmPath -and (Test-Path "$nodeDir\npm.cmd")) {
            Write-Log "npm.cmd found at $nodeDir but not resolving via PATH - using direct path" "WARN"
            # Create a function alias so all npm calls in this session work
            $script:NpmDirect = "$nodeDir\npm.cmd"
            function global:npm { & $script:NpmDirect @args }
            $npmPath = $true  # Signal that npm is available
        }
    }
}

if ($nodePath) { Write-Log "node: $(node --version 2>$null)" "OK" }
if ($npmPath) {
    Write-Log "npm: $(npm --version 2>$null)" "OK"

    # Resolve node.exe and npm-cli.js paths for reliable subprocess execution
    # Using "node npm-cli.js" avoids cmd.exe quoting issues with .cmd files
    $nodeExePath = if ($nodePath -and $nodePath.Source) { $nodePath.Source }
                   elseif ($nodeDir) { "$nodeDir\node.exe" }
                   elseif (Test-Path "C:\Program Files\nodejs\node.exe") { "C:\Program Files\nodejs\node.exe" }
                   else { "node" }
    $npmCliJs = Join-Path (Split-Path $nodeExePath) "node_modules\npm\bin\npm-cli.js"
    # Fallback to npm.cmd if npm-cli.js not found
    $npmExePath = if (Test-Path $npmCliJs) { $npmCliJs } else { Join-Path (Split-Path $nodeExePath) "npm.cmd" }
    $useNodeDirect = Test-Path $npmCliJs

    # Helper: run npm command reliably
    function Invoke-Npm {
        param([string]$Arguments)
        if ($useNodeDirect) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $nodeExePath
            $psi.Arguments = "`"$npmCliJs`" $Arguments"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            $proc.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            return @{ ExitCode = $proc.ExitCode; Output = $stdout }
        } else {
            $r = Invoke-Silent "cmd" "/c `"$npmExePath`" $Arguments" -TimeoutSeconds 300
            return $r
        }
    }

    # Get list of already-installed global npm packages
    $npmListResult = Invoke-Npm "list -g --depth=0"
    $npmInstalled = $npmListResult.Output

    # All npm globals to install (including Copilot/Codex CLIs)
    $npmAllPackages = @(
        "@githubnext/github-copilot-cli",    # GitHub Copilot CLI
        "@openai/codex",                      # OpenAI Codex CLI
        "typescript", "ts-node",             # TypeScript
        "nodemon",                            # Auto-restart on changes
        "pm2",                                # Process manager
        "eslint",                             # JS/TS linter
        "prettier",                           # Code formatter
        "serve",                              # Static file server
        "http-server",                        # Quick HTTP server
        "live-server",                        # Dev server with hot reload
        "tldr",                               # Simplified man pages
        "yarn",                               # Alt package manager
        "pnpm",                               # Fast package manager
        "nx",                                 # Monorepo build system
        "vercel",                             # Deploy CLI
        "netlify-cli",                        # Deploy CLI
        "concurrently",                       # Run multiple commands
        "dotenv-cli",                         # Load .env for any command
        "degit"                               # Scaffold from git repos
    )

    # Filter to only what's not installed yet
    $npmNeeded = @($npmAllPackages | Where-Object {
        $shortName = ($_ -split "/")[-1]
        $npmInstalled -notmatch $shortName
    })
    $npmSkipped = $npmAllPackages.Count - $npmNeeded.Count

    if ($npmNeeded.Count -eq 0) {
        Write-Log "npm: all $($npmAllPackages.Count) packages already installed" "OK"
    } else {
        # Batch install all at once (MUCH faster — single dependency resolution)
        $npmPkgList = $npmNeeded -join " "
        Start-Spinner "npm: installing $($npmNeeded.Count) packages (batch)..."

        $batchResult = Invoke-Npm "install -g $npmPkgList"

        # Check which actually installed
        $npmAfterResult = Invoke-Npm "list -g --depth=0"
        $npmAfter = $npmAfterResult.Output
        $npmOk = 0
        $npmFail = @()
        foreach ($pkg in $npmNeeded) {
            $shortName = ($pkg -split "/")[-1]
            if ($npmAfter -match $shortName) {
                $npmOk++
            } else {
                $npmFail += $pkg
            }
        }

        # Retry failures individually (some may have conflicts in batch)
        if ($npmFail.Count -gt 0) {
            $script:SpinnerSync.Message = "npm: retrying $($npmFail.Count) failed packages..."
            $stillFailed = @()
            foreach ($pkg in $npmFail) {
                $shortName = ($pkg -split "/")[-1]
                $script:SpinnerSync.Message = "npm retry: $shortName"
                $retryResult = Invoke-Npm "install -g $pkg"
                # Check if it installed
                $checkResult = Invoke-Npm "list -g --depth=0"
                if ($checkResult.Output -match $shortName) { $npmOk++ }
                else { $stillFailed += $pkg }
            }
            $npmFail = $stillFailed
        }

        if ($npmFail.Count -gt 0) {
            Stop-Spinner -FinalMessage "npm: $npmOk installed, $($npmFail.Count) failed" -Status "WARN"
            Write-Log "npm failed: $($npmFail -join ', ')" "WARN"
        } else {
            Stop-Spinner -FinalMessage "npm: $npmOk packages installed" -Status "OK"
        }
    }
    if ($npmSkipped -gt 0) { Write-Log "npm: $npmSkipped already installed" "OK" }

} else {
    # Fallback 1: try choco
    Write-Log "npm not found - attempting Node.js install via choco as fallback..." "WARN"
    Install-App "Node.js LTS (choco)" -ChocoId "nodejs-lts"
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    $chocoNodeDir = "C:\Program Files\nodejs"
    $npmFound = (Test-Path "$chocoNodeDir\npm.cmd")

    # Fallback 2: try scoop
    if (-not $npmFound) {
        Write-Log "choco failed - trying scoop..." "WARN"
        Install-App "Node.js LTS (scoop)" -ScoopId "nodejs-lts"
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        $scoopNodeDir = "$env:USERPROFILE\scoop\apps\nodejs-lts\current"
        if (Test-Path "$scoopNodeDir\npm.cmd") {
            $chocoNodeDir = $scoopNodeDir
            $npmFound = $true
        }
    }

    # Fallback 3: direct zip download from nodejs.org (most reliable - no package manager needed)
    if (-not $npmFound) {
        Write-Log "Package managers failed - downloading Node.js directly from nodejs.org..." "WARN"
        Start-Spinner "Downloading Node.js LTS portable..."
        try {
            $ProgressPreference = 'SilentlyContinue'
            # Query nodejs.org index to find latest LTS version dynamically
            $nodeIndex = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -TimeoutSec 15
            $latestLts = $nodeIndex | Where-Object { $_.lts } | Select-Object -First 1
            $nodeVer = $latestLts.version  # e.g. "v22.22.2"

            if ($nodeVer) {
                $script:SpinnerSync.Message = "Downloading Node.js $nodeVer..."
                $nodeZipUrl = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-win-x64.zip"
                $nodeZipPath = Join-Path $env:TEMP "node-lts.zip"
                $nodeExtract = Join-Path $env:TEMP "node-lts-extract"

                Invoke-WebRequest -Uri $nodeZipUrl -OutFile $nodeZipPath -UseBasicParsing -TimeoutSec 120

                $script:SpinnerSync.Message = "Extracting Node.js $nodeVer..."
                if (Test-Path $nodeExtract) { Remove-Item $nodeExtract -Recurse -Force }
                Expand-Archive -Path $nodeZipPath -DestinationPath $nodeExtract -Force

                # Move extracted folder to C:\Program Files\nodejs
                $extractedDir = @(Get-ChildItem $nodeExtract -Directory)[0]
                $targetDir = "C:\Program Files\nodejs"
                if ($extractedDir) {
                    if (Test-Path $targetDir) { Remove-Item $targetDir -Recurse -Force }
                    Move-Item $extractedDir.FullName $targetDir -Force
                    $chocoNodeDir = $targetDir
                    $npmFound = $true
                    Write-Log "Node.js $nodeVer extracted to $targetDir" "OK"
                }

                Remove-Item $nodeZipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $nodeExtract -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Log "Could not determine latest LTS version from nodejs.org" "WARN"
            }
            $ProgressPreference = 'Continue'
        } catch {
            Write-Log "Direct Node.js download failed: $_" "WARN"
            $ProgressPreference = 'Continue'
        }
        if ($script:SpinnerSync.Active) { Stop-Spinner -FinalMessage "Node.js direct download" -Status $(if ($npmFound) { "OK" } else { "ERROR" }) }
    }

    # Fallback 4: try MSI installer as last resort
    if (-not $npmFound) {
        Write-Log "Zip failed - trying MSI installer..." "WARN"
        try {
            $nodeIndex = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing -TimeoutSec 15 -ErrorAction SilentlyContinue
            $latestLts = $nodeIndex | Where-Object { $_.lts } | Select-Object -First 1
            $nodeVer = $latestLts.version
            if ($nodeVer) {
                $msiUrl = "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi"
                $msiPath = Join-Path $env:TEMP "node-lts.msi"
                Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 120
                $r = Invoke-Silent "msiexec" "/i `"$msiPath`" /qn /norestart"
                Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                            [System.Environment]::GetEnvironmentVariable("Path", "User")
                if (Test-Path "C:\Program Files\nodejs\npm.cmd") {
                    $chocoNodeDir = "C:\Program Files\nodejs"
                    $npmFound = $true
                    Write-Log "Node.js $nodeVer installed via MSI" "OK"
                }
            }
        } catch {
            Write-Log "MSI install failed: $_" "WARN"
        }
    }

    # If any fallback worked, set up PATH and install essentials
    if ($npmFound) {
        if ($env:Path -notmatch [regex]::Escape($chocoNodeDir)) { $env:Path = "$chocoNodeDir;$env:Path" }
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($chocoNodeDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$chocoNodeDir", "Machine")
        }
        $npmGlobalDir = "$env:APPDATA\npm"
        if (-not (Test-Path $npmGlobalDir)) { New-Item -ItemType Directory -Path $npmGlobalDir -Force | Out-Null }
        if ($env:Path -notmatch [regex]::Escape($npmGlobalDir)) { $env:Path = "$npmGlobalDir;$env:Path" }
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($npmGlobalDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$npmGlobalDir", "Machine")
        }

        $script:NpmDirect = "$chocoNodeDir\npm.cmd"
        Write-Log "npm: $(& $script:NpmDirect --version 2>$null) at $chocoNodeDir" "OK"
        $essentialNpm = @("typescript", "pnpm", "yarn", "prettier", "eslint", "tldr")
        foreach ($pkg in $essentialNpm) {
            & $script:NpmDirect install -g $pkg 2>&1 | Out-Null
        }
        Write-Log "npm essential packages installed ($($essentialNpm.Count) via fallback)" "OK"
    } else {
        Write-Log "Node.js/npm could not be installed by any method (winget/choco/scoop/zip/msi) - requires manual install" "ERROR"
    }
}

# --- GitHub CLI (needed for Copilot CLI auth) ---
Install-App "GitHub CLI" -WingetId "GitHub.cli" -ChocoId "gh" -ScoopId "gh"

# --- NVM for Windows (Node Version Manager) ---
Write-Log "Installing NVM for Windows..."
Install-App "NVM for Windows" -WingetId "CoreyButler.NVMforWindows" -ChocoId "nvm"

# --- Alternative JS/TS Runtimes ---
Install-App "Deno"                  -WingetId "DenoLand.Deno"                  -ChocoId "deno"           -ScoopId "deno"
Install-App "Bun"                   -WingetId "Oven-sh.Bun"                    -ChocoId "bun"            -ScoopId "bun"

# ============================================================================
# WSL Configuration
# ============================================================================
Write-SubStep "WSL Configuration"

# Set WSL memory limit to 16GB and configure sensible defaults
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfig = @"
[wsl2]
memory=32GB
processors=26
swap=4GB
localhostForwarding=true
nestedVirtualization=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
"@
Set-Content -Path $wslConfigPath -Value $wslConfig -Encoding UTF8
Write-Log "WSL configured: 32GB RAM, 26 CPUs, 4GB swap, nested virt, auto memory reclaim" "OK"

# ============================================================================
# Hacker / Security / Pentesting Tools
# ============================================================================
Write-SubStep "Dev & Security Tools"

# --- Network & Recon ---
Install-App "Nmap"                  -WingetId "Insecure.Nmap"                  -ChocoId "nmap"
Install-App "Wireshark"             -WingetId "WiresharkFoundation.Wireshark"  -ChocoId "wireshark"
Install-App "Npcap"                 -WingetId "Insecure.Npcap"                 -ChocoId "npcap"

# --- Reverse Engineering ---
# Ghidra - not on winget (NSA declined); download from GitHub releases directly
$ghidraInstalled = (Test-Path "C:\apps\Ghidra") -or
                   (Test-Path "C:\ProgramData\chocolatey\lib\ghidra") -or
                   (Test-Path "C:\ghidra")
if ($ghidraInstalled) {
    Write-Log "Ghidra already installed" "OK"
} else {
    $ghidraUrl = Get-GitHubReleaseUrl -Repo "NationalSecurityAgency/ghidra" -Pattern "ghidra_[\d.]+_PUBLIC_\d+\.zip$"
    if ($ghidraUrl) {
        Install-PortableApp -Name "Ghidra" -Url $ghidraUrl
    } else {
        Write-Log "Ghidra - could not resolve GitHub download URL, trying choco" "WARN"
        Install-App "Ghidra" -ChocoId "ghidra"
    }
}
Install-App "x64dbg"                -WingetId "x64dbg.x64dbg"                 -ChocoId "x64dbg.portable"

# --- Binary / Hex ---
Install-App "HxD Hex Editor"        -WingetId "MHNexus.HxD"                   -ChocoId "hxd"
Install-App "ImHex"                 -WingetId "WerWolv.ImHex"                  -ChocoId "imhex"

# --- Crypto / Hashing ---
Install-App "HashCheck"             -WingetId "idrassi.HashCheckShellExtension" -ChocoId "hashcheck"

# --- HTTP / API ---
Install-App "Postman"               -WingetId "Postman.Postman"                -ChocoId "postman"
Install-App "curl"                  -WingetId "cURL.cURL"                      -ScoopId "curl"

# --- Terminals & Shells ---
# ncat comes bundled with nmap - find it or install standalone
$ncatExe = $null
$ncatSearchPaths = @(
    "$env:ProgramFiles\Nmap\ncat.exe",
    "${env:ProgramFiles(x86)}\Nmap\ncat.exe",
    "C:\bin\ncat.exe"
)
foreach ($p in $ncatSearchPaths) {
    if (Test-Path $p) { $ncatExe = $p; break }
}
if (-not $ncatExe) {
    $ncatCmd = Get-Command ncat -ErrorAction SilentlyContinue
    if ($ncatCmd) { $ncatExe = $ncatCmd.Source }
}

if ($ncatExe) {
    Write-Log "ncat available at $ncatExe" "OK"
    # Ensure Nmap dir is on PATH so ncat is callable directly
    $ncatDir = Split-Path $ncatExe
    if ($env:Path -notmatch [regex]::Escape($ncatDir)) {
        $env:Path = "$env:Path;$ncatDir"
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($ncatDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$ncatDir", "Machine")
        }
    }
} else {
    # Nmap not installed or ncat missing - download ncat standalone from nmap.org
    Write-Log "ncat not found - downloading standalone from nmap.org..." "WARN"
    $ncatUrl = "https://nmap.org/dist/ncat-portable-5.59BETA1.zip"
    try {
        $ncatZip = Join-Path $env:TEMP "ncat-portable.zip"
        Invoke-WebRequest -Uri $ncatUrl -OutFile $ncatZip -UseBasicParsing -TimeoutSec 30
        $ncatExtract = Join-Path $env:TEMP "ncat-extract"
        if (Test-Path $ncatExtract) { Remove-Item $ncatExtract -Recurse -Force }
        Expand-Archive -Path $ncatZip -DestinationPath $ncatExtract -Force
        $ncatFound = Get-ChildItem $ncatExtract -Recurse -Filter "ncat.exe" | Select-Object -First 1
        if ($ncatFound) {
            Copy-Item $ncatFound.FullName -Destination "C:\bin\ncat.exe" -Force
            Write-Log "ncat standalone installed to C:\bin" "OK"
        }
        Remove-Item $ncatZip, $ncatExtract -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        # Last resort: try installing nmap via winget (includes ncat)
        Install-App "Nmap (for ncat)" -WingetId "Insecure.Nmap" -ChocoId "nmap"
    }
}

# --- Forensics / Sysinternals ---
Write-Log "Installing Sysinternals Suite..."
Install-App "Sysinternals Suite"    -WingetId "Microsoft.Sysinternals.Suite"   -ChocoId "sysinternals"

# --- Dev CLI tools ---
Install-App "jq"                    -WingetId "jqlang.jq"                      -ChocoId "jq"             -ScoopId "jq"
Install-App "ripgrep"               -WingetId "BurntSushi.ripgrep.MSVC"        -ChocoId "ripgrep"        -ScoopId "ripgrep"
Install-App "fzf"                   -WingetId "junegunn.fzf"                   -ChocoId "fzf"            -ScoopId "fzf"
Install-App "bat"                   -WingetId "sharkdp.bat"                    -ChocoId "bat"            -ScoopId "bat"
Install-App "fd"                    -WingetId "sharkdp.fd"                     -ChocoId "fd"             -ScoopId "fd"
Install-App "lazygit"               -WingetId "JesseDuffield.lazygit"          -ChocoId "lazygit"        -ScoopId "lazygit"
Install-App "delta (git diff)"      -WingetId "dandavison.delta"               -ChocoId "delta"          -ScoopId "delta"
Install-App "httpie"                -WingetId "HTTPie.HTTPie"                   -ChocoId "httpie"
Install-App "OpenSSH"               -WingetId "Microsoft.OpenSSH.Beta"         -ChocoId "openssh"

# ============================================================================
# Java / JRE / JDK Tooling
# ============================================================================
Write-SubStep "Java Tooling"

Install-App "OpenJDK 21"            -WingetId "EclipseAdoptium.Temurin.21.JDK" -ChocoId "temurin21"
Install-App "OpenJDK 17 (LTS)"      -WingetId "EclipseAdoptium.Temurin.17.JDK" -ChocoId "temurin17"
Install-App "Maven"                 -WingetId "Apache.Maven"                    -ChocoId "maven"          -ScoopId "maven"
Install-App "Gradle"                -WingetId "Gradle.Gradle"                   -ChocoId "gradle"         -ScoopId "gradle"

# Set JAVA_HOME to JDK 21
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
$javaExe = Get-Command java -ErrorAction SilentlyContinue
if ($javaExe) {
    $javaHome = (Get-Item $javaExe.Source).Directory.Parent.FullName
    [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
    $env:JAVA_HOME = $javaHome
    Write-Log "JAVA_HOME set to $javaHome" "OK"
}

# Install useful Java tools
Install-App "JBang"                 -WingetId "jbangdev.jbang"                  -ChocoId "jbang"          -ScoopId "jbang"
Install-App "VisualVM"              -WingetId "Oracle.VisualVM"                 -ChocoId "visualvm"

# SDKMAN alternative for Windows - Jabba (Java version manager)
# jabba removed - repo is archived/dead, use SDKMAN via WSL or manual JDK management

Write-Log "Java tooling installed (JDK 17+21, Maven, Gradle, JBang, VisualVM)" "OK"

# ============================================================================
# OpenSSH - Full Configuration
# ============================================================================
Write-SubStep "OpenSSH Configuration"

Install-App "OpenSSH"               -WingetId "Microsoft.OpenSSH.Beta"         -ChocoId "openssh"

# Enable OpenSSH server + client features
try { Add-WindowsCapability -Online -Name "OpenSSH.Client~~~~0.0.1.0" -ErrorAction Stop 3>$null | Out-Null } catch { Write-Log "OpenSSH Client capability: $_" "WARN" }
try { Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction Stop 3>$null | Out-Null } catch { Write-Log "OpenSSH Server capability: $_" "WARN" }

# Start SSH Agent (key manager) - this is safe, it's NOT a server
Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name ssh-agent -ErrorAction SilentlyContinue
Write-Log "SSH Agent started and set to auto-start" "OK"

# DISABLE sshd server - installed but NOT listening
Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
Set-Service  -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
Write-Log "SSH Server (sshd) installed but DISABLED - enable manually if needed" "OK"

# Create .ssh directory if not present
$sshDir = Join-Path $env:USERPROFILE ".ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    icacls $sshDir /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" >$null 2>&1
}

# Generate ED25519 SSH key if none exists
$sshKey = Join-Path $sshDir "id_ed25519"
if (-not (Test-Path $sshKey)) {
    ssh-keygen -t ed25519 -C "$env:USERNAME@$env:COMPUTERNAME" -f $sshKey -N "" 2>&1 | Out-Null
    Write-Log "ED25519 SSH key generated at $sshKey" "OK"
} else {
    Write-Log "SSH key already exists at $sshKey" "OK"
}

# Set default SSH config
$sshConfig = Join-Path $sshDir "config"
if (-not (Test-Path $sshConfig)) {
    $sshConfigContent = @"
Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
"@
    Set-Content $sshConfig -Value $sshConfigContent -Encoding UTF8
    Write-Log "SSH config created with GitHub defaults" "OK"
}

Write-Log "OpenSSH fully configured" "OK"

# ============================================================================
# CUDA Toolkit
# ============================================================================
Write-SubStep "CUDA Toolkit"

Install-App "CUDA Toolkit"          -WingetId "Nvidia.CUDA"                     -ChocoId "cuda"

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Set CUDA_PATH if not already set
$cudaPaths = @(
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6",
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.5",
    "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.4"
)
$cudaRoot = $null
foreach ($cp in $cudaPaths) {
    if (Test-Path $cp) { $cudaRoot = $cp; break }
}
# Fallback: find any CUDA install
if (-not $cudaRoot) {
    $cudaBase = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    if (Test-Path $cudaBase) {
        $cudaRoot = Get-ChildItem $cudaBase -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
}

if ($cudaRoot) {
    [System.Environment]::SetEnvironmentVariable("CUDA_PATH", $cudaRoot, "Machine")
    $env:CUDA_PATH = $cudaRoot

    $cudaBin = Join-Path $cudaRoot "bin"
    $cudaLibnvvp = Join-Path $cudaRoot "libnvvp"
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    foreach ($cp in @($cudaBin, $cudaLibnvvp)) {
        if ((Test-Path $cp) -and $machinePath -notmatch [regex]::Escape($cp)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$cp", "Machine")
            $machinePath = "$machinePath;$cp"
        }
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    Write-Log "CUDA_PATH set to $cudaRoot, nvcc in PATH" "OK"
} else {
    Write-Log "CUDA install path not found - may need reboot or manual CUDA install" "WARN"
}

# cuDNN requires NVIDIA developer login - cannot be automated
# Install manually from: https://developer.nvidia.com/cudnn
Write-Log "CUDA toolkit configured" "OK"

# ============================================================================
# SQL Server Tooling
# ============================================================================
Write-SubStep "SQL Server Tooling"

Install-App "SQL Server Management Studio" -WingetId "Microsoft.SQLServerManagementStudio" -ChocoId "sql-server-management-studio"
Install-App "Azure Data Studio"    -WingetId "Microsoft.AzureDataStudio"       -ChocoId "azure-data-studio"
# sqlcmd removed - bundled with SSMS already

# Install SQL Server PowerShell module (with timeout)
if (Get-Module -ListAvailable -Name SqlServer -ErrorAction SilentlyContinue) {
    Write-Log "SqlServer PowerShell module already installed" "OK"
} else {
    $sqlModJob = Start-Job { Install-Module -Name SqlServer -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue }
    $sqlModJob | Wait-Job -Timeout 60 | Out-Null
    if ($sqlModJob.State -ne "Completed") { Stop-Job $sqlModJob -ErrorAction SilentlyContinue }
    Remove-Job $sqlModJob -Force -ErrorAction SilentlyContinue
    Write-Log "SqlServer PowerShell module installed" "OK"
}

Write-Log "SQL Server tooling installed (SSMS, Azure Data Studio)" "OK"

# ============================================================================
# OpenSSL CLI Tooling
# ============================================================================
Write-SubStep "OpenSSL CLI"

# Install standalone OpenSSL (not just vcpkg library)
Install-App "OpenSSL"              -WingetId "ShiningLight.OpenSSL"             -ChocoId "openssl"

# Add OpenSSL to PATH
$opensslPaths = @(
    "C:\Program Files\OpenSSL-Win64\bin",
    "C:\Program Files\OpenSSL\bin"
)
foreach ($osp in $opensslPaths) {
    if (Test-Path $osp) {
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($machinePath -notmatch [regex]::Escape($osp)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$osp", "Machine")
            $env:Path = "$env:Path;$osp"
        }
        # Set OPENSSL_DIR and OPENSSL_CONF for Rust/C builds that need it
        $opensslDir = Split-Path $osp
        [System.Environment]::SetEnvironmentVariable("OPENSSL_DIR", $opensslDir, "Machine")
        [System.Environment]::SetEnvironmentVariable("OPENSSL_CONF", (Join-Path $opensslDir "bin\openssl.cfg"), "Machine")
        $env:OPENSSL_DIR = $opensslDir
        Write-Log "OpenSSL in PATH, OPENSSL_DIR=$opensslDir" "OK"
        break
    }
}

Write-Log "OpenSSL CLI configured" "OK"

# ============================================================================
# Document Processing (Pandoc, qpdf, LaTeX)
# ============================================================================
Write-SubStep "Document Processing"

Install-App "Pandoc"               -WingetId "JohnMacFarlane.Pandoc"            -ChocoId "pandoc"         -ScoopId "pandoc"
# Pandoc Crossref - not reliably on choco/scoop; download from GitHub directly
if ((Get-Command pandoc-crossref -ErrorAction SilentlyContinue) -or (Test-Path "C:\bin\pandoc-crossref.exe")) {
    Write-Log "Pandoc Crossref already installed" "OK"
} else {
    $crossrefUrl = Get-GitHubReleaseUrl -Repo "lierdakil/pandoc-crossref" -Pattern "pandoc-crossref-Windows-X64\.7z$"
    if ($crossrefUrl) {
        Install-PortableBin -Name "pandoc-crossref" -Url $crossrefUrl -ExeName "pandoc-crossref.exe" -ArchiveType "7z"
    } else {
        Write-Log "Pandoc Crossref - could not resolve GitHub URL, trying choco" "WARN"
        Install-App "Pandoc Crossref" -ChocoId "pandoc-crossref" -ScoopId "pandoc-crossref"
    }
}

# qpdf (PDF manipulation - merge, split, encrypt, decrypt, linearize)
Install-App "qpdf"                 -WingetId "QPDF.QPDF"                       -ChocoId "qpdf"           -ScoopId "qpdf"

# Add qpdf to PATH if installed via choco
$qpdfPath = "C:\Program Files\qpdf\bin"
if (Test-Path $qpdfPath) {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notmatch [regex]::Escape($qpdfPath)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$qpdfPath", "Machine")
        $env:Path = "$env:Path;$qpdfPath"
    }
}

# MiKTeX (LaTeX distribution - needed for pandoc PDF output)
Install-App "MiKTeX"               -WingetId "MiKTeX.MiKTeX"                   -ChocoId "miktex"

# poppler-utils (pdftotext, pdfimages, etc.) - via C:\bin
$popplerUrl = Get-GitHubReleaseUrl -Repo "oschwartz10612/poppler-windows" -Pattern "\.zip$"
if ($popplerUrl) {
    Install-PortableBin -Name "pdftotext" -Url $popplerUrl -ExeName "pdftotext.exe" -SubPath "Library\bin"
    Install-PortableBin -Name "pdfinfo"   -Url $popplerUrl -ExeName "pdfinfo.exe"   -SubPath "Library\bin"
} else {
    Write-Log "poppler-utils - could not resolve download URL" "WARN"
}

Write-Log "Document processing installed (Pandoc, qpdf, MiKTeX, poppler-utils)" "OK"

# TeX Live removed - MiKTeX already installed (serves same purpose, lighter)

# ============================================================================
# Android SDK (standalone, API 32+)
# ============================================================================
Write-SubStep "Android SDK"

$androidSdkRoot = "C:\android-sdk"

# Preflight: check if all SDK packages are already installed
$sdkPackagesList = @(
    "platform-tools",
    "platforms\android-32",
    "platforms\android-33",
    "platforms\android-34",
    "build-tools\32.0.0",
    "build-tools\34.0.0",
    "extras\google\usb_driver",
    "emulator",
    "ndk\27.0.12077973",
    "cmake\3.22.1"
)
$sdkAllPresent = $true
if (Test-Path $androidSdkRoot) {
    foreach ($pkgPath in $sdkPackagesList) {
        if (-not (Test-Path (Join-Path $androidSdkRoot $pkgPath))) {
            $sdkAllPresent = $false
            break
        }
    }
} else {
    $sdkAllPresent = $false
}

if ($sdkAllPresent) {
    Write-Log "Android SDK fully installed (all $($sdkPackagesList.Count) packages present)" "OK"
    # Still ensure env vars are set
    [System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $androidSdkRoot, "Machine")
    [System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $androidSdkRoot, "Machine")
    $env:ANDROID_HOME = $androidSdkRoot
    $env:ANDROID_SDK_ROOT = $androidSdkRoot
} else {

if (-not (Test-Path $androidSdkRoot)) { New-Item -ItemType Directory -Path $androidSdkRoot -Force | Out-Null }

# Set ANDROID_HOME / ANDROID_SDK_ROOT
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME", $androidSdkRoot, "Machine")
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $androidSdkRoot, "Machine")
$env:ANDROID_HOME = $androidSdkRoot
$env:ANDROID_SDK_ROOT = $androidSdkRoot

# Collect background Android cmdline-tools download (launched at module start)
$cmdlineToolsDir = Join-Path $androidSdkRoot "cmdline-tools"
if (-not (Test-Path "$cmdlineToolsDir\latest\bin\sdkmanager.bat")) {
    if ($bgAndroidJob) {
        Write-Log "Waiting for background Android cmdline-tools download..." "INFO"
        $bgAndroidJob | Wait-Job | Out-Null
        $bgResult = Receive-Job $bgAndroidJob
        Remove-Job $bgAndroidJob -Force -ErrorAction SilentlyContinue
        if ($bgResult.ok -and (Test-Path "$cmdlineToolsDir\latest\bin\sdkmanager.bat")) {
            Write-Log "Android command-line tools installed (from background)" "OK"
        } else {
            Write-Log "Background download failed ($($bgResult.error)) - retrying..." "WARN"
            # Retry in foreground
            try {
                $cmdlineZip = Join-Path $env:TEMP "android-cmdline-tools.zip"
                $cmdlineUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
                Invoke-WebRequest -Uri $cmdlineUrl -OutFile $cmdlineZip -UseBasicParsing -TimeoutSec 300
                $extractDir = Join-Path $env:TEMP "android-cmdline-extract"
                if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
                Expand-Archive -Path $cmdlineZip -DestinationPath $extractDir -Force
                $latestDir = Join-Path $cmdlineToolsDir "latest"
                if (-not (Test-Path $cmdlineToolsDir)) { New-Item -ItemType Directory -Path $cmdlineToolsDir -Force | Out-Null }
                if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force }
                Move-Item (Join-Path $extractDir "cmdline-tools") $latestDir -Force
                Remove-Item $cmdlineZip, $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Android command-line tools installed (retry)" "OK"
            } catch {
                Write-Log "Android command-line tools download failed: $_" "ERROR"
            }
        }
    }
}

# Add SDK tools to PATH
$sdkPaths = @(
    "$androidSdkRoot\cmdline-tools\latest\bin",
    "$androidSdkRoot\platform-tools",
    "$androidSdkRoot\build-tools\32.0.0",
    "$androidSdkRoot\emulator"
)
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
foreach ($sp in $sdkPaths) {
    if ($machinePath -notmatch [regex]::Escape($sp)) {
        $machinePath = "$machinePath;$sp"
    }
}
[System.Environment]::SetEnvironmentVariable("Path", $machinePath, "Machine")
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Install SDK packages via sdkmanager
$sdkmanager = Join-Path $androidSdkRoot "cmdline-tools\latest\bin\sdkmanager.bat"
if (Test-Path $sdkmanager) {
    # Accept all licenses by writing hash files directly (same as CI systems)
    # This avoids the slow sdkmanager --licenses which fetches updates over the network
    $licensesDir = Join-Path $androidSdkRoot "licenses"
    if (-not (Test-Path $licensesDir)) { New-Item -ItemType Directory -Path $licensesDir -Force | Out-Null }

    $licenseHashes = @{
        # Standard Android SDK license
        "android-sdk-license"         = "`n24333f8a63b6825ea9c5514f83c2829b004d1fee"
        # Android SDK Preview license
        "android-sdk-preview-license" = "`n84831b9409646a918e30573bab4c9c91346d8abd"
        # Google APIs Intel x86 Atom System Image license
        "intel-android-extra-license" = "`nd975f751698a77b662f1254ddbeed3901e976f5a"
        # Android SDK ARM DBTL license
        "android-sdk-arm-dbt-license" = "`n859f317696f67ef3d7f30a50a5560e7834b43903"
        # Google GDK license
        "google-gdk-license"          = "`n33b6a2b64607f11b759f320ef9dff4ae5c47d97a"
        # mips Android DBTL license
        "mips-android-sysimage-license" = "`ne9acab5b5fbb560a72cfaecbe88acf4457f3ed00"
    }

    $licensesWritten = 0
    foreach ($name in $licenseHashes.Keys) {
        $licFile = Join-Path $licensesDir $name
        if (-not (Test-Path $licFile)) {
            Set-Content -Path $licFile -Value $licenseHashes[$name] -Encoding ASCII -NoNewline
            $licensesWritten++
        }
    }
    if ($licensesWritten -gt 0) {
        Write-Log "Android SDK: $licensesWritten license files written" "OK"
    } else {
        Write-Log "Android SDK licenses already accepted" "OK"
    }

    # Direct download map: bypass sdkmanager for speed (just zips from dl.google.com)
    # sdkmanager starts a JVM + resolves XML manifests for each call — direct HTTP is 10x faster
    # Try to resolve URLs dynamically from the SDK repository manifest
    $sdkDirectDownloads = @()
    $sdkBaseUrl = "https://dl.google.com/android/repository/"
    $sdkDirectFallback = @(
        @{ pkg = "platform-tools";           dir = "platform-tools";              url = "${sdkBaseUrl}platform-tools-latest-windows.zip" }
        @{ pkg = "platforms;android-32";     dir = "platforms\android-32";        url = "${sdkBaseUrl}platform-32_r01.zip";               inner = "android-12" }
        @{ pkg = "platforms;android-33";     dir = "platforms\android-33";        url = "${sdkBaseUrl}platform-33-ext3_r03.zip";          inner = "android-13" }
        @{ pkg = "platforms;android-34";     dir = "platforms\android-34";        url = "${sdkBaseUrl}platform-34-ext7_r03.zip";          inner = "android-14" }
        @{ pkg = "build-tools;32.0.0";      dir = "build-tools\32.0.0";         url = "${sdkBaseUrl}210b77e4bc623bd4cdda4dae790048f227972bd2.build-tools_r32-windows.zip" }
        @{ pkg = "build-tools;34.0.0";      dir = "build-tools\34.0.0";         url = "${sdkBaseUrl}build-tools_r34-windows.zip" }
    )

    # Try dynamic URL resolution from repository XML (most reliable, always up-to-date)
    # Multiple manifest URLs as fallback chain
    $manifestUrls = @(
        "${sdkBaseUrl}repository2-3.xml",
        "${sdkBaseUrl}repository2-2.xml",
        "${sdkBaseUrl}repository2-1.xml",
        "https://dl-ssl.google.com/android/repository/repository2-3.xml"
    )
    $repoXml = $null
    foreach ($manifestUrl in $manifestUrls) {
        try {
            $repoXml = [xml](Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 30).Content
            if ($repoXml) {
                Write-Log "SDK manifest fetched from $manifestUrl" "OK"
                break
            }
        } catch {}
    }

    if ($repoXml) {
        foreach ($entry in $sdkDirectFallback) {
            $pkgPath = $entry.pkg
            $resolvedUrl = $null
            $nodes = $repoXml.SelectNodes("//remotePackage[@path='$pkgPath']")
            foreach ($node in $nodes) {
                if ($node.SelectSingleNode("obsolete")) { continue }
                $archives = $node.SelectNodes("archives/archive")
                foreach ($archive in $archives) {
                    $hostOs = $archive.SelectSingleNode("host-os")
                    if (-not $hostOs -or $hostOs.InnerText -eq "windows") {
                        $urlNode = $archive.SelectSingleNode("complete/url")
                        if ($urlNode) { $resolvedUrl = $sdkBaseUrl + $urlNode.InnerText; break }
                    }
                }
                if ($resolvedUrl) { break }
            }
            if ($resolvedUrl) {
                $innerVal = if ($entry.ContainsKey("inner")) { $entry.inner } else { $null }
                $sdkDirectDownloads += @{ pkg = $entry.pkg; dir = $entry.dir; url = $resolvedUrl; inner = $innerVal }
            } else {
                $sdkDirectDownloads += $entry
            }
        }
        Write-Log "SDK URLs resolved from manifest" "OK"
    } else {
        Write-Log "All SDK manifests unavailable, using hardcoded URLs" "WARN"
        $sdkDirectDownloads = $sdkDirectFallback
    }

    # Packages that need sdkmanager (complex installs with native components)
    # Also add direct download fallback URLs resolved from manifest for these
    $sdkMgrDirectFallback = @{}
    if ($repoXml) {
        foreach ($pkg in @("emulator", "ndk;27.0.12077973", "cmake;3.22.1")) {
            $nodes = $repoXml.SelectNodes("//remotePackage[@path='$pkg']")
            foreach ($node in $nodes) {
                if ($node.SelectSingleNode("obsolete")) { continue }
                $archives = $node.SelectNodes("archives/archive")
                foreach ($archive in $archives) {
                    $hostOs = $archive.SelectSingleNode("host-os")
                    if (-not $hostOs -or $hostOs.InnerText -eq "windows") {
                        $urlNode = $archive.SelectSingleNode("complete/url")
                        if ($urlNode) { $sdkMgrDirectFallback[$pkg] = $sdkBaseUrl + $urlNode.InnerText; break }
                    }
                }
                if ($sdkMgrDirectFallback.ContainsKey($pkg)) { break }
            }
        }
    }

    # usb_driver handled separately — it's optional (only for physical USB device debugging)
    # and has a 3-level directory structure that confuses the generic extract logic
    $usbDriverDir = Join-Path $androidSdkRoot "extras\google\usb_driver"
    if (-not (Test-Path $usbDriverDir)) {
        # Try direct download from manifest
        $usbDriverUrl = $null
        if ($sdkMgrDirectFallback.ContainsKey("extras;google;usb_driver")) {
            $usbDriverUrl = $sdkMgrDirectFallback["extras;google;usb_driver"]
        }
        if (-not $usbDriverUrl) {
            $usbDriverUrl = "${sdkBaseUrl}usb_driver_r13-windows.zip"  # known stable fallback
        }
        try {
            $usbZip = Join-Path $env:TEMP "sdk_usb_driver.zip"
            $usbExtract = Join-Path $env:TEMP "sdk_usb_extract"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $usbDriverUrl -OutFile $usbZip -UseBasicParsing -TimeoutSec 60
            if (Test-Path $usbExtract) { Remove-Item $usbExtract -Recurse -Force }
            Expand-Archive -Path $usbZip -DestinationPath $usbExtract -Force
            # Create parent dirs and move
            $extrasGoogle = Join-Path $androidSdkRoot "extras\google"
            if (-not (Test-Path $extrasGoogle)) { New-Item -ItemType Directory -Path $extrasGoogle -Force | Out-Null }
            $innerDir = @(Get-ChildItem $usbExtract -Directory)[0]
            if ($innerDir) { Move-Item $innerDir.FullName $usbDriverDir -Force }
            Remove-Item $usbZip, $usbExtract -Recurse -Force -ErrorAction SilentlyContinue
            $ProgressPreference = 'Continue'
            if (Test-Path $usbDriverDir) { Write-Log "SDK: usb_driver installed" "OK"; $sdkInstalled++ }
            else { Write-Log "SDK: usb_driver extract failed (optional, non-critical)" "WARN" }
        } catch {
            $ProgressPreference = 'Continue'
            Write-Log "SDK: usb_driver download failed (optional, non-critical)" "WARN"
        }
    } else {
        $sdkSkipped++
    }

    $sdkManagerOnly = @(
        "emulator",
        "ndk;27.0.12077973",
        "cmake;3.22.1"
    )

    $allPkgs = @($sdkDirectDownloads | ForEach-Object { $_.pkg }) + $sdkManagerOnly
    $sdkSkipped = 0
    $sdkInstalled = 0
    $sdkFailed = 0

    # Count already installed
    foreach ($pkg in $allPkgs) {
        $pkgDir = Join-Path $androidSdkRoot ($pkg -replace ";", "\")
        if (Test-Path $pkgDir) { $sdkSkipped++ }
    }
    if ($sdkSkipped -eq $allPkgs.Count) {
        Write-Log "Android SDK: all $($allPkgs.Count) packages already installed" "OK"
    } else {
        if ($sdkSkipped -gt 0) { Write-Log "Android SDK: $sdkSkipped/$($allPkgs.Count) packages already installed" "OK" }
        Start-Spinner "Android SDK: downloading packages in parallel..."

        # Filter to only what needs installing
        $directNeeded = @($sdkDirectDownloads | Where-Object {
            -not (Test-Path (Join-Path $androidSdkRoot $_.dir))
        })
        $sdkMgrNeeded = @($sdkManagerOnly | Where-Object {
            -not (Test-Path (Join-Path $androidSdkRoot ($_ -replace ";", "\")))
        })

        # === PARALLEL Phase 1: Launch all direct downloads + sdkmanager simultaneously ===
        $jobs = @()

        # Launch each direct download as a background job
        foreach ($entry in $directNeeded) {
            $jobEntry = $entry  # capture for closure
            $jobSdkRoot = $androidSdkRoot
            $jobs += Start-Job -ScriptBlock {
                param($e, $sdkRoot)
                $ProgressPreference = 'SilentlyContinue'
                $pkgDir = Join-Path $sdkRoot $e.dir
                $pkgName = ($e.pkg -split ";")[-1]
                $zipPath = Join-Path $env:TEMP "sdk_$($pkgName).zip"
                $extractDir = Join-Path $env:TEMP "sdk_extract_$pkgName"
                try {
                    Invoke-WebRequest -Uri $e.url -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
                    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
                    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

                    $parentDir = Split-Path $pkgDir
                    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

                    $eInner = if ($e.ContainsKey("inner")) { $e.inner } else { $null }
                    if ($eInner) {
                        $innerDir = Join-Path $extractDir $eInner
                        if (Test-Path $innerDir) {
                            Move-Item $innerDir $pkgDir -Force
                        } else {
                            $firstSub = @(Get-ChildItem $extractDir -Directory)[0]
                            if ($firstSub) { Move-Item $firstSub.FullName $pkgDir -Force }
                        }
                    } else {
                        $firstSub = @(Get-ChildItem $extractDir -Directory)[0]
                        if ($firstSub) { Move-Item $firstSub.FullName $pkgDir -Force }
                        else { Move-Item $extractDir $pkgDir -Force }
                    }

                    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                    return @{ name = $pkgName; ok = (Test-Path $pkgDir) }
                } catch {
                    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                    return @{ name = $pkgName; ok = $false; error = $_.ToString() }
                }
            } -ArgumentList $jobEntry, $jobSdkRoot
        }

        # Launch sdkmanager in a separate process (not Start-Job — avoids console/Wait issues)
        $sdkMgrProc = $null
        if ($sdkMgrNeeded.Count -gt 0) {
            $yesFile = Join-Path $env:TEMP "sdk-yes-parallel.txt"
            "y`ny`ny`ny`ny`ny`ny`ny`ny`ny`n" | Set-Content $yesFile -Encoding ASCII
            $pkgArgs = ($sdkMgrNeeded | ForEach-Object { "`"$_`"" }) -join " "
            $sdkMgrPsi = New-Object System.Diagnostics.ProcessStartInfo
            $sdkMgrPsi.FileName = "cmd.exe"
            $sdkMgrPsi.Arguments = "/c `"type `"$yesFile`" | `"$sdkmanager`" --sdk_root=`"$androidSdkRoot`" $pkgArgs`""
            $sdkMgrPsi.UseShellExecute = $false
            $sdkMgrPsi.CreateNoWindow = $true
            $sdkMgrPsi.RedirectStandardOutput = $false
            $sdkMgrPsi.RedirectStandardError = $false
            $sdkMgrProc = [System.Diagnostics.Process]::Start($sdkMgrPsi)
        }

        # Build name map for spinner status display
        $jobNames = @{}
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            $jobNames[$jobs[$i].Id] = ($directNeeded[$i].pkg -split ";")[-1]
        }
        $sdkMgrNames = ($sdkMgrNeeded | ForEach-Object { ($_ -split ";")[-1] }) -join "+"

        # Poll ALL tasks (download jobs + sdkmanager process) with live spinner
        # No artificial deadline — just wait until everything finishes
        $allDone = $false
        while (-not $allDone) {
            # Check direct download jobs
            $jobsDone = @($jobs | Where-Object { $_.State -ne "Running" }).Count
            $jobsRunning = @($jobs | Where-Object { $_.State -eq "Running" })
            $runningNames = ($jobsRunning | ForEach-Object { $jobNames[$_.Id] }) -join ", "

            # Check sdkmanager process
            $sdkMgrStatus = ""
            if ($sdkMgrProc) {
                if ($sdkMgrProc.HasExited) {
                    $sdkMgrStatus = " | sdkmanager: done"
                } else {
                    $mgrDone = @($sdkMgrNeeded | Where-Object { Test-Path (Join-Path $androidSdkRoot ($_ -replace ";", "\")) })
                    $mgrPending = @($sdkMgrNeeded | Where-Object { -not (Test-Path (Join-Path $androidSdkRoot ($_ -replace ";", "\"))) })
                    $mgrPendingNames = ($mgrPending | ForEach-Object { ($_ -split ";")[-1] }) -join ", "
                    $sdkMgrStatus = " | sdkmanager $($mgrDone.Count)/$($sdkMgrNeeded.Count): $mgrPendingNames"
                }
            }

            if ($jobsRunning.Count -gt 0) {
                $script:SpinnerSync.Message = "SDK downloads $jobsDone/$($jobs.Count): $runningNames$sdkMgrStatus"
            } elseif ($sdkMgrProc -and -not $sdkMgrProc.HasExited) {
                $mgrDone = @($sdkMgrNeeded | Where-Object { Test-Path (Join-Path $androidSdkRoot ($_ -replace ";", "\")) })
                $mgrPending = @($sdkMgrNeeded | Where-Object { -not (Test-Path (Join-Path $androidSdkRoot ($_ -replace ";", "\"))) })
                $mgrPendingNames = ($mgrPending | ForEach-Object { ($_ -split ";")[-1] }) -join ", "
                $script:SpinnerSync.Message = "SDK: waiting for sdkmanager $($mgrDone.Count)/$($sdkMgrNeeded.Count): $mgrPendingNames"
            }

            # Check if everything is done
            $jobsAllDone = $jobsRunning.Count -eq 0
            $sdkMgrDone = (-not $sdkMgrProc) -or $sdkMgrProc.HasExited
            if ($jobsAllDone -and $sdkMgrDone) { $allDone = $true; break }

            Start-Sleep -Seconds 2
        }

        # Collect direct download results, track failures for sdkmanager fallback
        $directFailed = @()
        foreach ($job in $jobs) {
            $jobName = $jobNames[$job.Id]
            if ($job.State -eq "Completed") {
                $result = Receive-Job $job
                if ($result.ok) {
                    Write-Log "SDK: $($result.name) downloaded" "OK"
                    $sdkInstalled++
                } else {
                    Write-Log "SDK: $($result.name) download failed - will retry via sdkmanager" "WARN"
                    # Find the matching package spec for sdkmanager retry
                    $matchEntry = $directNeeded | Where-Object { (($_.pkg -split ";")[-1]) -eq $result.name }
                    if ($matchEntry) { $directFailed += $matchEntry.pkg }
                }
            } else {
                Stop-Job $job -ErrorAction SilentlyContinue
                Write-Log "SDK: $jobName failed (state: $($job.State)) - will retry via sdkmanager" "WARN"
                $matchEntry = $directNeeded | Where-Object { (($_.pkg -split ";")[-1]) -eq $jobName }
                if ($matchEntry) { $directFailed += $matchEntry.pkg }
            }
            Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        # Fallback: retry failed direct downloads via sdkmanager individually
        if ($directFailed.Count -gt 0 -and (Test-Path $sdkmanager)) {
            $failNames = ($directFailed | ForEach-Object { ($_ -split ";")[-1] }) -join ", "
            Write-Log "Retrying $($directFailed.Count) failed packages via sdkmanager: $failNames" "INFO"
            foreach ($pkg in $directFailed) {
                $pkgName = ($pkg -split ";")[-1]
                $pkgDir = Join-Path $androidSdkRoot ($pkg -replace ";", "\")
                $script:SpinnerSync.Message = "SDK fallback (sdkmanager): $pkgName..."
                $retryPsi = New-Object System.Diagnostics.ProcessStartInfo
                $retryPsi.FileName = "cmd.exe"
                $retryPsi.Arguments = "/c `"`"$sdkmanager`" --sdk_root=`"$androidSdkRoot`" `"$pkg`"`""
                $retryPsi.UseShellExecute = $false
                $retryPsi.CreateNoWindow = $true
                $retryPsi.RedirectStandardOutput = $true
                $retryPsi.RedirectStandardError = $true
                $retryProc = [System.Diagnostics.Process]::Start($retryPsi)
                $retryOut = $retryProc.StandardOutput.ReadToEndAsync()
                $retryErr = $retryProc.StandardError.ReadToEndAsync()
                $retryProc.WaitForExit()
                $null = $retryOut.GetAwaiter().GetResult()
                $null = $retryErr.GetAwaiter().GetResult()
                if (Test-Path $pkgDir) {
                    Write-Log "SDK: $pkgName installed (sdkmanager fallback)" "OK"
                    $sdkInstalled++
                } else {
                    Write-Log "SDK: $pkgName failed all methods" "WARN"
                    $sdkFailed++
                }
            }
        } elseif ($directFailed.Count -gt 0) {
            $sdkFailed += $directFailed.Count
        }

        # Collect sdkmanager results with multi-layer fallback
        if ($sdkMgrProc) {
            Remove-Item $yesFile -Force -ErrorAction SilentlyContinue
            foreach ($pkg in $sdkMgrNeeded) {
                $pkgName = ($pkg -split ";")[-1]
                $pkgDir = Join-Path $androidSdkRoot ($pkg -replace ";", "\")
                if (Test-Path $pkgDir) {
                    Write-Log "SDK: $pkgName installed via sdkmanager" "OK"
                    $sdkInstalled++
                    continue
                }

                # Fallback 1: retry via sdkmanager individually
                $script:SpinnerSync.Message = "SDK retry (sdkmanager): $pkgName..."
                $retryPsi = New-Object System.Diagnostics.ProcessStartInfo
                $retryPsi.FileName = "cmd.exe"
                $retryPsi.Arguments = "/c `"`"$sdkmanager`" --sdk_root=`"$androidSdkRoot`" `"$pkg`"`""
                $retryPsi.UseShellExecute = $false
                $retryPsi.CreateNoWindow = $true
                $retryPsi.RedirectStandardOutput = $true
                $retryPsi.RedirectStandardError = $true
                $retryProc = [System.Diagnostics.Process]::Start($retryPsi)
                $retryOut = $retryProc.StandardOutput.ReadToEndAsync()
                $retryErr = $retryProc.StandardError.ReadToEndAsync()
                $retryProc.WaitForExit()
                $null = $retryOut.GetAwaiter().GetResult()
                $null = $retryErr.GetAwaiter().GetResult()

                if (Test-Path $pkgDir) {
                    Write-Log "SDK: $pkgName installed (sdkmanager retry)" "OK"
                    $sdkInstalled++
                    continue
                }

                # Fallback 2: direct download from manifest URL (if available)
                if ($sdkMgrDirectFallback.ContainsKey($pkg)) {
                    $script:SpinnerSync.Message = "SDK retry (direct download): $pkgName..."
                    $dlUrl = $sdkMgrDirectFallback[$pkg]
                    $dlZip = Join-Path $env:TEMP "sdk_mgr_$pkgName.zip"
                    $dlExtract = Join-Path $env:TEMP "sdk_mgr_extract_$pkgName"
                    try {
                        $ProgressPreference = 'SilentlyContinue'
                        Invoke-WebRequest -Uri $dlUrl -OutFile $dlZip -UseBasicParsing -TimeoutSec 600
                        if (Test-Path $dlExtract) { Remove-Item $dlExtract -Recurse -Force }
                        Expand-Archive -Path $dlZip -DestinationPath $dlExtract -Force -ErrorAction SilentlyContinue
                        # If Expand-Archive fails (not a zip), try 7z
                        if (-not (Get-ChildItem $dlExtract -ErrorAction SilentlyContinue)) {
                            $7z = "C:\Program Files\7-Zip\7z.exe"
                            if (Test-Path $7z) {
                                New-Item -ItemType Directory -Path $dlExtract -Force | Out-Null
                                & $7z x $dlZip -o"$dlExtract" -y 2>&1 | Out-Null
                            }
                        }
                        $parentDir = Split-Path $pkgDir
                        if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
                        $firstSub = @(Get-ChildItem $dlExtract -Directory -ErrorAction SilentlyContinue)[0]
                        if ($firstSub) { Move-Item $firstSub.FullName $pkgDir -Force }
                        else { Move-Item $dlExtract $pkgDir -Force }
                        Remove-Item $dlZip -Force -ErrorAction SilentlyContinue
                        Remove-Item $dlExtract -Recurse -Force -ErrorAction SilentlyContinue
                        $ProgressPreference = 'Continue'
                    } catch {
                        $ProgressPreference = 'Continue'
                        Remove-Item $dlZip -Force -ErrorAction SilentlyContinue
                        Remove-Item $dlExtract -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }

                if (Test-Path $pkgDir) {
                    Write-Log "SDK: $pkgName installed (direct download fallback)" "OK"
                    $sdkInstalled++
                } else {
                    Write-Log "SDK: $pkgName failed all methods (sdkmanager + direct)" "WARN"
                    $sdkFailed++
                }
            }
        }

        Stop-Spinner -FinalMessage "Android SDK: $sdkInstalled installed, $sdkSkipped already present, $sdkFailed failed" -Status "OK"
    }

    # Set NDK path
    $ndkDir = Get-ChildItem "$androidSdkRoot\ndk" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($ndkDir) {
        [System.Environment]::SetEnvironmentVariable("ANDROID_NDK_HOME", $ndkDir.FullName, "Machine")
        $env:ANDROID_NDK_HOME = $ndkDir.FullName
        Write-Log "ANDROID_NDK_HOME set to $($ndkDir.FullName)" "OK"
    }
} else {
    Write-Log "sdkmanager not found - Android SDK packages will need manual install" "WARN"
}

} # end Android SDK else block (preflight check)

Write-Log "Dev & security tools installed" "OK"

# ============================================================================
# pip - ensure available in PATH + global tools
# ============================================================================
Write-SubStep "Python pip global tools"

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Ensure pip is in PATH (add Python Scripts dir)
$pythonExe = Get-Command python -ErrorAction SilentlyContinue
if ($pythonExe) {
    $pythonDir = Split-Path $pythonExe.Source
    $scriptsDir = Join-Path $pythonDir "Scripts"
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notmatch [regex]::Escape($scriptsDir)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$scriptsDir", "Machine")
        $env:Path = "$env:Path;$scriptsDir"
        Write-Log "Python Scripts dir added to PATH ($scriptsDir)" "OK"
    }

    # Also add user site-packages scripts
    $userScripts = & python -c "import site; print(site.getusersitepackages().replace('site-packages','Scripts'))" 2>$null
    if ($userScripts -and (Test-Path $userScripts -ErrorAction SilentlyContinue) -eq $false) {
        New-Item -ItemType Directory -Path $userScripts -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if ($userScripts -and $machinePath -notmatch [regex]::Escape($userScripts)) {
        [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$userScripts", "Machine")
        $env:Path = "$env:Path;$userScripts"
    }

    # Collect background pip results (launched at module start)
    if ($bgPipJob) {
        Write-Log "Collecting background pip results..." "INFO"
        if ($bgPipJob.State -eq "Running") {
            Start-Spinner "Waiting for background pip install to finish..."
            $bgPipJob | Wait-Job | Out-Null
            Stop-Spinner -FinalMessage "Background pip install completed" -Status "OK"
        }
        $pipResults = Receive-Job $bgPipJob
        Remove-Job $bgPipJob -Force -ErrorAction SilentlyContinue
        if ($pipResults.upgraded) { Write-Log "pip upgraded (background)" "OK" }
        if ($pipResults.installed.Count -gt 0) { Write-Log "pip: $($pipResults.installed.Count) packages installed (background): $($pipResults.installed -join ', ')" "OK" }
        if ($pipResults.failed.Count -gt 0) {
            $pipRetryPkgs = @($pipResults.failed | Where-Object { $_ -notmatch "^EXCEPTION:" })
            if ($pipRetryPkgs.Count -gt 0) {
                Write-Log "pip: $($pipRetryPkgs.Count) packages failed (background), retrying in parallel..." "WARN"
                Start-Spinner "pip: retrying $($pipRetryPkgs.Count) packages in parallel..."

                # Launch all pip installs as parallel jobs
                $pipJobs = @()
                foreach ($pkg in $pipRetryPkgs) {
                    $pipJobs += Start-Job -ScriptBlock {
                        param($p)
                        & cmd /c "python -m pip install --user $p >""$env:TEMP\pip-retry-$p.log"" 2>&1"
                        return @{ pkg = $p; ok = ($LASTEXITCODE -eq 0) }
                    } -ArgumentList $pkg
                }

                # Poll with spinner showing progress
                while ($pipJobs | Where-Object { $_.State -eq "Running" }) {
                    $done = @($pipJobs | Where-Object { $_.State -ne "Running" }).Count
                    $script:SpinnerSync.Message = "pip parallel retry: $done/$($pipJobs.Count) done"
                    Start-Sleep -Seconds 2
                }

                # Collect results
                $retryOk = 0
                $retryFail = @()
                foreach ($job in $pipJobs) {
                    $res = Receive-Job $job
                    if ($res.ok) { $retryOk++; Write-Log "pip: $($res.pkg) installed (retry)" "OK" }
                    else { $retryFail += $res.pkg }
                    Remove-Job $job -Force -ErrorAction SilentlyContinue
                }
                # Clean up temp logs
                Remove-Item "$env:TEMP\pip-retry-*.log" -Force -ErrorAction SilentlyContinue

                if ($retryFail.Count -gt 0) {
                    Stop-Spinner -FinalMessage "pip: $retryOk recovered, $($retryFail.Count) still failed" -Status "WARN"
                    Write-Log "pip still failed: $($retryFail -join ', ')" "WARN"
                } else {
                    Stop-Spinner -FinalMessage "pip: all $retryOk packages recovered" -Status "OK"
                }
            }
        }
    } else {
        # No background job — pip was either already done or python wasn't found at launch
        # Check again now (python might have been installed by a module since)
        $pythonNow = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonNow -and -not $bgPipJob) {
            # Upgrade pip
            Write-Log "Upgrading pip..." "INFO"
            & cmd /c "python -m pip install --upgrade pip >""$env:TEMP\pip-upgrade.log"" 2>&1"
            Remove-Item "$env:TEMP\pip-upgrade.log" -Force -ErrorAction SilentlyContinue
            Write-Log "pip upgraded" "OK"

            $pipAll = @("cookiecutter", "pre-commit", "yt-dlp", "httpie", "poetry", "build", "wheel", "setuptools", "bandit")
            $pipInstalled = (python -m pip list --format=columns 2>$null) -join "`n"
            $pipNeeded = @($pipAll | Where-Object { $pipInstalled -notmatch "(?i)^$_\s" })
            if ($pipNeeded.Count -eq 0) {
                Write-Log "pip global tools already installed ($($pipAll.Count) packages)" "OK"
            } else {
                Start-Spinner "pip: installing $($pipNeeded.Count) packages in parallel..."
                # Launch all pip installs as parallel jobs
                $fgPipJobs = @()
                foreach ($pkg in $pipNeeded) {
                    $fgPipJobs += Start-Job -ScriptBlock {
                        param($p)
                        & cmd /c "python -m pip install --user $p >""$env:TEMP\pip-fg-$p.log"" 2>&1"
                        return @{ pkg = $p; ok = ($LASTEXITCODE -eq 0) }
                    } -ArgumentList $pkg
                }
                while ($fgPipJobs | Where-Object { $_.State -eq "Running" }) {
                    $done = @($fgPipJobs | Where-Object { $_.State -ne "Running" }).Count
                    $script:SpinnerSync.Message = "pip parallel: $done/$($fgPipJobs.Count) done"
                    Start-Sleep -Seconds 2
                }
                $pipOk = 0; $pipFail = 0
                foreach ($job in $fgPipJobs) {
                    $res = Receive-Job $job
                    if ($res.ok) { $pipOk++ } else { $pipFail++; Write-Log "pip: $($res.pkg) failed" "WARN" }
                    Remove-Job $job -Force -ErrorAction SilentlyContinue
                }
                Remove-Item "$env:TEMP\pip-fg-*.log" -Force -ErrorAction SilentlyContinue
                Stop-Spinner -FinalMessage "pip: $pipOk installed, $pipFail failed" -Status $(if ($pipFail -eq 0) { "OK" } else { "WARN" })
            }
        }
    }
} else {
    Write-Log "Python not found - pip global tools skipped" "WARN"
}

# ============================================================================
# Rust + Cargo Tooling
# ============================================================================
Write-SubStep "Rust & Cargo Tooling"

Install-App "Rust (rustup)" -WingetId "Rustlang.Rustup" -ChocoId "rustup.install" -ScoopId "rustup"

# Refresh PATH and aggressively find rustup/cargo
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
if (Test-Path $cargoBin) { $env:Path = "$cargoBin;$env:Path" }
# Search common locations if not on PATH
$rustupExe = Get-Command rustup -ErrorAction SilentlyContinue
if (-not $rustupExe) {
    $rustupCandidates = @(
        "$env:USERPROFILE\.cargo\bin\rustup.exe",
        "$env:LOCALAPPDATA\Programs\Rust\rustup\rustup.exe",
        "C:\Users\$env:USERNAME\.cargo\bin\rustup.exe"
    )
    foreach ($c in $rustupCandidates) {
        if (Test-Path $c) {
            $rustDir = Split-Path $c
            $env:Path = "$rustDir;$env:Path"
            $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($machinePath -notmatch [regex]::Escape($rustDir)) {
                [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$rustDir", "Machine")
            }
            $cargoBin = $rustDir
            Write-Log "Rust found at $rustDir (added to PATH)" "OK"
            break
        }
    }
    $rustupExe = Get-Command rustup -ErrorAction SilentlyContinue
}
if ($rustupExe) {
    # Install stable toolchain + common components (rustup skips already-installed ones internally)
    rustup default stable 2>&1 | Out-Null
    # Check installed components before adding
    $installedComponents = (rustup component list --installed 2>$null) -join "`n"
    $neededComponents = @("rustfmt", "clippy", "rust-analyzer", "rust-src") | Where-Object { $installedComponents -notmatch $_ }
    if ($neededComponents.Count -gt 0) {
        rustup component add @neededComponents 2>&1 | Out-Null
        Write-Log "Rust components added: $($neededComponents -join ', ')" "OK"
    } else {
        Write-Log "Rust components already installed" "OK"
    }
    # Check installed targets before adding
    $installedTargets = (rustup target list --installed 2>$null) -join "`n"
    $neededTargets = @("x86_64-pc-windows-gnu", "x86_64-unknown-linux-gnu", "wasm32-unknown-unknown") | Where-Object { $installedTargets -notmatch $_ }
    if ($neededTargets.Count -gt 0) {
        foreach ($t in $neededTargets) { rustup target add $t 2>&1 | Out-Null }
        Write-Log "Rust targets added: $($neededTargets -join ', ')" "OK"
    } else {
        Write-Log "Rust targets already installed" "OK"
    }

    # Cargo global tools - check if exe already exists before compiling
    $cargoTools = @(
        "cargo-watch",           # Auto-rebuild on file change
        "cargo-edit",            # cargo add/rm/upgrade deps
        "cargo-expand",          # Expand macros
        "cargo-audit",           # Security vulnerability checker
        "cargo-deny",            # Lint dependencies
        "cargo-outdated",        # Find outdated deps
        "cargo-nextest",         # Faster test runner
        "cargo-tarpaulin",       # Code coverage
        "cargo-bloat",           # Find what takes space in binary
        "cargo-flamegraph",      # Generate flamegraphs
        "cargo-make",            # Task runner / build system
        "cargo-generate",        # Project templates
        "cargo-release",         # Release automation
        "cargo-criterion",       # Benchmarking
        "cargo-udeps",           # Find unused dependencies
        "sccache",               # Shared compilation cache
        "cross",                 # Cross-compilation helper
        "wasm-pack",             # WASM packaging
        "trunk",                 # WASM web app bundler
        "mdbook"                 # Rust book/docs generator
    )
    $cargoSkipped = 0
    foreach ($tool in $cargoTools) {
        $toolExe = Join-Path $cargoBin "$tool.exe"
        if (Test-Path $toolExe) {
            $cargoSkipped++
            continue
        }
        $script:SpinnerSync.Message = "cargo install $tool"
        $r = Invoke-Silent "cargo" "install $tool"
        if ($r.ExitCode -eq 0) {
            Write-Log "cargo: $tool" "OK"
        } else {
            Write-Log "cargo: $tool failed" "WARN"
        }
    }
    if ($cargoSkipped -gt 0) { Write-Log "cargo: $cargoSkipped tools already installed" "OK" }
    Write-Log "Cargo tools done ($($cargoTools.Count) packages)" "OK"

    # Set sccache as default compiler wrapper
    if ([System.Environment]::GetEnvironmentVariable("RUSTC_WRAPPER", "User") -ne "sccache") {
        [System.Environment]::SetEnvironmentVariable("RUSTC_WRAPPER", "sccache", "User")
        Write-Log "sccache set as RUSTC_WRAPPER for faster builds" "OK"
    }
} else {
    Write-Log "Rust/rustup not found - cargo tools skipped" "WARN"
}

# ============================================================================
# Go Toolchain
# ============================================================================
Write-SubStep "Go Toolchain"

# Ensure Go is installed (also installed in module 16, but be idempotent)
Install-App "Go" -WingetId "GoLang.Go" -ChocoId "golang" -ScoopId "go"

# Refresh PATH and aggressively find Go
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Search common Go install locations if not on PATH
$goExe = Get-Command go -ErrorAction SilentlyContinue
if (-not $goExe) {
    $goCandidates = @(
        "C:\Program Files\Go\bin",
        "C:\Go\bin",
        "$env:LOCALAPPDATA\Programs\Go\bin",
        "$env:USERPROFILE\go\bin",
        "$env:USERPROFILE\scoop\apps\go\current\bin"
    )
    foreach ($gDir in $goCandidates) {
        if (Test-Path "$gDir\go.exe") {
            $env:Path = "$gDir;$env:Path"
            $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
            if ($machinePath -notmatch [regex]::Escape($gDir)) {
                [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$gDir", "Machine")
            }
            Write-Log "Go found at $gDir (added to PATH)" "OK"
            break
        }
    }
    $goExe = Get-Command go -ErrorAction SilentlyContinue
}

# Set GOPATH and add GOPATH/bin to PATH
$goPath = Join-Path $env:USERPROFILE "go"
if (-not (Test-Path $goPath)) { New-Item -ItemType Directory -Path $goPath -Force | Out-Null }
$goBin = Join-Path $goPath "bin"
if (-not (Test-Path $goBin)) { New-Item -ItemType Directory -Path $goBin -Force | Out-Null }

[System.Environment]::SetEnvironmentVariable("GOPATH", $goPath, "User")
$env:GOPATH = $goPath

$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notmatch [regex]::Escape($goBin)) {
    [System.Environment]::SetEnvironmentVariable("Path", "$machinePath;$goBin", "Machine")
    $env:Path = "$env:Path;$goBin"
    Write-Log "GOPATH/bin added to system PATH ($goBin)" "OK"
}
if ($goExe) {
    Write-Log "Go available: $(go version 2>$null)" "OK"

    # Go global tools
    $goTools = @(
        # Linting & formatting
        "golang.org/x/tools/cmd/goimports@latest",          # Auto-fix imports
        "github.com/golangci/golangci-lint/cmd/golangci-lint@latest",  # Meta-linter
        "mvdan.cc/gofumpt@latest",                           # Stricter gofmt
        "github.com/segmentio/golines@latest",               # Long line fixer

        # Code generation
        "google.golang.org/protobuf/cmd/protoc-gen-go@latest",        # Protobuf Go codegen
        "google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest",       # gRPC Go codegen
        "github.com/deepmap/oapi-codegen/v2/cmd/oapi-codegen@latest", # OpenAPI codegen
        "github.com/sqlc-dev/sqlc/cmd/sqlc@latest",                    # SQL --- Go codegen
        "go.uber.org/mock/mockgen@latest",                              # Mock generator
        "github.com/vektra/mockery/v2@latest",                          # Interface mocks

        # Testing & debugging
        "github.com/rakyll/hey@latest",                      # HTTP load tester
        "github.com/go-delve/delve/cmd/dlv@latest",          # Go debugger
        "gotest.tools/gotestsum@latest",                     # Better test output
        "github.com/kyoh86/richgo@latest",                   # Colorized test output

        # Build & release
        "github.com/goreleaser/goreleaser/v2@latest",        # Release automation
        "github.com/cosmtrek/air@latest",                    # Live reload for Go apps

        # Security
        "golang.org/x/vuln/cmd/govulncheck@latest",         # Vulnerability checker

        # Documentation
        "golang.org/x/pkgsite/cmd/pkgsite@latest",          # Local godoc server

        # Dependency management
        "github.com/icholy/gomajor@latest",                  # Major version upgrade helper

        # Misc utilities
        "github.com/cweill/gotests/gotests@latest",          # Auto-generate test stubs
        "github.com/fatih/gomodifytags@latest",              # Modify struct tags
        "github.com/josharian/impl@latest"                   # Generate interface stubs
    )

    $goSkipped = 0
    foreach ($tool in $goTools) {
        $toolName = ($tool -split "/")[-1] -replace "@.*", ""
        $toolExe = Join-Path $goBin "$toolName.exe"
        if (Test-Path $toolExe) {
            $goSkipped++
            continue
        }
        $script:SpinnerSync.Message = "go install $toolName"
        $r = Invoke-Silent "go" "install $tool"
        if ($r.ExitCode -eq 0) {
            Write-Log "go: $toolName" "OK"
        } else {
            Write-Log "go: $toolName failed" "WARN"
        }
    }
    if ($goSkipped -gt 0) { Write-Log "go: $goSkipped tools already installed" "OK" }
    Write-Log "Go tools done ($($goTools.Count) packages)" "OK"

    # Enable Go modules by default and set useful env vars
    go env -w GOFLAGS="-mod=mod" >$null 2>&1
    go env -w GONOSUMCHECK="off" >$null 2>&1
    Write-Log "Go env configured" "OK"
} else {
    Write-Log "Go not found - Go tools skipped" "WARN"
}

# ============================================================================
# Infrastructure / Cloud / Kubernetes
# ============================================================================
Write-SubStep "Infrastructure & Kubernetes"

Install-App "Terraform"             -WingetId "Hashicorp.Terraform"            -ChocoId "terraform"      -ScoopId "terraform"
Install-App "Pulumi"                -WingetId "Pulumi.Pulumi"                  -ChocoId "pulumi"
Install-App "kubectl"               -WingetId "Kubernetes.kubectl"             -ChocoId "kubernetes-cli"  -ScoopId "kubectl"
Install-App "Helm"                  -WingetId "Helm.Helm"                      -ChocoId "kubernetes-helm" -ScoopId "helm"
Install-App "Minikube"              -WingetId "Kubernetes.minikube"            -ChocoId "minikube"        -ScoopId "minikube"

Write-Log "Infrastructure tools installed" "OK"

# ============================================================================
# Container Extras (Podman, lazydocker, dive)
# ============================================================================
Write-SubStep "Container Extras"

Install-App "Podman"                -WingetId "RedHat.Podman"                  -ChocoId "podman-cli"
Install-App "lazydocker"            -WingetId "JesseDuffield.Lazydocker"       -ChocoId "lazydocker"     -ScoopId "lazydocker"
Install-App "dive"                  -ChocoId "dive"                            -ScoopId "dive"
# dive fallback: download from GitHub
if (-not (Get-Command dive -ErrorAction SilentlyContinue) -and -not (Test-Path "C:\bin\dive.exe")) {
    $diveUrl = Get-GitHubReleaseUrl -Repo "wagoodman/dive" -Pattern "dive_.*_windows_amd64\.zip$"
    if ($diveUrl) {
        Install-PortableBin -Name "dive" -Url $diveUrl -ExeName "dive.exe"
    }
}

Install-App "ctop"                  -ChocoId "ctop"                            -ScoopId "ctop"
# ctop fallback: download from GitHub (standalone exe)
if (-not (Get-Command ctop -ErrorAction SilentlyContinue) -and -not (Test-Path "C:\bin\ctop.exe")) {
    $ctopUrl = Get-GitHubReleaseUrl -Repo "bcicen/ctop" -Pattern "ctop-.*-windows-amd64$"
    if ($ctopUrl) {
        Install-PortableBin -Name "ctop" -Url $ctopUrl -ExeName "ctop.exe" -ArchiveType "direct"
    }
}

Write-Log "Container extras installed (Podman, lazydocker, dive, ctop)" "OK"

# ============================================================================
# gRPC / Protobuf Tooling
# ============================================================================
Write-SubStep "gRPC & Protobuf"

Install-App "Protobuf (protoc)"     -WingetId "Google.Protobuf"               -ChocoId "protoc"         -ScoopId "protobuf"

# Install gRPC tools via various package managers
if ($useNodeDirect) {
    $grpcCheck = Invoke-Npm "list -g --depth=0"
    if ($grpcCheck.Output -match "grpc-tools") {
        Write-Log "gRPC Node.js tools already installed" "OK"
    } else {
        Invoke-Npm "install -g grpc-tools grpc_tools_node_protoc_ts @grpc/grpc-js" | Out-Null
        Write-Log "gRPC Node.js tools installed" "OK"
    }
} elseif (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmGrpc = (npm list -g --depth=0 2>$null) -join "`n"
    if ($npmGrpc -match "grpc-tools") {
        Write-Log "gRPC Node.js tools already installed" "OK"
    } else {
        npm install -g grpc-tools grpc_tools_node_protoc_ts @grpc/grpc-js 2>&1 | Out-Null
        Write-Log "gRPC Node.js tools installed" "OK"
    }
}

$pipCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pipCmd) {
    $pipGrpc = (python -m pip list --format=columns 2>$null) -join "`n"
    if ($pipGrpc -match "grpcio") {
        Write-Log "gRPC Python tools already installed" "OK"
    } else {
        Start-Spinner "gRPC: installing Python tools (grpcio, grpcio-tools, protobuf)..."
        & cmd /c "python -m pip install --user grpcio grpcio-tools protobuf >""$env:TEMP\pip-grpc.log"" 2>&1"
        Remove-Item "$env:TEMP\pip-grpc.log" -Force -ErrorAction SilentlyContinue
        Stop-Spinner -FinalMessage "gRPC Python tools installed" -Status "OK"
    }
}

# Buf (modern protobuf tooling - lint, format, breaking change detection)
Install-PortableBin -Name "buf" `
    -Url "https://github.com/bufbuild/buf/releases/latest/download/buf-Windows-x86_64.exe" `
    -ExeName "buf.exe" -ArchiveType "direct"

# grpcurl (like curl for gRPC) - dynamic URL
$grpcurlUrl = Get-GitHubReleaseUrl -Repo "fullstorydev/grpcurl" -Pattern "windows_x86_64\.zip$"
if ($grpcurlUrl) {
    Install-PortableBin -Name "grpcurl" -Url $grpcurlUrl -ExeName "grpcurl.exe"
}

# Evans (gRPC interactive client / REPL) - dynamic URL (releases are .tar.gz only)
$evansUrl = Get-GitHubReleaseUrl -Repo "ktr0731/evans" -Pattern "windows_amd64\.tar\.gz$"
if ($evansUrl) {
    Install-PortableBin -Name "evans" -Url $evansUrl -ExeName "evans.exe" -ArchiveType "targz"
}

Write-Log "gRPC/Protobuf tooling installed (protoc, buf, grpcurl, evans)" "OK"

# ============================================================================
# Dev Extras (Graphviz, SQLite, Meld)
# ============================================================================
Write-SubStep "Dev Extras"

Install-App "Graphviz"              -WingetId "Graphviz.Graphviz"              -ChocoId "graphviz"       -ScoopId "graphviz"
Install-App "SQLite Tools"          -WingetId "SQLite.SQLite"                  -ChocoId "sqlite"         -ScoopId "sqlite"
Install-App "DB Browser for SQLite" -WingetId "DBBrowserForSQLite.DBBrowserForSQLite" -ChocoId "sqlitebrowser"
Install-App "Meld"                  -WingetId "Meld.Meld"                      -ChocoId "meld"

Write-Log "Dev extras installed" "OK"

Write-Log "Module 14 - Dev Tools completed" "OK"

