#Requires -Version 5.1
<#
.SYNOPSIS
    Configure le fichier .wslconfig global de l'utilisateur Windows.
#>

param(
    [string]$Memory = "8GB",
    [string]$Processors = "4",
    [string]$Swap = "4GB",
    [string]$TemplatePath
)

$ErrorActionPreference = "Stop"

$WslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

if (-not $TemplatePath) {
    $TemplatePath = Join-Path (Split-Path $PSScriptRoot -Parent) "config\wsl-template.wslconfig"
}

$content = @"
[wsl2]
memory=$Memory
processors=$Processors
swap=$Swap
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
"@

if (Test-Path $TemplatePath) {
    $content = Get-Content $TemplatePath -Raw
    $content = $content -replace 'memory=.*', "memory=$Memory"
    $content = $content -replace 'processors=.*', "processors=$Processors"
    $content = $content -replace 'swap=.*', "swap=$Swap"
}

Set-Content -Path $WslConfigPath -Value $content -Encoding UTF8
Write-Host "✓ .wslconfig écrit : $WslConfigPath" -ForegroundColor Green
