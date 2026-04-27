# ============================================================================
# WinInit DevScript: Version Bumper
# Computes and applies repository version metadata
# Usage:
#   .\devscripts\bump-version.ps1 -Next
#   .\devscripts\bump-version.ps1 -ApplyNext
#   .\devscripts\bump-version.ps1 -Version 26.1
# ============================================================================

[CmdletBinding(DefaultParameterSetName = "Apply")]
param(
    [Parameter(ParameterSetName = "Next")]
    [switch]$Next,

    [Parameter(ParameterSetName = "ApplyNext")]
    [switch]$ApplyNext,

    [Parameter(ParameterSetName = "Apply")]
    [string]$Version = "",

    [switch]$EnsureUniqueTag
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$versionFile = Join-Path $projectRoot "VERSION"
$readmeFile = Join-Path $projectRoot "readme.md"
$badgeDir = Join-Path $projectRoot ".github\badges"
$badgeFile = Join-Path $badgeDir "version.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Test-VersionFormat {
    param([string]$Value)

    return $Value -match '^\d{2}\.\d+$'
}

function Get-CurrentVersion {
    if (-not (Test-Path $versionFile)) {
        return ""
    }

    $currentVersion = (Get-Content $versionFile -Raw).Trim()
    if ($currentVersion -and -not (Test-VersionFormat $currentVersion)) {
        throw "VERSION must use YY.N format. Found: $currentVersion"
    }

    return $currentVersion
}

function Get-NextVersion {
    param([string]$CurrentVersion)

    $yy = (Get-Date).ToString("yy")
    if ($CurrentVersion -match '^(\d{2})\.(\d+)$' -and $Matches[1] -eq $yy) {
        return "$yy.$([int]$Matches[2] + 1)"
    }

    return "$yy.1"
}

function Resolve-UniqueVersion {
    param([string]$Candidate)

    if (-not $EnsureUniqueTag) {
        return $Candidate
    }

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        return $Candidate
    }

    & git fetch --tags --quiet *> $null

    $uniqueVersion = $Candidate
    while ($true) {
        $matchingTag = & git tag --list $uniqueVersion
        if (-not $matchingTag) {
            return $uniqueVersion
        }

        $parts = $uniqueVersion -split '\.'
        $uniqueVersion = "$($parts[0]).$([int]$parts[1] + 1)"
    }
}

function Write-VersionFiles {
    param([string]$Value)

    if (-not (Test-VersionFormat $Value)) {
        throw "Version must use YY.N format. Found: $Value"
    }

    if (-not (Test-Path $badgeDir)) {
        New-Item -ItemType Directory -Path $badgeDir -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($versionFile, "$Value`n", $utf8NoBom)

    $badgeData = [ordered]@{
        schemaVersion = 1
        label         = "version"
        message       = $Value
        color         = "2f81f7"
    } | ConvertTo-Json

    [System.IO.File]::WriteAllText($badgeFile, "$badgeData`n", $utf8NoBom)

    if (-not (Test-Path $readmeFile)) {
        throw "README file not found: $readmeFile"
    }

    $readmeContent = [System.IO.File]::ReadAllText($readmeFile)
    $versionMarkerPattern = '<!-- version: \d{2}\.\d+ -->'
    if ($readmeContent -notmatch $versionMarkerPattern) {
        throw "README version marker not found."
    }

    $updatedReadme = $readmeContent -replace $versionMarkerPattern, "<!-- version: $Value -->"
    [System.IO.File]::WriteAllText($readmeFile, $updatedReadme, $utf8NoBom)
}

$currentVersion = Get-CurrentVersion
$targetVersion = ""

switch ($PSCmdlet.ParameterSetName) {
    "Next" {
        $targetVersion = Resolve-UniqueVersion (Get-NextVersion $currentVersion)
        break
    }
    "ApplyNext" {
        $targetVersion = Resolve-UniqueVersion (Get-NextVersion $currentVersion)
        Write-VersionFiles $targetVersion
        break
    }
    default {
        $targetVersion = if ($Version) { $Version } else { $currentVersion }
        if (-not $targetVersion) {
            throw "No version available. Provide -Version or create VERSION first."
        }
        Write-VersionFiles $targetVersion
        break
    }
}

Write-Output $targetVersion
