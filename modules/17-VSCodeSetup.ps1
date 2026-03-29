# Module: 17 - VS Code Setup
# VS Code extensions + Fira Code font + VS Code settings + Windows Terminal theme + context menu

Write-Section "VS Code Setup" "Extensions, fonts, settings, terminal theme, context menu"

# ============================================================================
# VS Code Extensions
# ============================================================================

# Check if code CLI is available
$codePath = Get-Command code -ErrorAction SilentlyContinue
if (-not $codePath) {
    # Try common install paths
    $codeExe = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $codeExe) { $codePath = $codeExe }
}

if ($codePath) {
    $vscodeExtensions = @(
        # AI / Assistants
        "anthropic.claude-code",                          # Claude Code
        "Codex.codex",                                    # Codex
        "github.copilot-chat",                            # GitHub Copilot Chat
        "rooveterinaryinc.roo-cline",                     # Roo Code

        # AutoIt
        "loganch.vscode-autoit",                          # AutoIt

        # C/C++
        "ms-vscode.cpptools",                             # C/C++ IntelliSense, debugging
        "ms-vscode.cpptools-extension-pack",              # C/C++ Extension Pack
        "ms-vscode.cpptools-themes",                      # C/C++ Themes
        "ms-vscode.cmake-tools",                          # CMake Tools
        "ms-vscode.makefile-tools",                       # Makefile Tools

        # Rust
        "rust-lang.rust-analyzer",                        # Rust Analyzer

        # Kotlin / Gradle
        "fwcd.kotlin",                                    # Kotlin
        "vscjava.vscode-gradle",                          # Gradle for Java

        # Python
        "ms-python.python",                               # Python
        "ms-python.vscode-pylance",                       # Pylance
        "ms-python.debugpy",                              # Python Debugger
        "ms-python.vscode-python-envs",                   # Python Environments
        "charliermarsh.ruff",                             # Ruff (Python linter)

        # Docker / Containers
        "ms-azuretools.vscode-docker",                    # Docker
        "ms-vscode-remote.remote-containers",             # Dev Containers
        "ms-vscode-remote.remote-wsl",                    # WSL

        # Web / JS
        "dbaeumer.vscode-eslint",                         # ESLint
        "esbenp.prettier-vscode",                         # Prettier
        "christian-kohler.npm-intellisense",              # npm Intellisense

        # Markdown / LaTeX
        "DavidAnson.vscode-markdownlint",                 # Markdown Lint
        "James-Yu.latex-workshop",                        # LaTeX Workshop

        # Shell
        "ms-vscode.powershell",                           # PowerShell
        "timonwong.shellcheck",                           # ShellCheck

        # GitHub
        "github.vscode-github-actions",                   # GitHub Actions

        # Theme
        "pinage404.dark-pure-oled",                       # Dark Pure OLED

        # Utilities
        "streetsidesoftware.code-spell-checker",          # Code Spell Checker
        "nickmillerdev.scriptmonkey"                      # ScriptMonkey
    )

    $codeCmd = if ($codePath -is [string]) { $codePath } else { "code" }

    # Get already-installed extensions once
    $installedExts = @(& $codeCmd --list-extensions 2>$null)
    $extSkipped = 0
    foreach ($ext in $vscodeExtensions) {
        if ($installedExts -contains $ext) {
            $extSkipped++
            continue
        }
        $script:SpinnerSync.Message = "VS Code: $ext"
        & $codeCmd --install-extension $ext --force 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "VS Code ext: $ext" "OK"
        } else {
            Write-Log "VS Code ext failed: $ext" "WARN"
        }
    }
    if ($extSkipped -gt 0) { Write-Log "VS Code: $extSkipped extensions already installed" "OK" }
    Write-Log "VS Code extensions done ($($vscodeExtensions.Count) total)" "OK"
} else {
    Write-Log "VS Code CLI not found - skipping extension install (install VS Code first)" "WARN"
}

# ============================================================================
# Install Fira Code Font
# ============================================================================
Write-SubStep "Fira Code Font"

