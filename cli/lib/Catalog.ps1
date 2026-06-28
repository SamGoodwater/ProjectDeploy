#Requires -Version 5.1

function Get-ProjectDeployRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Get-CatalogRoot {
    return Join-Path (Get-ProjectDeployRoot) "catalog"
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Fichier JSON introuvable : $Path"
    }
    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Get-WslDefaults {
    $path = Join-Path (Get-CatalogRoot) "wsl\defaults.json"
    return Read-JsonFile $path
}

function Get-CatalogPackages {
    $dir = Join-Path (Get-CatalogRoot) "packages"
    $packages = @()
    Get-ChildItem -Path $dir -Filter "*.json" | Sort-Object Name | ForEach-Object {
        $packages += Read-JsonFile $_.FullName
    }
    return $packages
}

function Get-CatalogTemplates {
    $dir = Join-Path (Get-CatalogRoot) "templates"
    $templates = @()
    Get-ChildItem -Path $dir -Filter "*.json" | Sort-Object Name | ForEach-Object {
        $templates += Read-JsonFile $_.FullName
    }
    return $templates
}

function Get-CatalogPresets {
    $dir = Join-Path (Get-CatalogRoot) "presets"
    if (-not (Test-Path $dir)) { return @() }
    $presets = @()
    Get-ChildItem -Path $dir -Filter "*.json" | Sort-Object Name | ForEach-Object {
        $presets += Read-JsonFile $_.FullName
    }
    return $presets
}

function Get-PackageById {
    param([string]$Id)
    return (Get-CatalogPackages | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}

function Get-TemplateById {
    param([string]$Id)
    return (Get-CatalogTemplates | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}

function Get-PresetById {
    param([string]$Id)
    return (Get-CatalogPresets | Where-Object { $_.id -eq $Id } | Select-Object -First 1)
}

function ConvertTo-ProjectSlug {
    param([string]$Name)
    $slug = $Name.ToLower() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

function Expand-ProjectPath {
    param(
        [string]$Template,
        [string]$ProjectName,
        [string]$WslUser
    )
    $path = $Template -replace '\{name\}', $ProjectName
    if ($path -match '^~') {
        $linuxUser = if ($WslUser) { $WslUser } else { "user" }
        $path = $path -replace '^~', "/home/$linuxUser"
    }
    return $path
}

function New-DeploymentPlanObject {
    param(
        [string]$ProjectName,
        [string]$ProjectPath,
        [string]$WslName,
        [string]$WslUser,
        [bool]$CreateNew,
        [string]$Memory,
        [int]$Processors,
        [string]$Swap,
        [string]$Distribution,
        [array]$PackageSelections,
        [array]$TemplateSelections,
        [hashtable]$Github
    )

    $slug = ConvertTo-ProjectSlug $ProjectName
    $domain = $null
    foreach ($tpl in $TemplateSelections) {
        $def = Get-TemplateById $tpl.id
        if ($def -and $def.domain) {
            $domain = "$slug.local"
            break
        }
    }

    return [ordered]@{
        version   = 1
        project   = [ordered]@{
            name   = $ProjectName
            slug   = $slug
            path   = $ProjectPath
            domain = $domain
        }
        wsl       = [ordered]@{
            name           = $WslName
            user           = $WslUser
            createNew      = $CreateNew
            memory         = $Memory
            processors     = $Processors
            swap           = $Swap
            distribution   = $Distribution
        }
        packages  = $PackageSelections
        templates = $TemplateSelections
        github    = $Github
    }
}

function Save-DeploymentPlan {
    param(
        [object]$Plan,
        [string]$OutputPath
    )
    $dir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Plan | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    return $OutputPath
}

function Import-DeploymentPlan {
    param([string]$Path)
    return Read-JsonFile $Path
}
