<h1 align="center">WinInit</h1>
<p align="center">
  <a href="https://github.com/supermarsx/wininit/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/supermarsx/wininit/ci.yml?branch=main&style=flat-square&label=CI&logo=githubactions&logoColor=white" alt="CI status">
  </a>
  <a href="https://github.com/supermarsx/wininit">
    <img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsupermarsx%2Fwininit%2Fmain%2F.github%2Fbadges%2Fversion.json&style=flat-square" alt="Version badge">
  </a>
  <a href="https://learn.microsoft.com/powershell/">
    <img src="https://img.shields.io/badge/built%20with-PowerShell-5391FE?style=flat-square&logo=powershell&logoColor=white" alt="Built with PowerShell">
  </a>
  <a href="https://github.com/supermarsx/wininit/blob/main/license.md">
    <img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT License">
  </a>
</p>
<p align="center">
  <strong>Windows Initialization & Customization Script</strong><br>
  18 Modules | Full Automation | Zero Interaction
</p>
<!-- version: 26.2 -->
<p align="center">
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#features">Features</a> &bull;
  <a href="#modules">Modules</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#profiles">Profiles</a> &bull;
  <a href="#usage">Usage</a>
</p>

## Quick Start

**One-liner** (paste into an elevated PowerShell window):

```powershell
irm https://raw.githubusercontent.com/supermarsx/wininit/main/install.ps1 | iex
```

Or clone and run manually:

```powershell
git clone https://github.com/supermarsx/wininit.git
cd wininit
.\launch.bat
```

## Features

- **53+ applications** installed automatically via winget, Chocolatey, and Scoop
- **70+ UWP bloatware packages** removed (including promoted third-party apps)
- **500+ registry tweaks** across privacy, performance, UX, and security
- **30+ junk services** disabled (telemetry, Fax, Xbox, Retail Demo, etc.)
- **20+ telemetry domains** blocked via hosts file (optional)
- **18 modular stages** -- skip any module, run any subset
- **6 built-in profiles** -- developer, security, minimal, creative, office, full
- **TOML configuration** -- fine-grained control without editing scripts
- **Automatic version bumping** -- CI stamps `VERSION`, the release badge, and this README from one script
- **Uptime-safe Windows Update defaults** -- notify/manual installs, no forced restart deadlines, feature-release pinning
- **Checkpoint/Resume** -- survives reboots and Ctrl+C interruptions
- **Full rollback** -- every change is recorded; `undo.ps1` reverts them
- **Risk indicators** -- every tweak tagged [S]afe, [M]oderate, or [A]ggressive
- **Progress dashboard** -- weighted ETA, per-module timing, error tracking
- **Dry-run mode** -- preview all changes without touching the system
- **Community modules** -- drop custom `.ps1` scripts into `modules/community/`
- **JUnit XML test output** -- CI-ready test suite with 200+ assertions
- **Zero interaction** -- runs fully unattended from start to finish

## Modules

| #  | Module                | Description |
|----|----------------------|-------------|
| 01 | Package Managers      | Installs and configures winget, Scoop, and Chocolatey |
| 02 | Applications          | 53+ apps: browsers, editors, IDEs, media, utilities, dev toolchains |
| 03 | Desktop Environment   | Dark mode, taskbar cleanup, Explorer tweaks, wallpaper, file associations |
| 04 | OneDrive Removal      | Complete OneDrive uninstall, folder cleanup, Explorer sidebar removal |
| 05 | Performance           | Disables SysMain, Game Bar, tips, animations; enables hardware scheduling |
| 06 | Debloat               | Removes 70+ pre-installed UWP apps and prevents reinstallation |
| 07 | Privacy               | 40+ privacy tweaks: telemetry, ads, tracking, Cortana, Copilot, Recall |
| 08 | Quality of Life       | NumLock, locale, sticky keys, terminal defaults, keyboard layout |
| 09 | Services              | Disables 30+ unnecessary services (Fax, Xbox, Insider, biometrics) |
| 10 | Network Performance   | Nagle's algorithm, SSD trim, IRPStack, TCP/IP tuning |
| 11 | Visual UX             | Transparency, Start menu layout, icon spacing, font smoothing |
| 12 | Security Hardening    | SMBv1 removal, Hyper-V, Windows Sandbox, UTF-8, BitLocker readiness |
| 13 | Browser Extensions    | Pre-configures Firefox, Chrome, and Edge with privacy extensions |
| 14 | Dev Tools             | Node.js, Rust, Go, Python, CUDA, SQL tools, gRPC, Kubernetes, Docker |
| 15 | Portable Tools        | Downloads CLI tools to `C:\bin` and `C:\apps` (jq, fzf, ripgrep, etc.) |
| 16 | Unix Environment      | Cygwin, Perl, Python venv, Go workspace, Unix-style PATH |
| 17 | VS Code Setup         | Extensions, settings, Nerd Fonts, terminal theme, Oh My Posh |
| 18 | Final Config          | Uptime-safe Windows Update policy, System Restore point, cleanup, startup optimization |