# Check if Fira Code NF is already installed
$firaInstalled = Get-ChildItem "$env:WINDIR\Fonts" -Filter "FiraCode*NerdFont*" -ErrorAction SilentlyContinue
if ($firaInstalled -and $firaInstalled.Count -gt 5) {
    Write-Log "Fira Code Nerd Font already installed ($($firaInstalled.Count) files)" "OK"
} else {
Write-Log "Downloading Fira Code Nerd Font..."
$nerdFontVersion = "v3.3.0"
$firaZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$nerdFontVersion/FiraCode.zip"
$firaZipPath = Join-Path $env:TEMP "FiraCode.zip"
$firaExtractPath = Join-Path $env:TEMP "FiraCode"

try {
    Invoke-WebRequest -Uri $firaZipUrl -OutFile $firaZipPath -UseBasicParsing
    if (Test-Path $firaExtractPath) { Remove-Item $firaExtractPath -Recurse -Force }
    Expand-Archive -Path $firaZipPath -DestinationPath $firaExtractPath -Force

    $fontsDir = "$env:WINDIR\Fonts"
    $fontRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $installed = 0

    Get-ChildItem $firaExtractPath -Filter "*.ttf" | ForEach-Object {
        $destPath = Join-Path $fontsDir $_.Name
        if (-not (Test-Path $destPath)) {
            Copy-Item $_.FullName -Destination $destPath -Force
            # Register the font
            $fontName = $_.BaseName -replace "NerdFont", "Nerd Font" -replace "-", " "
            Set-ItemProperty -Path $fontRegPath -Name "$fontName (TrueType)" -Value $_.Name -Type String
            $installed++
        }
    }
    Write-Log "Fira Code Nerd Font installed ($installed font files)" "OK"

    # Cleanup
    Remove-Item $firaZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $firaExtractPath -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Failed to install Fira Code: $_" "ERROR"
}
} # end Fira Code check

# ============================================================================
# VS Code Settings
# ============================================================================
Write-SubStep "VS Code Settings"

$vsCodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
$vsCodeSettingsDir  = Split-Path $vsCodeSettingsPath

if (-not (Test-Path $vsCodeSettingsDir)) {
    New-Item -ItemType Directory -Path $vsCodeSettingsDir -Force | Out-Null
}

# Merge with existing settings if they exist
$vsSettings = @{}
if (Test-Path $vsCodeSettingsPath) {
    try {
        $vsSettings = Get-Content $vsCodeSettingsPath -Raw | ConvertFrom-Json -AsHashtable
    } catch {
        $vsSettings = @{}
    }
}

# Apply our settings (won't clobber keys we don't touch)
$wininItSettings = @{
    "workbench.colorTheme"                            = "Dark Pure OLED"
    "editor.fontFamily"                               = "'FiraCode Nerd Font', 'Fira Code', Consolas, monospace"
    "editor.fontLigatures"                            = $true
    "window.zoomLevel"                                = 0
    "editor.fontSize"                                 = 13
    "editor.tabSize"                                  = 4
    "editor.formatOnSave"                             = $true
    "editor.bracketPairColorization.enabled"          = $true
    "editor.minimap.enabled"                          = $false
    "editor.renderWhitespace"                         = "boundary"
    "editor.smoothScrolling"                          = $true
    "editor.cursorBlinking"                           = "smooth"
    "editor.cursorSmoothCaretAnimation"               = "on"
    "files.autoSave"                                  = "afterDelay"
    "files.autoSaveDelay"                             = 1000
    "terminal.integrated.fontFamily"                  = "'FiraCode Nerd Font'"
    "terminal.integrated.fontSize"                    = 9
    "terminal.integrated.defaultProfile.windows"      = "PowerShell"
    "workbench.startupEditor"                         = "none"
    "workbench.tips.enabled"                          = $false
    "telemetry.telemetryLevel"                        = "off"
    "update.showReleaseNotes"                         = $false
    "extensions.autoUpdate"                           = $true
    "git.autofetch"                                   = $true
    "git.confirmSync"                                 = $false
    "git.enableSmartCommit"                           = $true
    "explorer.confirmDelete"                          = $false
    "explorer.confirmDragAndDrop"                     = $false
}

