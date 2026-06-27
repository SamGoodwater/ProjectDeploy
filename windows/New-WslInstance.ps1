#Requires -Version 5.1
<#
.SYNOPSIS
    Crée une nouvelle instance WSL Debian pour un projet.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WslName,

    [string]$Distribution = "Debian",

    [switch]$SkipIfExists
)

$ErrorActionPreference = "Stop"

function Test-WslInstance {
    param([string]$Name)
    $list = wsl --list --quiet 2>$null
    return ($list -match [regex]::Escape($Name))
}

Write-Host "→ Vérification WSL..." -ForegroundColor Cyan
wsl --update 2>$null | Out-Null

if (Test-WslInstance -Name $WslName) {
    if ($SkipIfExists) {
        Write-Host "✓ Instance WSL '$WslName' existe déjà — reprise" -ForegroundColor Yellow
        return
    }
    throw "L'instance WSL '$WslName' existe déjà. Utilisez -SkipIfExists ou choisissez un autre nom."
}

Write-Host "→ Création de l'instance WSL '$WslName' ($Distribution)..." -ForegroundColor Cyan

# Création avec nom personnalisé
wsl --install -d $Distribution --name $WslName --no-launch

if ($LASTEXITCODE -ne 0) {
    # Fallback si --name non supporté (anciennes versions)
    Write-Host "! Fallback : installation sans --name" -ForegroundColor Yellow
    wsl --install -d $Distribution --no-launch
}

# Attendre que WSL soit disponible
$maxRetries = 30
for ($i = 1; $i -le $maxRetries; $i++) {
    Start-Sleep -Seconds 2
    $status = wsl --status 2>$null
    if ($LASTEXITCODE -eq 0) {
        break
    }
    Write-Host "  Attente WSL ($i/$maxRetries)..." -ForegroundColor Gray
}

Write-Host "✓ Instance WSL '$WslName' créée" -ForegroundColor Green
