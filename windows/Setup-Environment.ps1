#Requires -Version 5.1
<#
.SYNOPSIS
    Verifie et installe les prerequis ProjectDeploy, puis prepare l'app Tauri.
#>

param(
    [switch]$InstallMissing = $true,
    [switch]$LaunchGui,
    [switch]$BuildRelease,
    [switch]$SkipWsl
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ((Get-Item -LiteralPath $PSCommandPath).Attributes -band [IO.FileAttributes]::Archive) {
    Unblock-File -LiteralPath $PSCommandPath
}
$AppDir = Join-Path $RepoRoot "app"
$TauriRelease = Join-Path $AppDir "src-tauri\target\release\project-deploy.exe"

$MinNodeMajor = 20

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ("-> {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host ("  [OK] {0}" -f $Message) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host ("  [!] {0}" -f $Message) -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host ("  [X] {0}" -f $Message) -ForegroundColor Red
}

function Refresh-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "{0};{1}" -f $machinePath, $userPath
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-WingetAvailable {
    return (Test-CommandExists "winget")
}

function Install-WithWinget {
    param(
        [string]$Id,
        [string]$Label,
        [string]$Override = ""
    )
    if (-not (Test-WingetAvailable)) {
        Write-Warn ("winget indisponible - installez {0} manuellement." -f $Label)
        return $false
    }
    Write-Step ("Installation de {0} via winget..." -f $Label)
    $wingetArgs = @(
        "install", "--id", $Id, "-e",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    if ($Override) {
        $wingetArgs += @("--override", $Override)
    }
    & winget @wingetArgs
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warn ("winget a retourne le code {0} pour {1}" -f $LASTEXITCODE, $Label)
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
    $regPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    $reg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
    return [bool]$reg
}

function Test-VsBuildTools {
    if (Test-CommandExists "cl") { return $true }
    if (Test-CommandExists "link") { return $true }
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) { return $false }
    $install = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($install) { return $true }
    $install2 = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Workload.VCTools `
        -property installationPath 2>$null
    return [bool]$install2
}

function Wait-VsBuildTools {
    param([int]$MaxMinutes = 45)
    $attempts = $MaxMinutes * 2
    for ($i = 1; $i -le $attempts; $i++) {
        Refresh-SessionPath
        if (Test-VsBuildTools) {
            return $true
        }
        $min = [math]::Floor($i / 2)
        Write-Host ("  En attente des Build Tools C++... ~{0} min" -f $min) -ForegroundColor Gray
        Start-Sleep -Seconds 30
    }
    return $false
}

function Test-WslReady {
    if (-not (Test-CommandExists "wsl")) { return $false }
    wsl --status 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-Wsl {
    if ($SkipWsl) {
        Write-Warn "Verification WSL ignoree (-SkipWsl)"
        return $true
    }
    Write-Step "WSL2"
    if (Test-WslReady) {
        Write-Ok "WSL disponible"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "WSL non configure"
        return $false
    }
    Write-Warn "WSL absent - installation (administrateur requis)..."
    try {
        wsl --install --no-distribution 2>&1 | Out-Host
        Refresh-SessionPath
        if (Test-WslReady) {
            Write-Ok "WSL installe - redemarrage Windows peut etre necessaire"
            return $true
        }
    } catch {
        Write-Fail ("Echec installation WSL : {0}" -f $_)
    }
    Write-Warn "Installez WSL manuellement : wsl --install"
    return $false
}

function Ensure-Node {
    Write-Step ("Node.js (>= {0})" -f $MinNodeMajor)
    $major = Get-NodeMajorVersion
    if ($major -ge $MinNodeMajor) {
        Write-Ok ("Node.js v{0}" -f $major)
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail ("Node.js {0}+ requis (trouve : v{1})" -f $MinNodeMajor, $major)
        return $false
    }
    if (Install-WithWinget -Id "OpenJS.NodeJS.LTS" -Label "Node.js LTS") {
        $major = Get-NodeMajorVersion
        if ($major -ge $MinNodeMajor) {
            Write-Ok ("Node.js v{0} installe" -f $major)
            return $true
        }
    }
    Write-Fail "Node.js introuvable - https://nodejs.org/"
    return $false
}

function Ensure-Rust {
    Write-Step "Rust / Cargo"
    if ((Test-CommandExists "rustc") -and (Test-CommandExists "cargo")) {
        $ver = rustc --version 2>$null
        Write-Ok ("Rust {0}" -f $ver)
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "Rust non installe"
        return $false
    }
    if (Install-WithWinget -Id "Rustlang.Rustup" -Label "Rustup") {
        Refresh-SessionPath
        $cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
        if (Test-Path $cargo) {
            $cargoDir = Split-Path $cargo
            $env:Path = "{0};{1}" -f $cargoDir, $env:Path
        }
        if ((Test-CommandExists "rustc") -and (Test-CommandExists "cargo")) {
            Write-Ok "Rust installe"
            return $true
        }
    }
    Write-Fail "Rust introuvable - https://rustup.rs/"
    return $false
}

function Ensure-WebView2 {
    Write-Step "WebView2 Runtime"
    if (Test-WebView2Installed) {
        Write-Ok "WebView2 present"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "WebView2 Runtime manquant"
        return $false
    }
    if (Install-WithWinget -Id "Microsoft.EdgeWebView2Runtime" -Label "WebView2") {
        if (Test-WebView2Installed) {
            Write-Ok "WebView2 installe"
            return $true
        }
    }
    Write-Warn "WebView2 peut etre preinstalle sur Windows 11 - continuez si l'app demarre"
    return $true
}

function Ensure-VsBuildTools {
    Write-Step "Visual Studio Build Tools (C++)"
    if (Test-VsBuildTools) {
        Write-Ok "Outils de compilation C++ detectes"
        return $true
    }
    Write-Warn "Build Tools C++ non detectes - requis pour compiler Tauri"
    if (-not $InstallMissing) { return $false }
    if (-not (Test-WingetAvailable)) {
        Write-Warn "Installez manuellement : Visual Studio Build Tools 2022 + charge C++"
        return $false
    }
    $answer = Read-Host "  Installer Build Tools (charge C++) maintenant ? [O/n]"
    if ($answer -ne "" -and $answer -notmatch '^[OoYy]') {
        return $false
    }
    $vsOverride = "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    $installed = Install-WithWinget `
        -Id "Microsoft.VisualStudio.2022.BuildTools" `
        -Label "VS Build Tools (C++)" `
        -Override $vsOverride
    if (-not $installed) {
        Write-Warn "Echec winget - installez Visual Studio Build Tools 2022 avec la charge C++"
        return $false
    }
    Write-Host "  L'installateur VS peut prendre 10 a 30 minutes..." -ForegroundColor Gray
    if (Wait-VsBuildTools -MaxMinutes 45) {
        Write-Ok "Build Tools C++ installes"
        return $true
    }
    Write-Warn "Build Tools pas encore detectes - relancez install.ps1 dans quelques minutes"
    Write-Warn "Ou ouvrez 'Visual Studio Installer' et verifiez la charge 'Developpement Desktop en C++'"
    return $false
}

function Ensure-NpmDependencies {
    Write-Step "Dependances npm (app Tauri)"
    if (-not (Test-Path $AppDir)) {
        Write-Fail ("Dossier app introuvable : {0}" -f $AppDir)
        return $false
    }
    $nodeModules = Join-Path $AppDir "node_modules"
    if ((Test-Path $nodeModules) -and (Test-Path (Join-Path $AppDir "package-lock.json"))) {
        Write-Ok "node_modules present"
        return $true
    }
    if (-not $InstallMissing) {
        Write-Fail "Executez : cd app ; npm install"
        return $false
    }
    Push-Location $AppDir
    try {
        Write-Host "  npm install..." -ForegroundColor Gray
        npm install
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "npm install a echoue"
            return $false
        }
        npm approve-scripts --allow-scripts-pending 2>$null | Out-Null
        Write-Ok "Dependances npm installees"
        return $true
    } finally {
        Pop-Location
    }
}