foreach ($key in $wininItSettings.Keys) {
    $vsSettings[$key] = $wininItSettings[$key]
}

$vsSettings | ConvertTo-Json -Depth 10 | Set-Content $vsCodeSettingsPath -Encoding UTF8
Write-Log "VS Code settings configured (theme, font, autosave, telemetry off)" "OK"

# ============================================================================
# Windows Terminal Theme
# ============================================================================
Write-SubStep "Windows Terminal Theme"

# Load existing settings safely (handles comments, BOM, corruption)
$wtConfig = Read-WTSettings
if (-not $wtConfig) {
    $wtConfig = Repair-WTSettings
}

# Set top-level properties
$wtConfig | Add-Member -NotePropertyName "defaultProfile" -NotePropertyValue "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}" -Force
$wtConfig | Add-Member -NotePropertyName "theme" -NotePropertyValue "dark" -Force
$wtConfig | Add-Member -NotePropertyName "alwaysShowTabs" -NotePropertyValue $true -Force
$wtConfig | Add-Member -NotePropertyName "confirmCloseAllTabs" -NotePropertyValue $false -Force

# Set profile defaults (preserves existing profiles.list)
$profileDefaults = @{
    font = @{
        face = "FiraCode Nerd Font"
        size = 9
        weight = "normal"
    }
    colorScheme      = "WinInit Dark"
    opacity          = 92
    useAcrylic       = $true
    padding          = "12, 8, 12, 8"
    cursorShape      = "bar"
    cursorHeight     = 25
    scrollbarState   = "hidden"
    antialiasingMode = "cleartype"
}

if (-not $wtConfig.profiles) {
    $wtConfig | Add-Member -NotePropertyName "profiles" -NotePropertyValue ([PSCustomObject]@{}) -Force
}
$wtConfig.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue $profileDefaults -Force

# Build custom profiles using [PSCustomObject] (guarantees "hidden": false serialization)
$pwsh7Cmd = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh.exe -NoLogo" }
            elseif (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") { "`"$env:ProgramFiles\PowerShell\7\pwsh.exe`" -NoLogo" }
            else { "pwsh.exe -NoLogo" }

$profilesList = @(
    [PSCustomObject]@{
        guid        = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
        name        = "PowerShell"
        commandline = "powershell.exe -NoLogo"
        icon        = "ms-appx:///ProfileIcons/pwsh.png"
        tabTitle    = "PS"
        colorScheme = "WinInit Dark"
        hidden      = [bool]$false
    }
    [PSCustomObject]@{
        guid        = "{574e775e-4f2a-5b96-ac1e-a2962a402336}"
        name        = "PowerShell 7"
        commandline = $pwsh7Cmd
        source      = "Windows.Terminal.PowershellCore"
        icon        = "ms-appx:///ProfileIcons/pwsh.png"
        tabTitle    = "PS7"
        tabColor    = "#012456"
        colorScheme = "WinInit Dark"
        hidden      = [bool]$false
    }
    [PSCustomObject]@{
        guid        = "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}"
        name        = "Command Prompt"
        commandline = "cmd.exe"
        icon        = "ms-appx:///ProfileIcons/{0caa0dad-35be-5f56-a8ff-afceeeaa6101}.png"
        tabTitle    = "CMD"
        tabColor    = "#1E1E1E"
        colorScheme = "WinInit Dark"
        hidden      = [bool]$false
    }
)

