# Community Modules

Drop custom `.ps1` scripts in this directory to extend WinInit.

## Creating a Module

1. Create a `.ps1` file in this directory (or copy `_template.ps1` and rename it)
2. Start with a comment describing what it does:
   ```powershell
   # My Custom Module - Installs my favorite tools
   ```
3. Use WinInit helper functions from `lib/common.ps1`:
   - `Write-Log "message" "OK"` -- Log with status (OK, INFO, WARN, ERROR, DEBUG)
   - `Write-Section "Name"` -- Section header with spinner
   - `Install-App -Name "App" -WingetId "Publisher.App"` -- Install app via winget/choco/scoop
   - `Set-RegistrySafe -Path "HKCU:\..." -Name "Key" -Value 1 -Type DWord` -- Registry tweak
   - `Install-PortableBin -Name "tool" -Url "https://..." -ExeName "tool.exe"` -- Portable tool
   - `Get-GitHubReleaseUrl -Repo "owner/repo" -Pattern "*.zip"` -- Get latest GitHub release
   - `Start-Spinner "message"` / `Stop-Spinner` -- Progress spinner
4. Community modules run **after** all built-in modules (01-18)
5. Modules are sorted alphabetically by filename
6. Modules are validated for safety before execution

## Naming Convention

Use descriptive filenames. They will be sorted alphabetically:

```
my-dev-tools.ps1
setup-gaming.ps1
work-vpn-config.ps1
```

Prefix with numbers if ordering matters:

```
01-my-first-step.ps1
02-my-second-step.ps1
```

## Example

```powershell
# Install My Tools - Custom development environment additions

Write-Section "My Custom Tools"

Install-App -Name "Neovim" -WingetId "Neovim.Neovim" -ChocoId "neovim" -ScoopId "neovim"
Install-App -Name "Alacritty" -WingetId "Alacritty.Alacritty" -ScoopId "alacritty"

# Custom registry tweak
Set-RegistrySafe -Path "HKCU:\Console" -Name "FaceName" -Value "CaskaydiaCove Nerd Font" -Type String

Write-Log "Custom tools installed" "OK"
```

## Template

A starter template is available at `_template.ps1` in this directory. Copy it and modify to your needs.

## Safety

Community modules are scanned for dangerous operations before execution. The following patterns are blocked:

- **Disk operations:** `Format-Volume`, `Remove-Partition`, `Clear-Disk`, `Initialize-Disk`
- **System file deletion:** `Remove-Item -Recurse` targeting `C:\Windows`, `C:\Users`, or `C:\Program Files`
- **Remote code execution:** `Invoke-Expression` or `iex` with HTTP URLs
- **Insecure downloads:** `DownloadString` or `WebClient` with plain HTTP (HTTPS is allowed)
- **Boot tampering:** `bcdedit /deletevalue`
- **Encryption removal:** `Disable-BitLocker`

If your module is blocked, review the log output for details on which pattern was matched.

## Debugging

Run WinInit with verbose logging to see community module loading details:

```powershell
.\init.ps1 -DryRun  # Preview mode - shows what would run without changes
```

Check `wininit.log` for community module validation and execution logs.