function Start-ProjectDeployGui {
    Write-Step "Lancement de l'interface graphique"

    if (Test-Path $TauriRelease) {
        Write-Ok "Executable release trouve"
        Start-Process -FilePath $TauriRelease -WorkingDirectory $RepoRoot
        return
    }

    if ($BuildRelease) {
        Push-Location $AppDir
        try {
            Write-Host "  Compilation release (peut prendre plusieurs minutes)..." -ForegroundColor Gray
            npm run tauri build
            if ($LASTEXITCODE -ne 0) { throw "tauri build a echoue" }
        } finally {
            Pop-Location
        }
        if (Test-Path $TauriRelease) {
            Start-Process -FilePath $TauriRelease -WorkingDirectory $RepoRoot
            return
        }
        throw "Executable release introuvable apres build"
    }

    Write-Ok "Mode developpement - npm run tauri dev"
    $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    $npmExe = if ($npmCmd) { $npmCmd.Source } else { "npm" }
    Start-Process -FilePath $npmExe -ArgumentList @("run", "tauri", "dev") `
        -WorkingDirectory $AppDir
}

# --- Execution ---

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   ProjectDeploy - Verification env." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

Refresh-SessionPath

$checks = @(
    @{ Name = "wsl"; Ok = (Ensure-Wsl) }
    @{ Name = "node"; Ok = (Ensure-Node) }
    @{ Name = "rust"; Ok = (Ensure-Rust) }
    @{ Name = "webview2"; Ok = (Ensure-WebView2) }
    @{ Name = "vs"; Ok = (Ensure-VsBuildTools) }
    @{ Name = "npm"; Ok = (Ensure-NpmDependencies) }
)

$guiReady = ($checks | Where-Object {
    $_.Name -in @("node", "rust", "webview2", "vs", "npm") -and -not $_.Ok
}).Count -eq 0

$deployReady = ($checks | Where-Object {
    $_.Name -eq "wsl" -and -not $_.Ok
}).Count -eq 0

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($guiReady) {
    Write-Host "  GUI         : prete" -ForegroundColor Green
} else {
    Write-Host "  GUI         : incomplete" -ForegroundColor Red
}
if ($SkipWsl -or $deployReady) {
    Write-Host "  Deploiement : pret (WSL OK ou ignore)" -ForegroundColor Green
} else {
    Write-Host "  Deploiement : WSL requis pour installer des projets" -ForegroundColor Yellow
}
Write-Host "==========================================" -ForegroundColor Cyan

if ($LaunchGui) {
    if (-not $guiReady) {
        $failed = @($checks | Where-Object {
            $_.Name -in @("node", "rust", "webview2", "vs", "npm") -and -not $_.Ok
        } | ForEach-Object { $_.Name })
        Write-Fail ("Prerequis manquants : {0}" -f ($failed -join ", "))
        if ($failed -contains "vs") {
            Write-Host ""
            Write-Host "  Si VS Build Tools vient d'etre installe, attendez la fin puis relancez :" -ForegroundColor Yellow
            Write-Host "    .\install.ps1" -ForegroundColor White
        }
        exit 1
    }
    Start-ProjectDeployGui
    exit 0
}

if ($guiReady) {
    Write-Host ""
    Write-Host "Tout est pret. Lancez :" -ForegroundColor Green
    Write-Host "  .\install.ps1" -ForegroundColor White
    exit 0
}

exit 1
