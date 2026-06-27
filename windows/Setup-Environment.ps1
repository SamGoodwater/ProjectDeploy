#Requires -Version 5.1
<#
.SYNOPSIS
    Vérifie et installe les prérequis ProjectDeploy, puis prépare l'app Tauri.

.DESCRIPTION
    Contrôle WSL2, Node.js 20+, Rust, WebView2 et les dépendances npm.
    Installe automatiquement via winget lorsque c'est possible.

.PARAMETER InstallMissing
    Tente d'installer les composants manquants (défaut : true).

.PARAMETER LaunchGui
    Lance l'interface graphique si tous les prérequis GUI sont OK.

.PARAMETER BuildRelease
    Compile l'exécutable Tauri release au lieu de lancer tauri dev.

.PARAMETER SkipWsl
    Ne vérifie pas WSL (utile si vous testez uniquement la GUI).
#>

param(
    [switch]$InstallMissing = $true,
    [switch]$LaunchGui,
    [switch]$BuildRelease,
    [switch]$SkipWsl
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$AppDir = Join-Path $RepoRoot "app"
$TauriRelease = Join-Path $AppDir "src-tauri\target\release\project-deploy.exe"

$MinNodeMajor = 20

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "→ $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

function Refresh-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-WingetAvailable {
    return Test-CommandExists "winget"
}

function Install-WithWinget {
    param(
        [string]$Id,
        [string]$Label
    )
    if (-not (Test-WingetAvailable)) {
        Write-Warn "winget indisponible — installez $Label manuellement."
        return $false
    }
    Write-Step "Installation de $Label via winget..."
    winget install --id $Id -e `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warn "winget a retourné le code $LASTEXITCODE pour $Label"
        return $false
    }
    Refresh-SessionPath
    return $true
}

function Get-NodeMajorVersion {
    if (-not (Test-CommandExists "node")) { return 0 }
    $raw = (node --version 2>$null).TrimStart("v")
    if ($raw -match '^(\d+)') { return [int]$Matches[1] }
    return 0
}

function Test-WebView2Installed {
    $paths = @(
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application",
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $true }
    }
    $reg = Get-ItemProperty `
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" `
        -ErrorAction SilentlyContinue
    return [bool]$reg
}

function Test-VsBuildTools {
    if (Test-CommandExists "cl") { return $true }
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) { return $false }
    $install = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return [bool]$install
}

function Test-WslReady {
    if (-not (Test-CommandExists "wsl")) { return $false }
    wsl --status 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Ensure-Wsl {
    if ($SkipWsl) {
        Write-Warn "Vérification WSL ignorée (-SkipWsl)"
        return $true
    }
    Write-Step "WSL2"
    if (Test-WslReady) {
        Write-Ok "WSL disponible"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "WSL non configuré"
        return $false
    }
    Write-Warn "WSL absent — installation (administrateur requis)..."
    try {
        wsl --install --no-distribution 2>&1 | Out-Host
        Refresh-SessionPath
        if (Test-WslReady) {
            Write-Ok "WSL installé — redémarrage Windows peut être nécessaire"
            return $true
        }
    } catch {
        Write-Fail "Échec installation WSL : $_"
    }
    Write-Warn "Installez WSL manuellement : wsl --install"
    return $false
}

function Ensure-Node {
    Write-Step "Node.js (>= $MinNodeMajor)"
    $major = Get-NodeMajorVersion
    if ($major -ge $MinNodeMajor) {
        Write-Ok "Node.js v$major"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "Node.js $MinNodeMajor+ requis (trouvé : v$major)"
        return $false
    }
    if (Install-WithWinget -Id "OpenJS.NodeJS.LTS" -Label "Node.js LTS") {
        $major = Get-NodeMajorVersion
        if ($major -ge $MinNodeMajor) {
            Write-Ok "Node.js v$major installé"
            return $true
        }
    }
    Write-Fail "Node.js introuvable — https://nodejs.org/"
    return $false
}

function Ensure-Rust {
    Write-Step "Rust / Cargo"
    if ((Test-CommandExists "rustc") -and (Test-CommandExists "cargo")) {
        Write-Ok "Rust $(rustc --version 2>$null)"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "Rust non installé"
        return $false
    }
    if (Install-WithWinget -Id "Rustlang.Rustup" -Label "Rustup") {
        Refresh-SessionPath
        $cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
        if (Test-Path $cargo) {
            $env:Path = "$(Split-Path $cargo);$env:Path"
        }
        if ((Test-CommandExists "rustc") -and (Test-CommandExists "cargo")) {
            Write-Ok "Rust installé"
            return $true
        }
    }
    Write-Fail "Rust introuvable — https://rustup.rs/"
    return $false
}

function Ensure-WebView2 {
    Write-Step "WebView2 Runtime"
    if (Test-WebView2Installed) {
        Write-Ok "WebView2 présent"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "WebView2 Runtime manquant"
        return $false
    }
    if (Install-WithWinget -Id "Microsoft.EdgeWebView2Runtime" -Label "WebView2") {
        if (Test-WebView2Installed) {
            Write-Ok "WebView2 installé"
            return $true
        }
    }
    Write-Warn "WebView2 peut être préinstallé sur Windows 11 — continuez si l'app démarre"
    return $true
}

function Ensure-VsBuildTools {
    Write-Step "Visual Studio Build Tools (C++)"
    if (Test-VsBuildTools) {
        Write-Ok "Outils de compilation C++ détectés"
        return $true
    }
    Write-Warn "Build Tools C++ non détectés — requis pour compiler Tauri"
    if (-not $InstallMissing) { return $false }
    if (Test-WingetAvailable) {
        $answer = Read-Host "  Installer Build Tools maintenant ? [O/n]"
        if ($answer -eq "" -or $answer -match '^[OoYy]') {
            Install-WithWinget -Id "Microsoft.VisualStudio.2022.BuildTools" -Label "VS Build Tools" | Out-Null
            Write-Warn "Relancez ce script après l'installation des Build Tools"
            return $false
        }
    }
    return $false
}

function Ensure-NpmDependencies {
    Write-Step "Dépendances npm (app Tauri)"
    if (-not (Test-Path $AppDir)) {
        Write-Fail "Dossier app introuvable : $AppDir"
        return $false
    }
    $nodeModules = Join-Path $AppDir "node_modules"
    if ((Test-Path $nodeModules) -and (Test-Path (Join-Path $AppDir "package-lock.json"))) {
        Write-Ok "node_modules présent"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "Exécutez : cd app && npm install"
        return $false
    }
    Push-Location $AppDir
    try {
        Write-Host "  npm install..." -ForegroundColor Gray
        npm install
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "npm install a échoué"
            return $false
        }
        Write-Ok "Dépendances npm installées"
        return $true
    } finally {
        Pop-Location
    }
}

