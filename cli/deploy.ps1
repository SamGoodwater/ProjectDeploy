#Requires -Version 5.1
<#
.SYNOPSIS
    Point d'entrée CLI ProjectDeploy v2
#>

param(
    [string]$ProjectName,
    [string]$ProjectPath,
    [string]$WslName,
    [string]$WslUser,
    [string]$Preset,
    [string[]]$Packages,
    [string[]]$Templates,
    [string]$PlanFile,
    [switch]$NonInteractive,
    [switch]$UseExistingWsl,
    [switch]$BuildOnly,
    [string]$Memory = "",
    [string]$Processors = "",
    [string]$Swap = ""
)

$ErrorActionPreference = "Stop"
$CliRoot = $PSScriptRoot

if ((Get-Item -LiteralPath $PSCommandPath).Attributes -band [IO.FileAttributes]::Archive) {
    Unblock-File -LiteralPath $PSCommandPath
}

. "$CliRoot\lib\Catalog.ps1"
. "$CliRoot\lib\Graph.ps1"

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 1
    )
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i])
    }
    $choice = Read-Host ("Choix [{0}]" -f $Default)
    if (-not $choice) { $choice = $Default }
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $Options.Count) { return $Options[$idx] }
    return $Options[$Default - 1]
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $true)
    $hint = if ($Default) { "[O/n]" } else { "[o/N]" }
    $answer = Read-Host "$Question $hint"
    if (-not $answer) { return $Default }
    return ($answer -match '^[OoYy]')
}

Write-Host ""
Write-Host "ProjectDeploy v2 — CLI" -ForegroundColor Cyan
Write-Host ""

if ($PlanFile) {
    $executeParams = @{ PlanFile = $PlanFile }
    if ($NonInteractive) { $executeParams["NonInteractive"] = $true }
    & "$CliRoot\Execute-Plan.ps1" @executeParams
    exit $LASTEXITCODE
}

$defaults = Get-WslDefaults
$allPackages = Get-CatalogPackages | Where-Object { -not $_.hidden }
$allTemplates = Get-CatalogTemplates
$allPresets = Get-CatalogPresets

if (-not $NonInteractive) {
    if ($allPresets.Count -gt 0) {
        $presetNames = @("custom") + @($allPresets | ForEach-Object { $_.id })
        $picked = Read-Choice "Preset :" $presetNames 1
        if ($picked -ne "custom") { $Preset = $picked }
    }

    if (-not $ProjectName) {
        $ProjectName = Read-Host "Nom du projet [mon-projet]"
        if (-not $ProjectName) { $ProjectName = "mon-projet" }
    }

    if (-not $Preset) {
        Write-Host ""
        Write-Host "Paquets disponibles :" -ForegroundColor Cyan
        $selectedPackages = @("base")
        foreach ($pkg in $allPackages) {
            if ($pkg.id -eq "base") { continue }
            if (Read-YesNo "  Installer $($pkg.label) ?" $false) {
                $selectedPackages += $pkg.id
            }
        }
        $Packages = $selectedPackages

        Write-Host ""
        Write-Host "Templates disponibles :" -ForegroundColor Cyan
        $selectedTemplates = @()
        foreach ($tpl in $allTemplates) {
            if (Read-YesNo "  Initialiser $($tpl.label) ?" $false) {
                $selectedTemplates += $tpl.id
            }
        }
        $Templates = $selectedTemplates

        $UseExistingWsl = -not (Read-YesNo "Créer une nouvelle instance WSL ?" $true)
    }

    if (-not $WslName) {
        $slug = ConvertTo-ProjectSlug $ProjectName
        $defaultWsl = "wsl-$slug"
        $WslName = Read-Host "Nom WSL [$defaultWsl]"
        if (-not $WslName) { $WslName = $defaultWsl }
    }
}

if (-not $ProjectName) {
    throw "ProjectName requis (ou mode interactif)"
}

$buildParams = @{
    ProjectName = $ProjectName
}
if ($ProjectPath)     { $buildParams["ProjectPath"] = $ProjectPath }
if ($WslName)         { $buildParams["WslName"] = $WslName }
if ($WslUser)         { $buildParams["WslUser"] = $WslUser }
if ($Preset)          { $buildParams["Preset"] = $Preset }
if ($Packages)        { $buildParams["Packages"] = $Packages }
if ($Templates)       { $buildParams["Templates"] = $Templates }
if ($UseExistingWsl)  { $buildParams["UseExistingWsl"] = $true }
if ($Memory)           { $buildParams["Memory"] = $Memory }
if ($Processors)       { $buildParams["Processors"] = [int]$Processors }
if ($Swap)             { $buildParams["Swap"] = $Swap }

$planPath = & "$CliRoot\Build-Plan.ps1" @buildParams
Write-Host "Plan généré : $planPath" -ForegroundColor Green

if ($BuildOnly) {
    exit 0
}

if (-not $NonInteractive) {
    if (-not (Read-YesNo "Lancer l'installation ?" $true)) {
        exit 0
    }
}

$executeParams = @{ PlanFile = $planPath }
if ($NonInteractive) { $executeParams["NonInteractive"] = $true }
& "$CliRoot\Execute-Plan.ps1" @executeParams