# Add Git Bash if installed
$gitBashExe = "$env:ProgramFiles\Git\bin\bash.exe"
if (Test-Path $gitBashExe) {
    $profilesList += [PSCustomObject]@{
        guid        = "{2ece5bfe-50ed-5f3a-ab87-5cd4baafed2b}"
        name        = "Git Bash"
        commandline = "`"$gitBashExe`" --login -i"
        icon        = "$env:ProgramFiles\Git\mingw64\share\git\git-for-windows.ico"
        tabTitle    = "Bash"
        tabColor    = "#1D1F21"
        colorScheme = "WinInit Dark"
        hidden      = [bool]$false
    }
}

# Always overwrite profiles.list with our custom set
$wtConfig.profiles | Add-Member -NotePropertyName "list" -NotePropertyValue $profilesList -Force

# Color scheme
$wtScheme = @{
    name        = "WinInit Dark"
    background  = "#0A0A0A"
    foreground  = "#C8C8C8"
    cursorColor = "#00AAFF"
    selectionBackground = "#264F78"
    black       = "#1A1A1A"
    red         = "#FF5555"
    green       = "#50FA7B"
    yellow      = "#F1FA8C"
    blue        = "#6272E8"
    purple      = "#BD93F9"
    cyan        = "#8BE9FD"
    white       = "#C8C8C8"
    brightBlack   = "#555555"
    brightRed     = "#FF6E6E"
    brightGreen   = "#69FF94"
    brightYellow  = "#FFFFA5"
    brightBlue    = "#8294FF"
    brightPurple  = "#D6ACFF"
    brightCyan    = "#A4FFFF"
    brightWhite   = "#FFFFFF"
}

# Merge scheme into existing schemes array or create new
$existingSchemes = @()
if ($wtConfig.schemes) { $existingSchemes = @($wtConfig.schemes | Where-Object { $_.name -ne "WinInit Dark" }) }
$existingSchemes += $wtScheme
$wtConfig | Add-Member -NotePropertyName "schemes" -NotePropertyValue $existingSchemes -Force

# Theme
$wtTheme = @{
    name = "dark"
    tab = @{
        background = "#0A0A0AFF"
        unfocusedBackground = "#0A0A0AFF"
    }
    tabRow = @{
        background = "#0A0A0AFF"
        unfocusedBackground = "#0A0A0AFF"
    }
    window = @{
        applicationTheme = "dark"
    }
}
$existingThemes = @()
if ($wtConfig.themes) { $existingThemes = @($wtConfig.themes | Where-Object { $_.name -ne "dark" }) }
$existingThemes += $wtTheme
$wtConfig | Add-Member -NotePropertyName "themes" -NotePropertyValue $existingThemes -Force

Write-WTSettings -Config $wtConfig | Out-Null
Write-Log "Windows Terminal themed (OLED dark, Fira Code NF, acrylic, custom color scheme)" "OK"

# ============================================================================
# Context Menu: Open VS Code Here
# ============================================================================
Write-SubStep "Context Menu"

Write-Log "Adding 'Open with VS Code' to context menu..."
$codeExePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"

# Use reg.exe directly (HKCR via PowerShell PSDrive is extremely slow)
# Directory background (right-click inside a folder)
reg add "HKCR\Directory\Background\shell\VSCode" /ve /d "Open with VS Code" /f >$null 2>&1
reg add "HKCR\Directory\Background\shell\VSCode" /v "Icon" /d "$codeExePath" /f >$null 2>&1
reg add "HKCR\Directory\Background\shell\VSCode\command" /ve /d "`"$codeExePath`" `"%V`"" /f >$null 2>&1

# Folders (right-click on a folder)
reg add "HKCR\Directory\shell\VSCode" /ve /d "Open with VS Code" /f >$null 2>&1
reg add "HKCR\Directory\shell\VSCode" /v "Icon" /d "$codeExePath" /f >$null 2>&1
reg add "HKCR\Directory\shell\VSCode\command" /ve /d "`"$codeExePath`" `"%1`"" /f >$null 2>&1

# Files (right-click on any file)
reg add "HKCR\*\shell\VSCode" /ve /d "Open with VS Code" /f >$null 2>&1
reg add "HKCR\*\shell\VSCode" /v "Icon" /d "$codeExePath" /f >$null 2>&1
reg add "HKCR\*\shell\VSCode\command" /ve /d "`"$codeExePath`" `"%1`"" /f >$null 2>&1

Write-Log "VS Code context menu entries added (files, folders, background)" "OK"

# ============================================================================
# Oh My Posh + PowerShell Profile
# ============================================================================
Write-Log "Setting up Oh My Posh & PowerShell profile..."

# Install Oh My Posh
Install-App "Oh My Posh" -WingetId "JanDeDobbeleer.OhMyPosh" -ChocoId "oh-my-posh" -ScoopId "oh-my-posh"

# Install Terminal-Icons module
if (Get-Module -ListAvailable -Name Terminal-Icons -ErrorAction SilentlyContinue) {
    Write-Log "Terminal-Icons already installed" "OK"
} else {
    Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue
    Write-Log "Terminal-Icons installed" "OK"
}

# Install PSReadLine (latest)
if (Get-Module -ListAvailable -Name PSReadLine -ErrorAction SilentlyContinue) {
    Write-Log "PSReadLine already installed" "OK"
} else {
    Install-Module -Name PSReadLine -Scope CurrentUser -Force -AllowClobber -ErrorAction SilentlyContinue
    Write-Log "PSReadLine installed" "OK"
}

# Build PowerShell profile
$psProfile = $PROFILE.CurrentUserAllHosts
$psProfileDir = Split-Path $psProfile
if (-not (Test-Path $psProfileDir)) { New-Item -ItemType Directory -Path $psProfileDir -Force | Out-Null }

$profileContent = @'
# ============================================================================
# WinInit PowerShell Profile
# ============================================================================

# --- Oh My Posh prompt ---
$ompExe = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($ompExe) {
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\slim.omp.json" | Invoke-Expression
}

# --- Terminal Icons ---
if (Get-Module -ListAvailable -Name Terminal-Icons -ErrorAction SilentlyContinue) {
    Import-Module Terminal-Icons
}

# --- PSReadLine ---
if (Get-Module -ListAvailable -Name PSReadLine -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Chord "Ctrl+d" -Function DeleteCharOrExit
}

# --- Modern CLI aliases ---
if (Get-Command eza   -ErrorAction SilentlyContinue) { Set-Alias -Name ls    -Value eza   -Option AllScope -Force }
if (Get-Command bat   -ErrorAction SilentlyContinue) { Set-Alias -Name cat   -Value bat   -Option AllScope -Force }
if (Get-Command rg    -ErrorAction SilentlyContinue) { Set-Alias -Name grep  -Value rg    -Option AllScope -Force }
if (Get-Command fd    -ErrorAction SilentlyContinue) { Set-Alias -Name find  -Value fd    -Option AllScope -Force }
if (Get-Command procs -ErrorAction SilentlyContinue) { Set-Alias -Name ps2   -Value procs -Option AllScope -Force }
if (Get-Command dust  -ErrorAction SilentlyContinue) { Set-Alias -Name du    -Value dust  -Option AllScope -Force }
if (Get-Command btm   -ErrorAction SilentlyContinue) { Set-Alias -Name top   -Value btm   -Option AllScope -Force }
if (Get-Command lazygit -ErrorAction SilentlyContinue) { Set-Alias -Name lg  -Value lazygit -Option AllScope -Force }
if (Get-Command lazydocker -ErrorAction SilentlyContinue) { Set-Alias -Name ld -Value lazydocker -Option AllScope -Force }

# --- Python venv ---
function Activate-Venv { param([string]$Name = "default") & "C:\venv\$Name\Scripts\Activate.ps1" }
Set-Alias -Name venv -Value Activate-Venv

# --- Navigation ---
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }
function mkcd { param($dir) New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }

# --- Git shortcuts ---
function gs  { git status }
function gd  { git diff }
function gl  { git log --oneline -20 }
function gp  { git push }
function gpu { git pull }
function ga  { git add -A }
function gc  { param($msg) git commit -m $msg }

# --- Docker shortcuts ---
function dps  { docker ps }
function dpsa { docker ps -a }
function di   { docker images }
'@

if (Test-Path $psProfile) {
    $existing = Get-Content $psProfile -Raw
    if ($existing -notmatch "WinInit PowerShell Profile") {
        $profileContent + "`n`n" + $existing | Set-Content $psProfile -Encoding UTF8
        Write-Log "PowerShell profile merged" "OK"
    } else {
        Write-Log "WinInit profile already present" "OK"
    }
} else {
    Set-Content $psProfile -Value $profileContent -Encoding UTF8
    Write-Log "PowerShell profile created" "OK"
}

Write-Log "Oh My Posh + profile configured" "OK"

# ============================================================================
# File Associations
# ============================================================================
Write-Log "Setting file associations..."

# Helper: set file association via registry (UserChoice requires special handling on Win 10+)
function Set-FileAssociation {
    param([string]$Extension, [string]$ProgId)
    # Set the default program in HKCU Classes
    $extKey = "HKCU:\Software\Classes\$Extension"
    if (-not (Test-Path $extKey)) { New-Item -Path $extKey -Force | Out-Null }
    Set-ItemProperty -Path $extKey -Name "(default)" -Value $ProgId -Type String -ErrorAction SilentlyContinue

    # Set OpenWithProgids
    $openWith = "$extKey\OpenWithProgids"
    if (-not (Test-Path $openWith)) { New-Item -Path $openWith -Force | Out-Null }
    Set-ItemProperty -Path $openWith -Name $ProgId -Value ([byte[]]@()) -Type Binary -ErrorAction SilentlyContinue
}

# VS Code ProgId
$vsCodeProgId = "VSCode.txt"
$vsCodeKey = "HKCU:\Software\Classes\$vsCodeProgId"
if (-not (Test-Path $vsCodeKey)) { New-Item -Path $vsCodeKey -Force | Out-Null }
$vsCodeShell = "$vsCodeKey\shell\open\command"
if (-not (Test-Path $vsCodeShell)) { New-Item -Path $vsCodeShell -Force | Out-Null }
Set-ItemProperty -Path $vsCodeShell -Name "(default)" -Value "`"$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe`" `"%1`"" -Type String

# Code files -> VS Code
$codeExtensions = @(
    ".txt", ".md", ".markdown", ".json", ".jsonc", ".json5",
    ".py", ".pyw", ".pyi",
    ".ps1", ".psm1", ".psd1",
    ".sh", ".bash", ".zsh",
    ".rs", ".go", ".rb",
    ".js", ".mjs", ".cjs", ".jsx",
    ".ts", ".tsx",
    ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx",
    ".cs", ".java", ".kt", ".kts", ".scala",
    ".yml", ".yaml", ".toml", ".ini", ".cfg", ".conf",
    ".xml", ".xsl", ".xslt",
    ".html", ".htm", ".css", ".scss", ".less", ".sass",
    ".sql", ".graphql", ".gql",
    ".lua", ".vim", ".dockerfile",
    ".makefile", ".cmake",
    ".gitignore", ".gitattributes", ".editorconfig",
    ".env", ".env.local", ".env.example",
    ".log", ".csv", ".tsv",
    ".tf", ".tfvars", ".hcl",
    ".proto", ".svelte", ".vue"
)
foreach ($ext in $codeExtensions) {
    Set-FileAssociation -Extension $ext -ProgId $vsCodeProgId
}
Write-Log "Code file extensions ($($codeExtensions.Count) types) associated with VS Code" "OK"

# 7-Zip ProgId
$sevenZipProgId = "7-Zip.Archive"
$sevenZipKey = "HKCU:\Software\Classes\$sevenZipProgId"
if (-not (Test-Path $sevenZipKey)) { New-Item -Path $sevenZipKey -Force | Out-Null }
$sevenZipShell = "$sevenZipKey\shell\open\command"
if (-not (Test-Path $sevenZipShell)) { New-Item -Path $sevenZipShell -Force | Out-Null }
Set-ItemProperty -Path $sevenZipShell -Name "(default)" -Value "`"C:\Program Files\7-Zip\7zFM.exe`" `"%1`"" -Type String

# Archive files -> 7-Zip
$archiveExtensions = @(
    ".zip", ".7z", ".rar", ".tar", ".gz", ".tgz",
    ".bz2", ".xz", ".lzma", ".zst",
    ".cab", ".iso", ".img", ".wim"
)
foreach ($ext in $archiveExtensions) {
    Set-FileAssociation -Extension $ext -ProgId $sevenZipProgId
}
Write-Log "Archive file extensions ($($archiveExtensions.Count) types) associated with 7-Zip" "OK"

# PDF -> default browser (Chrome or Firefox)
$pdfProgId = "ChromeHTML"
$chromeExe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
$firefoxExe = "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
if (Test-Path $chromeExe) {
    $pdfProgId = "ChromeHTML"
} elseif (Test-Path $firefoxExe) {
    $pdfProgId = "FirefoxHTML"
}
Set-FileAssociation -Extension ".pdf" -ProgId $pdfProgId
Write-Log "PDF associated with $pdfProgId" "OK"

Write-Log "File associations configured" "OK"

# ============================================================================
# Windows Defender Exclusions (dev folders)
# ============================================================================
Write-Log "Adding Windows Defender exclusions for dev folders..."

$defenderExclusions = @(
    # Package managers / build caches
    "C:\vcpkg",
    "C:\venv",
    "C:\cygwin64",
    "C:\msys64",
    "C:\bin",
    "C:\apps",
    "C:\android-sdk",
    # User-level dev folders
    (Join-Path $env:USERPROFILE ".cargo"),
    (Join-Path $env:USERPROFILE ".rustup"),
    (Join-Path $env:USERPROFILE ".gradle"),
    (Join-Path $env:USERPROFILE ".m2"),
    (Join-Path $env:USERPROFILE ".nuget"),
    (Join-Path $env:USERPROFILE ".npm"),
    (Join-Path $env:USERPROFILE ".yarn"),
    (Join-Path $env:USERPROFILE "go"),
    (Join-Path $env:USERPROFILE "scoop"),
    (Join-Path $env:USERPROFILE "AppData\Local\pip"),
    (Join-Path $env:USERPROFILE "AppData\Roaming\npm"),
    # Common project folders
    (Join-Path $env:USERPROFILE "source"),
    (Join-Path $env:USERPROFILE "projects"),
    (Join-Path $env:USERPROFILE "repos"),
    (Join-Path $env:USERPROFILE "dev"),
    (Join-Path $env:USERPROFILE "code"),
    (Join-Path $env:USERPROFILE "Documents\GitHub"),
    # Temp / build
    $env:TEMP
)

foreach ($path in $defenderExclusions) {
    try {
        Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
        Write-Log "Defender exclusion: $path" "OK"
    } catch {
        Write-Log "Defender exclusion failed for $path - $_" "WARN"
    }
}

# Exclude common dev processes from real-time scanning
$defenderProcessExclusions = @(
    "node.exe", "npm.cmd", "npx.cmd",
    "python.exe", "pip.exe",
    "cargo.exe", "rustc.exe", "rust-analyzer.exe",
    "go.exe", "gopls.exe",
    "cl.exe", "link.exe", "msbuild.exe",
    "gcc.exe", "g++.exe", "make.exe", "cmake.exe", "ninja.exe",
    "java.exe", "javac.exe", "gradle.exe", "mvn.cmd",
    "docker.exe", "dockerd.exe",
    "git.exe", "ssh.exe",
    "code.exe", "devenv.exe",
    "dotnet.exe",
    "ruby.exe", "perl.exe",
    "deno.exe", "bun.exe"
)

foreach ($proc in $defenderProcessExclusions) {
    try {
        Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
    } catch {}
}
Write-Log "Defender process exclusions added ($($defenderProcessExclusions.Count) processes)" "OK"

# Exclude common dev file extensions from scanning
$defenderExtExclusions = @(
    ".obj", ".o", ".a", ".lib", ".dll", ".so", ".dylib",
    ".pdb", ".ilk", ".exp",
    ".pyc", ".pyo", ".class",
    ".d", ".rlib", ".rmeta"
)

foreach ($ext in $defenderExtExclusions) {
    try {
        Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
    } catch {}
}
Write-Log "Defender extension exclusions added ($($defenderExtExclusions.Count) extensions)" "OK"

Write-Log "Defender exclusions configured - builds will be significantly faster" "OK"

# ============================================================================
# npm / pip Config
# ============================================================================
Write-Log "Configuring npm and pip defaults..."

# npm init defaults
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    npm config set init-author-name "supermarsx" 2>&1 | Out-Null
    npm config set init-license "MIT" 2>&1 | Out-Null
    npm config set init-version "0.1.0" 2>&1 | Out-Null
    npm config set fund false 2>&1 | Out-Null
    npm config set audit false 2>&1 | Out-Null
    npm config set update-notifier false 2>&1 | Out-Null
    Write-Log "npm config set (author: supermarsx, license: MIT, no fund/audit nags)" "OK"
} else {
    Write-Log "npm not found - skipping npm config" "WARN"
}