## Configuration

WinInit reads `config.toml` in the project root. Every setting has a sensible default.

```toml
[general]
profile = "developer"       # developer | security | minimal | creative | office | full
dry_run = false
log_level = "INFO"          # DEBUG | INFO | WARN | ERROR

[modules]
# Set to false to skip a module
"01-PackageManagers" = true
"02-Applications" = true
"03-DesktopEnvironment" = true
"04-OneDriveRemoval" = true
"05-Performance" = true
"06-Debloat" = true
"07-Privacy" = true
"08-QualityOfLife" = true
"09-Services" = true
"10-NetworkPerformance" = true
"11-VisualUX" = true
"12-SecurityHardening" = true
"13-BrowserExtensions" = true
"14-DevTools" = true
"15-PortableTools" = true
"16-UnixEnvironment" = true
"17-VSCodeSetup" = true
"18-FinalConfig" = true

[apps]
skip = []                   # Winget IDs to skip: ["Blender.Blender", "OBSProject.OBSStudio"]

[privacy]
level = "strict"            # standard | strict | paranoid
block_telemetry_hosts = false

[updates]
# Windows Update policy: "notify" = AUOptions 2, "auto_download" = AUOptions 3
windows_update_install_mode = "notify"
pin_current_feature_release = true
target_release_version = ""            # Empty = pin to the current DisplayVersion

# Optional package-maintenance task for update.ps1
enable_scheduled_updates = false
update_interval_days = 7
scheduled_update_time = "4:00AM"
```

`[updates]` controls two different things: Windows Update policy for the OS itself, and the optional scheduled task that runs `update.ps1` for package-manager maintenance. The default profile favors uptime on long-running boxes: no forced restart deadlines, no scheduled OS install window, and no automatic WinInit update task unless you opt in.

**Priority order:** CLI flags > `config.toml` > profile defaults > built-in defaults.

## Profiles

Profiles are JSON files in the `profiles/` directory. Each one enables or disables modules and sets a privacy level.

| Profile      | Description                                        | Modules Enabled | Privacy Level |
|-------------|---------------------------------------------------|-----------------|---------------|
| `full`       | Everything enabled -- all modules, all apps         | 18/18           | strict        |
| `developer`  | Full dev environment with all toolchains            | 18/18           | strict        |
| `security`   | Pentesting and hardening with maximum privacy       | 17/18           | paranoid      |
| `creative`   | Design and media: Blender, Krita, OBS              | 13/18           | standard      |
| `office`     | Productivity: browsers, office tools, essentials    | 13/18           | standard      |
| `minimal`    | Lightweight: package managers, debloat, privacy     | 6/18            | standard      |

Use a profile via CLI or config:

```powershell
.\init.ps1 -Profile minimal
```

Or set it in `config.toml`:

```toml
[general]
profile = "security"
```

## Usage

```powershell
# Full run using config.toml settings
.\init.ps1

# Use a specific profile
.\init.ps1 -Profile minimal

# Preview all changes without modifying the system
.\init.ps1 -DryRun

# Skip specific modules by number
.\init.ps1 -SkipModules 14,16

# Run only specific modules
.\init.ps1 -OnlyModules 01,06,07

# Resume after interruption or reboot
.\init.ps1 -Resume

# Update mode -- just upgrade all installed packages
.\init.ps1 -Update

# Manual app updates
.\update.ps1

# Preview what undo would revert
.\undo.ps1 -DryRun

# Revert all recorded changes
.\undo.ps1

# Revert only registry changes
.\undo.ps1 -OnlyTypes registry

# Show help
.\init.ps1 -Help
```

## Safety Indicators

Every tweak is tagged with a risk level so you know exactly what is happening:

