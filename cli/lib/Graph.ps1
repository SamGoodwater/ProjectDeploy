#Requires -Version 5.1

. "$PSScriptRoot\Catalog.ps1"

function Resolve-PackageDependencies {
    param(
        [string[]]$SelectedIds,
        [string[]]$RequiredTemplateIds
    )

    $allPackages = Get-CatalogPackages
    $byId = @{}
    foreach ($p in $allPackages) { $byId[$p.id] = $p }

    $selected = [System.Collections.Generic.HashSet[string]]::new([string[]]$SelectedIds)
    $selected.Add("base") | Out-Null

    # Paquets requis par les templates
    foreach ($tplId in $RequiredTemplateIds) {
        $tpl = Get-TemplateById $tplId
        if (-not $tpl) { continue }
        foreach ($pkgId in @($tpl.requiresPackages)) {
            [void]$selected.Add($pkgId)
        }
        foreach ($cap in @($tpl.requiresProvides)) {
            foreach ($p in $allPackages) {
                if (@($p.provides) -contains $cap) {
                    [void]$selected.Add($p.id)
                }
            }
        }
    }

    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($id in @($selected)) {
            $pkg = $byId[$id]
            if (-not $pkg) { continue }
            foreach ($req in @($pkg.requires)) {
                if (-not $selected.Contains($req)) {
                    [void]$selected.Add($req)
                    $changed = $true
                }
            }
            foreach ($cap in @($pkg.requiresProvides)) {
                foreach ($p in $allPackages) {
                    if (@($p.provides) -contains $cap -and -not $selected.Contains($p.id)) {
                        [void]$selected.Add($p.id)
                        $changed = $true
                    }
                }
            }
        }
    }

    return @($selected) | Sort-Object
}

function Test-SelectionConflicts {
    param(
        [string[]]$PackageIds,
        [string[]]$TemplateIds
    )

    $errors = @()
    $warnings = @()
    $allPackages = Get-CatalogPackages
    $allTemplates = Get-CatalogTemplates

    $selectedPkg = [System.Collections.Generic.HashSet[string]]::new([string[]]$PackageIds)
    $selectedTpl = [System.Collections.Generic.HashSet[string]]::new([string[]]$TemplateIds)

    foreach ($p in $allPackages) {
        if (-not $selectedPkg.Contains($p.id)) { continue }
        foreach ($other in @($p.incompatibleWith)) {
            if ($selectedPkg.Contains($other)) {
                $errors += "Paquet '$($p.id)' incompatible avec '$other'"
            }
        }
    }

    foreach ($t in $allTemplates) {
        if (-not $selectedTpl.Contains($t.id)) { continue }
        foreach ($other in @($t.incompatibleWith)) {
            if ($selectedTpl.Contains($other)) {
                $errors += "Template '$($t.id)' incompatible avec '$other'"
            }
        }
    }

    if ($selectedTpl.Count -eq 0) {
        $warnings += "Aucun template sélectionné — seuls les paquets seront installés"
    }

    return [pscustomobject]@{
        Valid    = ($errors.Count -eq 0)
        Errors   = $errors
        Warnings = $warnings
    }
}

function Sort-PackagesTopologically {
    param([string[]]$PackageIds)

    $allPackages = Get-CatalogPackages
    $byId = @{}
    foreach ($p in $allPackages) { $byId[$p.id] = $p }

    $ids = @($PackageIds | Where-Object { $byId.ContainsKey($_) })
    $sorted = New-Object System.Collections.Generic.List[string]
    $visited = @{}

    function Visit([string]$Id) {
        if ($visited.ContainsKey($Id)) { return }
        $visited[$Id] = $true
        $pkg = $byId[$Id]
        if ($pkg) {
            foreach ($req in @($pkg.requires)) {
                if ($ids -contains $req) { Visit $req }
            }
            foreach ($cap in @($pkg.requiresProvides)) {
                foreach ($p in $allPackages) {
                    if (@($p.provides) -contains $cap -and ($ids -contains $p.id)) {
                        Visit $p.id
                    }
                }
            }
        }
        if ($ids -contains $Id) { [void]$sorted.Add($Id) }
    }

    foreach ($id in $ids) { Visit $id }
    return $sorted.ToArray()
}

function Build-PackageSelections {
    param(
        [string[]]$PackageIds,
        [hashtable]$PackageOptions = @{}
    )

    $result = @()
    foreach ($id in (Sort-PackagesTopologically $PackageIds)) {
        $opts = @{}
        if ($PackageOptions.ContainsKey($id)) {
            $raw = $PackageOptions[$id]
            if ($raw -is [hashtable]) {
                $raw.GetEnumerator() | ForEach-Object { $opts[$_.Key] = $_.Value }
            } elseif ($raw -is [pscustomobject]) {
                $raw.PSObject.Properties | ForEach-Object { $opts[$_.Name] = $_.Value }
            }
        }
        $result += [ordered]@{ id = $id; options = $opts }
    }
    return $result
}

function Build-TemplateSelections {
    param(
        [string[]]$TemplateIds,
        [hashtable]$TemplateOptions = @{}
    )

    $result = @()
    foreach ($id in $TemplateIds) {
        $opts = @{}
        if ($TemplateOptions.ContainsKey($id)) {
            $raw = $TemplateOptions[$id]
            if ($raw -is [hashtable]) {
                $raw.GetEnumerator() | ForEach-Object { $opts[$_.Key] = $_.Value }
            } elseif ($raw -is [pscustomobject]) {
                $raw.PSObject.Properties | ForEach-Object { $opts[$_.Name] = $_.Value }
            }
        }
        $result += [ordered]@{ id = $id; options = $opts }
    }
    return $result
}

function Resolve-FullSelection {
    param(
        [string[]]$PackageIds,
        [string[]]$TemplateIds,
        [hashtable]$PackageOptions = @{},
        [hashtable]$TemplateOptions = @{}
    )

    $resolvedIds = Resolve-PackageDependencies -SelectedIds $PackageIds -RequiredTemplateIds $TemplateIds
    $validation = Test-SelectionConflicts -PackageIds $resolvedIds -TemplateIds $TemplateIds

    return [pscustomobject]@{
        PackageIds         = $resolvedIds
        PackageSelections  = (Build-PackageSelections -PackageIds $resolvedIds -PackageOptions $PackageOptions)
        TemplateSelections = (Build-TemplateSelections -TemplateIds $TemplateIds -TemplateOptions $TemplateOptions)
        Validation         = $validation
    }
}