# pip config
$pipConfigDir = Join-Path $env:APPDATA "pip"
if (-not (Test-Path $pipConfigDir)) { New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null }
$pipConfig = Join-Path $pipConfigDir "pip.ini"
$pipContent = @"
[global]
timeout = 60
disable-pip-version-check = true

[install]
no-warn-script-location = true
"@
Set-Content -Path $pipConfig -Value $pipContent -Encoding UTF8
Write-Log "pip config created (timeout 60s, no version nag)" "OK"

# ============================================================================
# KeePass / KeePassXC Dark Mode
# ============================================================================
Write-Log "Configuring KeePass dark mode..."

# KeePassXC: set dark theme via ini
$kpxcConfig = "$env:APPDATA\keepassxc\keepassxc.ini"
$kpxcDir = Split-Path $kpxcConfig
if (-not (Test-Path $kpxcDir)) { New-Item -ItemType Directory -Path $kpxcDir -Force | Out-Null }
$kpxcContent = @"
[General]
UseSystemAppearance=false

[GUI]
ApplicationTheme=dark
"@
if (-not (Test-Path $kpxcConfig)) {
    Set-Content -Path $kpxcConfig -Value $kpxcContent -Encoding UTF8
    Write-Log "KeePassXC dark theme configured" "OK"
} else {
    # Patch existing config
    $existing = Get-Content $kpxcConfig -Raw
    if ($existing -notmatch "ApplicationTheme") {
        Add-Content -Path $kpxcConfig -Value "`nApplicationTheme=dark"
    }
    Write-Log "KeePassXC dark theme patched" "OK"
}

