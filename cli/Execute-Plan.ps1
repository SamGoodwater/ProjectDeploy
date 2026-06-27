#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$PlanFile,

    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

. "$PSScriptRoot\lib\Catalog.ps1"
. "$PSScriptRoot\lib\Wsl.ps1"

if (-not (Test-Path $PlanFile)) {
    throw "Plan introuvable : $PlanFile"
}

$plan = Import-DeploymentPlan $PlanFile

Write-Host ""
Write-Host "ProjectDeploy — Exécution du plan" -ForegroundColor Cyan
Write-Host "  Projet : $($plan.project.name)" -ForegroundColor Gray
Write-Host "  WSL    : $($plan.wsl.name)" -ForegroundColor Gray
Write-Host "  Chemin : $($plan.project.path)" -ForegroundColor Gray
Write-Host ""

# Phase 1 : .wslconfig
Write-Host "→ Configuration WSL globale..." -ForegroundColor Cyan
& "$RepoRoot\windows\Set-WslConfig.ps1" `
    -Memory $plan.wsl.memory `
    -Processors $plan.wsl.processors `
    -Swap $plan.wsl.swap

# Phase 2 : Création WSL
$wslName = $plan.wsl.name
if ($plan.wsl.createNew) {
    if (-not (Test-Administrator)) {
        Write-Host "! Création WSL recommandée en administrateur" -ForegroundColor Yellow
    }
    & "$RepoRoot\windows\New-WslInstance.ps1" -WslName $wslName -Distribution $plan.wsl.distribution -SkipIfExists
} else {
    Write-Host "→ Utilisation de la WSL existante" -ForegroundColor Cyan
    if (-not (Test-WslInstance -Name $wslName)) {
        $names = Get-WslInstanceNames
        if ($names.Count -gt 0) {
            $wslName = $names[0]
            Write-Host "  Instance utilisée : $wslName" -ForegroundColor Gray
        } else {
            throw "Aucune instance WSL trouvée"
        }
    }
}

# Phase 3 : Copier plan et lancer orchestrateur Linux
Write-Host "→ Bootstrap Linux..." -ForegroundColor Cyan
$wslPlanPath = Copy-PlanToWsl -WslName $wslName -PlanFile (Resolve-Path $PlanFile).Path

$exitCode = Invoke-WslOrchestrator -WslName $wslName -RepoRoot $RepoRoot -PlanPathInWsl $wslPlanPath -NonInteractive:$NonInteractive
if ($exitCode -ne 0) {
    throw "Le bootstrap a échoué (code $exitCode). Consultez /var/log/project-deploy/setup.log"
}

# Phase 4 : Hosts Windows
if ($plan.project.domain) {
    $domain = $plan.project.domain
    if (Test-Administrator) {
        & "$RepoRoot\windows\Set-WindowsHosts.ps1" -Domain $domain
    } else {
        Write-Host "! Ajoutez manuellement dans hosts :" -ForegroundColor Yellow
        Write-Host "  127.0.0.1  $domain" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "Installation terminée" -ForegroundColor Green
Write-Host "  wsl -d $wslName" -ForegroundColor White
Write-Host "  Chemin : $($plan.project.path)" -ForegroundColor White
if ($plan.project.domain) {
    Write-Host "  URL    : http://$($plan.project.domain)" -ForegroundColor White
}
Write-Host ""
