#Requires -Version 5.1

param(
    [string]$ProjectName,
    [string]$ProjectPath,
    [string]$WslName,
    [string]$WslUser,
    [switch]$CreateNewWsl,
    [switch]$UseExistingWsl,
    [string]$Memory,
    [int]$Processors,
    [string]$Swap,
    [string]$Distribution,
    [string[]]$Packages,
    [string[]]$Templates,
    [string]$Preset,
    [hashtable]$Github,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\Catalog.ps1"
. "$PSScriptRoot\lib\Graph.ps1"

$defaults = Get-WslDefaults

if ($Preset) {
    $presetObj = Get-PresetById $Preset
    if (-not $presetObj) { throw "Preset introuvable : $Preset" }
    if (-not $Packages) { $Packages = @($presetObj.packages) }
    if (-not $Templates) { $Templates = @($presetObj.templates) }
    if (-not $Github -and $presetObj.github) {
        $Github = @{
            init          = [bool]$presetObj.github.init
            createRemote  = [string]$presetObj.github.createRemote
            visibility    = [string]$presetObj.github.visibility
        }
    }
}

if (-not $ProjectName) { throw "ProjectName requis" }
if (-not $Packages) { $Packages = @("base") }
if (-not $Templates) { $Templates = @() }

$slug = ConvertTo-ProjectSlug $ProjectName
if (-not $WslName) { $WslName = "wsl-$slug" }
if (-not $WslUser) { $WslUser = $env:USERNAME }

$createNew = $true
if ($UseExistingWsl) { $createNew = $false }
if ($CreateNewWsl) { $createNew = $true }

if (-not $Memory) { $Memory = [string]$defaults.memory }
if (-not $Processors) { $Processors = [int]$defaults.processors }
if (-not $Swap) { $Swap = [string]$defaults.swap }
if (-not $Distribution) { $Distribution = [string]$defaults.distribution }

if (-not $ProjectPath) {
    if ($Templates.Count -gt 0) {
        $tpl = Get-TemplateById $Templates[0]
        if ($tpl -and $tpl.defaultPath) {
            $ProjectPath = Expand-ProjectPath -Template $tpl.defaultPath -ProjectName $ProjectName -WslUser $WslUser
        }
    }
    if (-not $ProjectPath) {
        $ProjectPath = "/home/$WslUser/$ProjectName"
    }
}

$packageOptions = @{}
$templateOptions = @{}
if ($Preset) {
    $presetObj = Get-PresetById $Preset
    if ($presetObj.packageOptions) {
        $presetObj.packageOptions.PSObject.Properties | ForEach-Object {
            $h = @{}
            $_.Value.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
            $packageOptions[$_.Name] = $h
        }
    }
    if ($presetObj.templateOptions) {
        $presetObj.templateOptions.PSObject.Properties | ForEach-Object {
            $h = @{}
            $_.Value.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
            $templateOptions[$_.Name] = $h
        }
    }
}

$resolved = Resolve-FullSelection -PackageIds $Packages -TemplateIds $Templates `
    -PackageOptions $packageOptions -TemplateOptions $templateOptions

if (-not $resolved.Validation.Valid) {
    throw ($resolved.Validation.Errors -join "; ")
}

if (-not $Github) {
    $Github = @{
        init         = $true
        createRemote = "ask"
        visibility   = "private"
        userName     = $WslUser
        userEmail    = if ($WslUser) { "$WslUser@localhost" } else { "" }
    }
}

$plan = New-DeploymentPlanObject `
    -ProjectName $ProjectName `
    -ProjectPath $ProjectPath `
    -WslName $WslName `
    -WslUser $WslUser `
    -CreateNew $createNew `
    -Memory $Memory `
    -Processors $Processors `
    -Swap $Swap `
    -Distribution $Distribution `
    -PackageSelections $resolved.PackageSelections `
    -TemplateSelections $resolved.TemplateSelections `
    -Github $Github

if (-not $OutputPath) {
    $plansDir = Join-Path (Get-ProjectDeployRoot) "plans"
    $OutputPath = Join-Path $plansDir "$slug.plan.json"
}

Save-DeploymentPlan -Plan $plan -OutputPath $OutputPath
Write-Output $OutputPath
