#Requires -Version 5.1
<#
.SYNOPSIS
    Configure le fichier .wslconfig global de l'utilisateur Windows.
#>

param(
    [string]$Memory = "8GB",
    [string]$Processors = "4",
    [string]$Swap = "4GB"
)

$ErrorActionPreference = "Stop"

$WslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

$content = @"
[wsl2]
memory=$Memory
processors=$Processors
swap=$Swap
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
"@

Set-Content -Path $WslConfigPath -Value $content -Encoding UTF8
Write-Host "✓ .wslconfig écrit : $WslConfigPath" -ForegroundColor Green