| Tag   | Level      | Meaning                                          |
|-------|-----------|--------------------------------------------------|
| `[S]` | Safe       | Cosmetic or easily reversible (dark mode, icons)  |
| `[M]` | Moderate   | Functional change that may affect features        |
| `[A]` | Aggressive | Disables security features or modifies kernel-level settings |

The final summary shows a breakdown:

```
  --- Risk Summary ---
    Total tweaks applied: 147
    [S] Safe       (cosmetic / reversible):        112
    [M] Moderate   (functional / feature changes):  28
    [A] Aggressive (security / kernel-level):         7
```

## Reboot Resilience

WinInit saves a checkpoint after each module completes. If the system reboots (e.g., after enabling Hyper-V) or the script is interrupted:

1. A `checkpoint.json` file records the last completed module
2. A `RunOnce` registry key is set to resume after reboot
3. Running `.\init.ps1 -Resume` picks up where it left off

The checkpoint includes the module index, timestamp, username, and any extra state needed for continuation.

## Undo / Rollback

Every change WinInit makes is recorded in `rollback.json`. The standalone `undo.ps1` script can revert them:

```powershell
# See what would be reverted
.\undo.ps1 -DryRun

# Revert everything
.\undo.ps1

# Revert only specific types
.\undo.ps1 -OnlyTypes registry
.\undo.ps1 -OnlyTypes service
```

Supported rollback types:
- **Registry** -- restores previous values or removes keys that were created
- **Services** -- restores original startup types and running states
- **Apps** -- notes which apps were installed (manual removal guidance)
- **Features** -- notes which Windows features were enabled/disabled

`undo.ps1` is fully self-contained and does not depend on `lib/common.ps1`.

## Community Modules

Extend WinInit with your own scripts. Drop `.ps1` files into `modules/community/`:

```powershell
# modules/community/my-tools.ps1
# Install My Tools - Custom development additions

Write-Section "My Custom Tools"

Install-App -Name "Neovim" -WingetId "Neovim.Neovim" -ChocoId "neovim" -ScoopId "neovim"
Install-App -Name "Alacritty" -WingetId "Alacritty.Alacritty" -ScoopId "alacritty"

Write-Log "Custom tools installed" "OK"
```

Community modules:
- Run **after** all 18 built-in modules
- Are scanned for dangerous operations before execution (disk formatting, system file deletion, insecure downloads are blocked)
- Have access to all WinInit helper functions (`Write-Log`, `Install-App`, `Set-RegistrySafe`, etc.)
- Are sorted alphabetically by filename

See [`modules/community/README.md`](modules/community/README.md) for the full guide and a template.

## What Gets Installed

<details>
<summary><strong>53+ applications by category (click to expand)</strong></summary>

**Browsers**
- Google Chrome, Mozilla Firefox, Ungoogled Chromium

**Communication**
- WhatsApp, Telegram

**Development - Editors and IDEs**
- Visual Studio Code, Visual Studio 2026 Community, Android Studio

**Development - Toolchains**
- VS Build Tools (MSVC, ATL, MFC, Clang), CMake, Ninja, LLVM

**Development - Languages and Runtimes**
- Node.js (LTS), Rust (rustup), Go, Python 3, .NET SDK

**Development - Database**
- SQL Server tools, DBeaver, Redis, PostgreSQL client

**Development - Containers and Cloud**
- Docker Desktop, Kubernetes (kubectl, helm, k9s), Terraform

**Media and Creative**
- Blender, Krita, OBS Studio, GIMP, Inkscape, Audacity

**Utilities**
- 7-Zip, Everything, KeePassXC, WinSCP, PuTTY, WinMerge

**System Tools**
- Process Explorer, Autoruns, HWiNFO, CrystalDiskInfo, TreeSize

**Networking**
- Wireshark, Nmap, WireGuard, Tailscale

**Portable CLI Tools** (in `C:\bin`)
- jq, fzf, ripgrep, fd, bat, delta, eza, zoxide, duf, glow, hexyl, hyperfine, tokei, bottom, procs, sd, choose, xh, doggo, bandwhich

</details>

## Privacy and Security

**Module 07 (Privacy)** applies 40+ tweaks across these categories:

- Wi-Fi Sense, clipboard cloud sync, Timeline
- Windows telemetry (AllowTelemetry=0, DiagTrack disabled)
- Advertising ID, ad tracking, location, sensors
- Camera and microphone app defaults (set to Deny)
- Inking, typing, and handwriting data collection
- Cortana, web search, Connected Search
- Windows Copilot, Windows Recall (AI features)
- Error Reporting (WerSvc disabled)
- Feedback notifications and frequency
- Tailored experiences, tips, Spotlight
- Optional: 20+ telemetry domains blocked via hosts file

