# Module: Community Template
# Description: [Replace with what this module does]
# Author: [Your name]
# Date: [Date created]

Write-Section "My Custom Module" "Description of what this module does"

# ============================================================================
# Your customizations here
# ============================================================================

# --- Example: Install apps ---
# Install-App -Name "AppName" -WingetId "Publisher.AppId"
# Install-App -Name "AppName" -WingetId "Publisher.AppId" -ChocoId "appname" -ScoopId "appname"

# --- Example: Registry tweak ---
# Set-RegistrySafe -Path "HKCU:\Software\MyKey" -Name "Setting" -Value 1 -Type DWord

# --- Example: Download portable tool ---
# Install-PortableBin -Name "tool" -Url "https://github.com/owner/repo/releases/latest/download/tool.zip" -ExeName "tool.exe"

# --- Example: Download from GitHub releases ---
# $url = Get-GitHubReleaseUrl -Repo "owner/repo" -Pattern "*windows*amd64*.zip"
# Install-PortableBin -Name "tool" -Url $url -ExeName "tool.exe"

# --- Example: Run a command ---
# Write-Log "Configuring something..."
# $result = Invoke-Silent "some-command" "--flag --value"
# if ($result.ExitCode -eq 0) {
#     Write-Log "Configuration successful" "OK"
# } else {
#     Write-Log "Configuration failed" "WARN"
# }

# --- Example: Conditional logic ---
# if (Get-Command "some-tool" -ErrorAction SilentlyContinue) {
#     Write-Log "some-tool is already installed" "OK"
# } else {
#     Install-App -Name "Some Tool" -WingetId "Publisher.SomeTool"
# }

Write-Log "Community module completed" "OK"
