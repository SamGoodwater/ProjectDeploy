#Requires -Version 5.1
<#
.SYNOPSIS
    Ajoute une entrée dans le fichier hosts Windows pour un domaine .local
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [string]$IpAddress = "127.0.0.1"
)

$ErrorActionPreference = "Stop"

$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$Entry = "$IpAddress`t$Domain"

$content = Get-Content $HostsPath -ErrorAction SilentlyContinue
if ($content -match [regex]::Escape($Domain)) {
    Write-Host "✓ Entrée hosts déjà présente pour $Domain" -ForegroundColor Yellow
    return
}

try {
    Add-Content -Path $HostsPath -Value "`n$Entry" -ErrorAction Stop
    Write-Host "✓ Hosts mis à jour : $Entry" -ForegroundColor Green
} catch {
    Write-Host "! Impossible de modifier hosts (droits admin requis)" -ForegroundColor Yellow
    Write-Host "  Ajoutez manuellement dans $HostsPath :" -ForegroundColor Yellow
    Write-Host "  $Entry" -ForegroundColor White
}