# KeePass 2: install KeeTheme plugin for dark mode
$kp2Paths = @(
    "$env:ProgramFiles\KeePass Password Safe 2",
    "${env:ProgramFiles(x86)}\KeePass Password Safe 2"
)
foreach ($kp2Dir in $kp2Paths) {
    if (Test-Path $kp2Dir) {
        $pluginsDir = Join-Path $kp2Dir "Plugins"
        if (-not (Test-Path $pluginsDir)) { New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null }

        # Download KeeTheme plugin
        $keeThemePlgx = Join-Path $pluginsDir "KeeTheme.plgx"
        if (-not (Test-Path $keeThemePlgx)) {
            $keeThemeUrl = Get-GitHubReleaseUrl -Repo "xatupal/KeeTheme" -Pattern "KeeTheme\.plgx$"
            if ($keeThemeUrl) {
                try {
                    $ProgressPreference = 'SilentlyContinue'
                    Invoke-WebRequest -Uri $keeThemeUrl -OutFile $keeThemePlgx -UseBasicParsing
                    Write-Log "KeeTheme plugin installed" "OK"
                } catch {
                    Write-Log "KeeTheme download failed: $_" "WARN"
                }
            }
        }

        # Configure KeePass to use dark theme + follow Win11 dark mode
        $kp2Config = Join-Path $kp2Dir "KeePass.config.enforced.xml"
        $kp2Xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <Application>
        <Start>
            <CheckForUpdate>false</CheckForUpdate>
        </Start>
    </Application>
    <UI>
        <Hiding>
            <UnhideOnce>false</UnhideOnce>
        </Hiding>
    </UI>
    <Custom>
        <Item>
            <Key>KeeTheme.Enabled</Key>
            <Value>true</Value>
        </Item>
        <Item>
            <Key>KeeTheme.Name</Key>
            <Value>KeeThemeDark</Value>
        </Item>
    </Custom>
</Configuration>
"@
        Set-Content -Path $kp2Config -Value $kp2Xml -Encoding UTF8
        Write-Log "KeePass 2 dark theme (KeeTheme) configured" "OK"
        break
    }
}

Write-Log "Module 17 - VS Code Setup completed" "OK"

