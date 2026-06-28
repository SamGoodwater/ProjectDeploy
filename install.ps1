#Requires -Version 5.1
<#
.SYNOPSIS
    Point d'entree ProjectDeploy - verifie l'environnement, installe si besoin, lance la GUI.
#>

param(
    [switch]$CheckOnly,
    [switch]$BuildRelease,
    [switch]$SkipWsl,
    [switch]$Cli
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

function Unblock-ProjectScripts {
    param([string]$Root)
    Get-ChildItem -Path $Root -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::Archive) {
            Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        }
    }
}

Unblock-ProjectScripts -Root $RepoRoot

if ((Get-Item -LiteralPath $PSCommandPath).Attributes -band [IO.FileAttributes]::Archive) {
    Unblock-File -LiteralPath $PSCommandPath
}

$setupScript = Join-Path $RepoRoot "windows\Setup-Environment.ps1"
if (-not (Test-Path $setupScript)) {
    throw "Script introuvable : $setupScript"
}

if ($Cli) {
    & "$RepoRoot\cli\deploy.ps1" @args
    exit $LASTEXITCODE
}

$setupParams = @{
    InstallMissing = -not $CheckOnly
    LaunchGui      = -not $CheckOnly
}
if ($BuildRelease) { $setupParams["BuildRelease"] = $true }
if ($SkipWsl) { $setupParams["SkipWsl"] = $true }

& $setupScript @setupParams
exit $LASTEXITCODE
