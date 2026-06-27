#Requires -Version 5.1
<#
.SYNOPSIS
    Point d'entrée ProjectDeploy — vérifie l'environnement, installe si besoin, lance la GUI.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -CheckOnly

.EXAMPLE
    .\install.ps1 -BuildRelease

.EXAMPLE
    .\install.ps1 -Cli
#>

param(
    [switch]$CheckOnly,
    [switch]$BuildRelease,
    [switch]$SkipWsl,
    [switch]$Cli
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

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