function Start-ProjectDeployGui {
    Write-Step "Lancement de l'interface graphique"

    if (Test-Path $TauriRelease) {
        Write-Ok "Exécutable release trouvé"
        Start-Process -FilePath $TauriRelease -WorkingDirectory $RepoRoot
        return
    }

    if ($BuildRelease) {
        Push-Location $AppDir
        try {
            Write-Host "  Compilation release (peut prendre plusieurs minutes)..." -ForegroundColor Gray
            npm run tauri build
            if ($LASTEXITCODE -ne 0) { throw "tauri build a échoué" }
        } finally {
            Pop-Location
        }
        if (Test-Path $TauriRelease) {
            Start-Process -FilePath $TauriRelease -WorkingDirectory $RepoRoot
            return
        }
        throw "Exécutable release introuvable après build"
    }

    Push-Location $AppDir
    try {
        Write-Ok "Mode développement — npm run tauri dev"
        $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
        $npm = if ($npmCmd) { $npmCmd.Source } else { "npm" }
        Start-Process -FilePath $npm -ArgumentList @("run", "tauri", "dev") `
            -WorkingDirectory $AppDir
    } finally {
        Pop-Location
    }
}

# --- Exécution ---

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   ProjectDeploy — Vérification env.      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan

Refresh-SessionPath

$checks = @(
    @{ Name = "wsl"; Ok = (Ensure-Wsl) }
    @{ Name = "node"; Ok = (Ensure-Node) }
    @{ Name = "rust"; Ok = (Ensure-Rust) }
    @{ Name = "webview2"; Ok = (Ensure-WebView2) }
    @{ Name = "vs"; Ok = (Ensure-VsBuildTools) }
    @{ Name = "npm"; Ok = (Ensure-NpmDependencies) }
)

$guiReady = ($checks | Where-Object { $_.Name -in @("node", "rust", "webview2", "vs", "npm") -and -not $_.Ok }).Count -eq 0
$deployReady = ($checks | Where-Object { $_.Name -eq "wsl" -and -not $_.Ok }).Count -eq 0

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
if ($guiReady) {
    Write-Host "  GUI        : prête" -ForegroundColor Green
} else {
    Write-Host "  GUI        : incomplète" -ForegroundColor Red
}
if ($SkipWsl -or $deployReady) {
    Write-Host "  Déploiement: prêt (WSL OK ou ignoré)" -ForegroundColor Green
} else {
    Write-Host "  Déploiement: WSL requis pour installer des projets" -ForegroundColor Yellow
}
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan

if ($LaunchGui) {
    if (-not $guiReady) {
        Write-Fail "Corrigez les prérequis ci-dessus avant de lancer la GUI."
        exit 1
    }
    Start-ProjectDeployGui
    exit 0
}

if ($guiReady) {
    Write-Host ""
    Write-Host "Tout est prêt. Lancez :" -ForegroundColor Green
    Write-Host "  .\install.ps1" -ForegroundColor White
    exit 0
}

exit 1
