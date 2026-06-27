#Requires -Version 5.1

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WslInstance {
    param([string]$Name)
    $list = wsl --list --quiet 2>$null
    if (-not $list) { return $false }
    foreach ($line in $list) {
        $clean = ($line -replace '\0', '').Trim()
        if ($clean -eq $Name) { return $true }
    }
    return $false
}

function Get-WslInstanceNames {
    $list = wsl --list --quiet 2>$null
    if (-not $list) { return @() }
    return @($list | ForEach-Object { ($_ -replace '\0', '').Trim() } | Where-Object { $_ })
}

function Convert-ToWslPath {
    param([string]$WindowsPath)
    if (-not $WindowsPath) { return "" }
    $result = wsl wslpath -a $WindowsPath 2>$null
    if ($LASTEXITCODE -eq 0) { return $result.Trim() }
    $drive = $WindowsPath.Substring(0, 1).ToLower()
    $rest = $WindowsPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

function Copy-PlanToWsl {
    param(
        [string]$WslName,
        [string]$PlanFile
    )
    $wslPlanDir = "/var/lib/project-deploy"
    $wslPlanPath = "$wslPlanDir/plan.json"
    $wslSource = Convert-ToWslPath $PlanFile

    $cmd = @"
mkdir -p '$wslPlanDir' && cp '$wslSource' '$wslPlanPath' && chmod 644 '$wslPlanPath'
"@
    wsl -d $WslName -e bash -c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "Impossible de copier le plan dans WSL"
    }
    return $wslPlanPath
}

function Invoke-WslOrchestrator {
    param(
        [string]$WslName,
        [string]$RepoRoot,
        [string]$PlanPathInWsl,
        [switch]$NonInteractive
    )

    $wslRepo = Convert-ToWslPath $RepoRoot
    $extra = ""
    if ($NonInteractive) { $extra = "--non-interactive" }

    $cmd = @"
cd '$wslRepo' && chmod +x linux/orchestrator.sh linux/packages/*.sh linux/templates/*.sh linux/lib/*.sh && sudo bash linux/orchestrator.sh --plan '$PlanPathInWsl' $extra
"@

    wsl -d $WslName -e bash -c $cmd
    return $LASTEXITCODE
}
