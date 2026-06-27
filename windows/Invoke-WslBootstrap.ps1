#Requires -Version 5.1
<#
.SYNOPSIS
    Lance bootstrap.sh dans une instance WSL.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WslName,

    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string]$ProjectName,
    [string]$ProjectType,
    [string]$Profile,
    [string]$ProjectPath,
    [string]$WslUser,
    [switch]$NonInteractive,
    [switch]$SkipUserSetup,
    [switch]$UseExistingWsl
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param([string]$WindowsPath)
    $result = wsl wslpath -a $WindowsPath 2>$null
    if ($LASTEXITCODE -eq 0) { return $result.Trim() }
    return $WindowsPath -replace '\\', '/' -replace '^([A-Z]):', { "/mnt/$($_.Groups[1].Value.ToLower())" }
}

$BootstrapScript = Join-Path $RepoRoot "linux\bootstrap.sh"
$WslRepoRoot = Convert-ToWslPath $RepoRoot

if (-not (Test-Path $BootstrapScript)) {
    throw "bootstrap.sh introuvable : $BootstrapScript"
}

# Construire les arguments
$args = @()
if ($ProjectName)      { $args += "--project"; $args += $ProjectName }
if ($ProjectType)      { $args += "--type"; $args += $ProjectType }
if ($Profile)          { $args += "--profile"; $args += $Profile }
if ($ProjectPath)      { $args += "--path"; $args += $ProjectPath }
if ($WslUser)          { $args += "--user"; $args += $WslUser }
if ($WslName)          { $args += "--wsl-name"; $args += $WslName }
if ($NonInteractive)   { $args += "--non-interactive" }
if ($SkipUserSetup)    { $args += "--skip-user-setup" }

$argString = ($args | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' '

Write-Host "→ Lancement du bootstrap dans WSL '$WslName'..." -ForegroundColor Cyan

# Copier le script si la WSL ne monte pas le même chemin
$cmd = @"
cd '$WslRepoRoot' && chmod +x linux/bootstrap.sh linux/lib/*.sh && sudo bash linux/bootstrap.sh $argString
"@

if ($UseExistingWsl) {
    wsl -d $WslName -e bash -c $cmd
} else {
    wsl -d $WslName -e bash -c $cmd
}

if ($LASTEXITCODE -ne 0) {
    throw "Le bootstrap a échoué (code $LASTEXITCODE). Consultez /var/log/wsl-project-init/setup.log"
}

Write-Host "✓ Bootstrap terminé" -ForegroundColor Green
