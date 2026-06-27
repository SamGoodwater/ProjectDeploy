#Requires -Version 5.1
<#
.SYNOPSIS
    WSL Project Init — Point d'entrée Windows

.DESCRIPTION
    Crée une instance WSL Debian, configure .wslconfig, lance le bootstrap Linux
    et prépare un projet web (Apache/PHP/Laravel) ou Python (FastAPI/Django).

.EXAMPLE
    .\install.ps1
    # Mode interactif complet

.EXAMPLE
    .\install.ps1 -ProjectName "mon-api" -ProjectType python -Profile python-fastapi -NonInteractive

.EXAMPLE
    .\install.ps1 -UseExistingWsl -ProjectName "mon-site" -Profile web-laravel
    # Utilise la WSL courante sans en créer une nouvelle
#>

param(
    [string]$ProjectName,
    [ValidateSet("web", "python", "")]
    [string]$ProjectType = "",
    [string]$Profile,
    [string]$ProjectPath,
    [string]$WslUser,
    [string]$WslName,
    [switch]$NonInteractive,
    [switch]$UseExistingWsl,
    [switch]$SkipWslCreation,
    [string]$Memory = "8GB",
    [string]$Processors = "4",
    [string]$Swap = "4GB"
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

# --- Fonctions utilitaires ---

function Write-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       WSL Project Init — Install         ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 1
    )
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  $($i + 1)) $($Options[$i])"
    }
    $choice = Read-Host "Choix [$Default]"
    if (-not $choice) { $choice = $Default }
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $Options.Count) { return $Options[$idx] }
    return $Options[$Default - 1]
}

function Get-Slug {
    param([string]$Name)
    return ($Name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Collecte interactive ---

Write-Banner

if (-not $NonInteractive) {
    if (-not $Profile) {
        $useProfile = Read-Host "Utiliser un profil prédéfini ? [web-laravel/web-vanilla/python-fastapi/custom] (Entrée = custom)"
        if ($useProfile -and $useProfile -ne "custom") {
            $Profile = $useProfile
        }
    }

    if (-not $ProjectName) {
        $ProjectName = Read-Host "Nom du projet [mon-projet]"
        if (-not $ProjectName) { $ProjectName = "mon-projet" }
    }

    if (-not $ProjectType) {
        $ProjectType = Read-Choice "Type de projet :" @("web", "python")
    }

    if (-not $UseExistingWsl -and -not $SkipWslCreation) {
        $createWsl = Read-Host "Créer une nouvelle instance WSL ? [O/n]"
        if ($createWsl -eq "n" -or $createWsl -eq "N") {
            $UseExistingWsl = $true
        }
    }
}

$ProjectSlug = Get-Slug $ProjectName
if (-not $WslName) { $WslName = "wsl-$ProjectSlug" }

if (-not $ProjectPath) {
    switch ($ProjectType) {
        "web"    { $ProjectPath = "/var/www/$ProjectName" }
        "python" { $ProjectPath = "~/$ProjectName" }
    }
}

Write-Host ""
Write-Host "Configuration :" -ForegroundColor Cyan
Write-Host "  Projet    : $ProjectName"
Write-Host "  Type      : $ProjectType"
Write-Host "  Chemin    : $ProjectPath"
Write-Host "  WSL       : $WslName"
if ($Profile) { Write-Host "  Profil    : $Profile" }
Write-Host ""

if (-not $NonInteractive) {
    $confirm = Read-Host "Continuer ? [O/n]"
    if ($confirm -eq "n" -or $confirm -eq "N") { exit 0 }
}

# --- Étape 1 : .wslconfig ---

Write-Host "→ Configuration WSL globale..." -ForegroundColor Cyan
& "$RepoRoot\windows\Set-WslConfig.ps1" -Memory $Memory -Processors $Processors -Swap $Swap

# --- Étape 2 : Création WSL ---

if (-not $UseExistingWsl -and -not $SkipWslCreation) {
    if (-not (Test-Administrator)) {
        Write-Host "! Création WSL recommandée en administrateur. Tentative sans élévation..." -ForegroundColor Yellow
    }
    & "$RepoRoot\windows\New-WslInstance.ps1" -WslName $WslName -SkipIfExists
} else {
    Write-Host "→ Utilisation de la WSL existante" -ForegroundColor Cyan
    $WslName = (wsl --list --quiet 2>$null | Select-Object -First 1).Trim()
    if (-not $WslName) { throw "Aucune instance WSL trouvée." }
    Write-Host "  Instance : $WslName" -ForegroundColor Gray
}

# --- Étape 3 : Bootstrap Linux ---

$bootstrapParams = @{
    WslName          = $WslName
    RepoRoot         = $RepoRoot
    ProjectName      = $ProjectName
    ProjectType      = $ProjectType
    ProjectPath      = $ProjectPath
    WslUser          = $WslUser
    UseExistingWsl   = $true
}

if ($Profile)         { $bootstrapParams["Profile"] = $Profile }
if ($NonInteractive)  { $bootstrapParams["NonInteractive"] = $true }
if ($UseExistingWsl)  { $bootstrapParams["SkipUserSetup"] = $false }

& "$RepoRoot\windows\Invoke-WslBootstrap.ps1" @bootstrapParams

# --- Étape 4 : Hosts Windows (web) ---

if ($ProjectType -eq "web") {
    $Domain = "$ProjectSlug.local"
    if (Test-Administrator) {
        & "$RepoRoot\windows\Set-WindowsHosts.ps1" -Domain $Domain
    } else {
        Write-Host "! Ajoutez manuellement dans C:\Windows\System32\drivers\etc\hosts :" -ForegroundColor Yellow
        Write-Host "  127.0.0.1  $Domain" -ForegroundColor White
    }
}

# --- Récapitulatif ---

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            Installation terminée           ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Entrer dans la WSL :  wsl -d $WslName" -ForegroundColor White
Write-Host "  Chemin projet     :  $ProjectPath" -ForegroundColor White
if ($ProjectType -eq "web") {
    Write-Host "  URL locale        :  http://${ProjectSlug}.local" -ForegroundColor White
}
Write-Host "  Explorateur       :  \\wsl$\$WslName$(($ProjectPath -replace '~', ''))" -ForegroundColor White
Write-Host ""
Write-Host "  N'oubliez pas : wsl --shutdown (puis relancer) si systemd vient d'être activé." -ForegroundColor Yellow
Write-Host ""