**Module 12 (Security Hardening)** enables:

- SMBv1 protocol removal
- Hyper-V and Windows Sandbox
- Windows Subsystem for Linux (WSL2)
- System-wide UTF-8 encoding
- BitLocker readiness checks
- Credential Guard configuration

## Comparison

| Feature                    | WinInit | WinUtil | Win11Debloat | Sophia Script |
|---------------------------|---------|---------|-------------|---------------|
| Fully unattended           | Yes     | No (GUI)| Partial     | No (prompts)  |
| App installation (50+)     | Yes     | Yes     | No          | No            |
| Dev toolchain setup        | Yes     | No      | No          | No            |
| TOML config file           | Yes     | No      | No          | No            |
| Profile system             | Yes     | No      | No          | Yes           |
| Checkpoint/resume          | Yes     | No      | No          | No            |
| Full rollback (undo.ps1)   | Yes     | No      | No          | Partial       |
| Risk-level indicators      | Yes     | No      | No          | No            |
| Progress dashboard + ETA   | Yes     | Yes     | No          | No            |
| Community modules          | Yes     | No      | No          | No            |
| Portable CLI tools         | Yes     | No      | No          | No            |
| JUnit test output          | Yes     | No      | No          | No            |

## Running Tests

WinInit includes a comprehensive test suite with 200+ assertions:

```powershell
# Run all test files
.\tests\Run-AllTests.ps1

# Run with JUnit XML output (for CI)
.\tests\Run-AllTests.ps1 -JUnit results.xml

# Run a specific test file
.\tests\Test-Config.ps1
.\tests\Test-Privacy.ps1 -Suite hosts

# Dry-run mode (skip tests requiring admin)
.\tests\Run-AllTests.ps1 -DryRun
```

Test files:
- `Test-Common.ps1` -- 49 functions in `lib/common.ps1`
- `Test-Init.ps1` -- Preflight logic and cross-module consistency
- `Test-Modules.ps1` -- All 18 module files: structure, syntax, dependencies
- `Test-Config.ps1` -- TOML parser, profiles, CLI flag merging
- `Test-Infrastructure.ps1` -- Checkpoint, rollback, safety, dashboard systems
- `Test-Privacy.ps1` -- Privacy module: categories, registry paths, risk levels

CI integration: the test runner returns a non-zero exit code on failure and supports `-JUnit` for XML report generation. A GitHub Actions workflow can run `.\tests\Run-AllTests.ps1 -JUnit results.xml -DryRun` on every push.

## Requirements

| Requirement       | Details                                                    |
|------------------|------------------------------------------------------------|
| **OS**            | Windows 10 version 2004+ (Build 19041) or Windows 11      |
| **Privileges**    | Administrator (elevated PowerShell)                        |
| **PowerShell**    | 5.1+ (ships with Windows 10/11)                            |
| **Disk Space**    | 10 GB+ free on the system drive                            |
| **Internet**      | Required for downloads (winget, Chocolatey, GitHub, etc.)  |
| **Architecture**  | x64 (AMD64) or ARM64                                       |

## Project Structure

```
wininit/
  init.ps1              Main orchestrator script
  launch.bat            Elevated launcher (right-click > Run as Admin)
  config.toml           User configuration (TOML format)
  undo.ps1              Standalone rollback script
  install.ps1           Quick installer (one-liner bootstrap)
  lib/
    common.ps1          Shared library (49 functions)
    safety.ps1          Risk level tagging system
    checkpoint.ps1      Checkpoint/resume system
    rollback.ps1        Change recording for undo
    dashboard.ps1       Progress dashboard and ETA
    community.ps1       Community module loader
  modules/
    01-PackageManagers.ps1 ... 18-FinalConfig.ps1
    community/          Drop custom modules here
  profiles/
    developer.json, security.json, minimal.json,
    creative.json, office.json, full.json
  tests/
    Run-AllTests.ps1    Test runner (discovers Test-*.ps1)
    Test-Common.ps1     Test-Init.ps1  Test-Modules.ps1
    Test-Config.ps1     Test-Infrastructure.ps1  Test-Privacy.ps1
```

## License

Released under the MIT License. See [license.md](license.md) for details.
