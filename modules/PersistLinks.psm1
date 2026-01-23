<#
.SYNOPSIS
Helpers for managing persist links for apps with non-standard data locations.
#>

function Get-PersistLinksConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )

    $configPath = Join-Path $ProjectRoot 'config\persist_links.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    try {
        $raw = Get-Content -Raw -Path $configPath
        if (-not $raw) {
            return $null
        }
        $json = $raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to parse persist_links.json: $($_.Exception.Message)"
        return $null
    }

    $config = @{}
    foreach ($prop in $json.PSObject.Properties) {
        $appName = $prop.Name
        $entries = $prop.Value

        if ($null -eq $entries) {
            continue
        }

        if ($entries -isnot [System.Collections.IEnumerable] -or $entries -is [string]) {
            $entries = @($entries)
        }

        $validEntries = @()
        foreach ($entry in $entries) {
            if (-not $entry.link -or -not $entry.target) {
                Write-Warning "persist_links.json entry for '$appName' is missing link/target."
                continue
            }
            $validEntries += $entry
        }

        if ($validEntries.Count -gt 0) {
            $config[$appName] = $validEntries
        }
    }

    if ($config.Count -eq 0) {
        return $null
    }

    return $config
}

function Get-InstalledAppsMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )

    $installed = @{}
    $appsDir = Join-Path $ScoopRoot 'apps'
    if (-not (Test-Path -LiteralPath $appsDir)) {
        return $installed
    }

    Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
        $appName = $_.Name
        if ($appName -eq 'scoop') { return }

        $versionDirs = Get-ChildItem -Path $_.FullName -Directory | Where-Object { $_.Name -ne 'current' }
        if ($versionDirs -and $versionDirs.Count -gt 0) {
            $installed[$appName.ToLowerInvariant()] = $true
        }
    }

    return $installed
}

function Normalize-Path {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $normalized = $Path
    try {
        $normalized = [System.IO.Path]::GetFullPath($Path)
    } catch {
        $normalized = $Path
    }

    if ($normalized.Length -gt 3) {
        $normalized = $normalized.TrimEnd('\')
    }

    return $normalized
}

function Resolve-LinkPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Link,

        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )

    if ($Link -match '^[Aa]pps[\\/]') {
        $resolved = Join-Path $ScoopRoot $Link
    } else {
        $resolved = [Environment]::ExpandEnvironmentVariables($Link)
    }

    try {
        $resolved = [System.IO.Path]::GetFullPath($resolved)
    } catch { }

    return $resolved
}

function Resolve-PersistTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Target,

        [Parameter(Mandatory=$true)]
        [string]$PersistRoot
    )

    if ($Target -notmatch '^[Pp]ersist\\') {
        return $null
    }

    $isFolder = $Target.EndsWith('\')
    $relative = $Target -replace '^[Pp]ersist\\', ''
    $resolved = Join-Path $PersistRoot $relative

    return [pscustomobject]@{
        Path = $resolved
        IsFolder = $isFolder
        Raw = $Target
    }
}

function Get-ExistingLinkInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LinkPath
    )

    $info = [pscustomobject]@{
        Exists = $false
        IsLink = $false
        LinkType = $null
        Targets = @()
        IsDirectory = $false
    }

    if (-not (Test-Path -LiteralPath $LinkPath)) {
        return $info
    }

    $info.Exists = $true

    try {
        $item = Get-Item -LiteralPath $LinkPath -Force
        $info.IsDirectory = [bool]$item.PSIsContainer

        if ($item.PSObject.Properties.Match('LinkType').Count -gt 0 -and $item.LinkType) {
            $info.IsLink = $true
            $info.LinkType = $item.LinkType
        } elseif ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $info.IsLink = $true
        }

        if ($item.PSObject.Properties.Match('Target').Count -gt 0 -and $item.Target) {
            $info.Targets = @($item.Target)
        }
    } catch { }

    if (-not $info.IsLink -and $info.Exists -and -not $info.IsDirectory) {
        try {
            $hardlinkTargets = @()

            Assert-ExternalCommandRunner -Caller 'Get-LinkInfo'

            $projectRoot = Split-Path -Parent $PSScriptRoot
            $fsutilCmd = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath 'fsutil' -ArgumentList @('hardlink', 'list', $LinkPath) -Stream:$false -NoHostOutput
            $fsutilOutput = if ($fsutilCmd.Output) { $fsutilCmd.Output -split "\r?\n" } else { @() }

            if ($fsutilCmd.ExitCode -eq 0 -and $fsutilOutput) {
                $root = [System.IO.Path]::GetPathRoot($LinkPath)
                foreach ($line in $fsutilOutput) {
                    $trimmed = $line.Trim()
                    if (-not $trimmed) { continue }
                    if ($trimmed -match '^Hardlink\(s\)\s+for\s+file') { continue }
                    if ($trimmed -match '^[A-Za-z]:') {
                        $hardlinkTargets += $trimmed
                    } else {
                        $hardlinkTargets += (Join-Path $root $trimmed.TrimStart('\'))
                    }
                }
            }
            if ($hardlinkTargets.Count -gt 1) {
                $info.IsLink = $true
                $info.LinkType = 'HardLink'
                $info.Targets = $hardlinkTargets
            }
        } catch { }
    }

    return $info
}

function Test-LinkTargetMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Targets,

        [Parameter(Mandatory=$true)]
        [string]$ExpectedTarget
    )

    if (-not $Targets -or $Targets.Count -eq 0) {
        return $false
    }

    $expectedNorm = Normalize-Path -Path $ExpectedTarget

    foreach ($target in $Targets) {
        if (-not $target) { continue }
        $targetNorm = Normalize-Path -Path $target
        if ($targetNorm -and $expectedNorm -and $targetNorm.Equals($expectedNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Build-PersistLinkPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [Parameter(Mandatory=$true)]
        [hashtable]$InstalledApps,

        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,

        [Parameter(Mandatory=$true)]
        [string]$PersistRoot,

        [Parameter(Mandatory=$false)]
        [string[]]$AppNameFilter
    )

    $plan = @()

    $filterSet = @{}
    if ($AppNameFilter) {
        foreach ($name in $AppNameFilter) {
            if ($name) {
                $filterSet[$name.ToLowerInvariant()] = $true
            }
        }
    }

    foreach ($appName in $Config.Keys) {
        $appKey = $appName.ToLowerInvariant()
        if ($filterSet.Count -gt 0 -and -not $filterSet.ContainsKey($appKey)) {
            continue
        }

        if (-not $InstalledApps.ContainsKey($appKey)) {
            continue
        }

        foreach ($entry in $Config[$appName]) {
            $linkRaw = [string]$entry.link
            $targetRaw = [string]$entry.target

            if (-not $linkRaw -or -not $targetRaw) {
                Write-Warning "persist_links.json entry for '$appName' is missing link/target."
                continue
            }

            $targetInfo = Resolve-PersistTarget -Target $targetRaw -PersistRoot $PersistRoot
            if (-not $targetInfo) {
                Write-Warning "Persist target for '$appName' must start with 'persist\\': $targetRaw"
                continue
            }

            $linkPath = Resolve-LinkPath -Link $linkRaw -ScoopRoot $ScoopRoot
            $targetPath = $targetInfo.Path
            $isFolder = $targetInfo.IsFolder
            $desiredType = if ($isFolder) { 'Junction' } else { 'HardLink' }

            $existing = Get-ExistingLinkInfo -LinkPath $linkPath
            $targetExists = Test-Path -LiteralPath $targetPath
            $targetIsDir = $false
            if ($targetExists) {
                $targetIsDir = Test-Path -LiteralPath $targetPath -PathType Container
            }

            if ($targetExists) {
                if ($isFolder -and -not $targetIsDir) {
                    $plan += [pscustomobject]@{
                        AppName = $appName
                        LinkPath = $linkPath
                        TargetPath = $targetPath
                        LinkType = $desiredType
                        Action = 'WARN'
                        Reason = 'Target is not a directory'
                        ExistingExists = $existing.Exists
                        ExistingIsLink = $existing.IsLink
                        ExistingLinkType = $existing.LinkType
                        ExistingTargets = $existing.Targets
                        TargetExists = $targetExists
                        TargetIsDirectory = $targetIsDir
                    }
                    continue
                }
                if (-not $isFolder -and $targetIsDir) {
                    $plan += [pscustomobject]@{
                        AppName = $appName
                        LinkPath = $linkPath
                        TargetPath = $targetPath
                        LinkType = $desiredType
                        Action = 'WARN'
                        Reason = 'Target is a directory'
                        ExistingExists = $existing.Exists
                        ExistingIsLink = $existing.IsLink
                        ExistingLinkType = $existing.LinkType
                        ExistingTargets = $existing.Targets
                        TargetExists = $targetExists
                        TargetIsDirectory = $targetIsDir
                    }
                    continue
                }
            }

            if (-not $existing.Exists) {
                $plan += [pscustomobject]@{
                    AppName = $appName
                    LinkPath = $linkPath
                    TargetPath = $targetPath
                    LinkType = $desiredType
                    Action = 'CREATE'
                    Reason = 'Missing'
                    ExistingExists = $existing.Exists
                    ExistingIsLink = $existing.IsLink
                    ExistingLinkType = $existing.LinkType
                    ExistingTargets = $existing.Targets
                    TargetExists = $targetExists
                    TargetIsDirectory = $targetIsDir
                }
                continue
            }

            if ($existing.IsLink) {
                $matches = Test-LinkTargetMatch -Targets $existing.Targets -ExpectedTarget $targetPath
                if ($matches -and -not $targetExists) {
                    $plan += [pscustomobject]@{
                        AppName = $appName
                        LinkPath = $linkPath
                        TargetPath = $targetPath
                        LinkType = $desiredType
                        Action = 'WARN'
                        Reason = 'Target missing'
                        ExistingExists = $existing.Exists
                        ExistingIsLink = $existing.IsLink
                        ExistingLinkType = $existing.LinkType
                        ExistingTargets = $existing.Targets
                        TargetExists = $targetExists
                        TargetIsDirectory = $targetIsDir
                        TargetMatch = $matches
                    }
                } elseif ($matches) {
                    $plan += [pscustomobject]@{
                        AppName = $appName
                        LinkPath = $linkPath
                        TargetPath = $targetPath
                        LinkType = $desiredType
                        Action = 'SKIP'
                        Reason = 'Already linked'
                        ExistingExists = $existing.Exists
                        ExistingIsLink = $existing.IsLink
                        ExistingLinkType = $existing.LinkType
                        ExistingTargets = $existing.Targets
                        TargetExists = $targetExists
                        TargetIsDirectory = $targetIsDir
                        TargetMatch = $matches
                    }
                } else {
                    $reason = if (-not $targetExists) { 'Target missing; link points elsewhere' } else { 'Link points elsewhere' }
                    $plan += [pscustomobject]@{
                        AppName = $appName
                        LinkPath = $linkPath
                        TargetPath = $targetPath
                        LinkType = $desiredType
                        Action = 'WARN'
                        Reason = $reason
                        ExistingExists = $existing.Exists
                        ExistingIsLink = $existing.IsLink
                        ExistingLinkType = $existing.LinkType
                        ExistingTargets = $existing.Targets
                        TargetExists = $targetExists
                        TargetIsDirectory = $targetIsDir
                        TargetMatch = $matches
                    }
                }
                continue
            }

            $plan += [pscustomobject]@{
                AppName = $appName
                LinkPath = $linkPath
                TargetPath = $targetPath
                LinkType = $desiredType
                Action = 'WARN'
                Reason = 'Existing path is not a link'
                ExistingExists = $existing.Exists
                ExistingIsLink = $existing.IsLink
                ExistingLinkType = $existing.LinkType
                ExistingTargets = $existing.Targets
                TargetExists = $targetExists
                TargetIsDirectory = $targetIsDir
            }
        }
    }

    return $plan
}

function Invoke-PersistLinks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,

        [Parameter(Mandatory=$false)]
        [string[]]$AppName
    )

    $config = Get-PersistLinksConfig -ProjectRoot $ProjectRoot
    if (-not $config) {
        return
    }

    $filterSet = @{}
    if ($AppName) {
        foreach ($name in $AppName) {
            if ($name) {
                $filterSet[$name.ToLowerInvariant()] = $true
            }
        }
    }

    if ($filterSet.Count -gt 0) {
        $matches = $false
        foreach ($appKey in $config.Keys) {
            if ($filterSet.ContainsKey($appKey.ToLowerInvariant())) {
                $matches = $true
                break
            }
        }
        if (-not $matches) {
            return
        }
    }

    $installedApps = Get-InstalledAppsMap -ScoopRoot $ScoopRoot
    $persistRoot = Join-Path $ScoopRoot 'persist'

    $plan = Build-PersistLinkPlan -Config $config -InstalledApps $installedApps -ScoopRoot $ScoopRoot -PersistRoot $persistRoot -AppNameFilter $AppName
    if (-not $plan -or $plan.Count -eq 0) {
        return
    }

    if ($AppName -and $AppName.Count -gt 0) {
        Write-Host ("[*] Persist links preview (app: {0})" -f ($AppName -join ', '))
    } else {
        Write-Host "[*] Persist links preview"
    }
    Write-Host ""

    $currentApp = $null
    $hasWarnings = $false
    foreach ($item in $plan) {
        if ($item.AppName -ne $currentApp) {
            if ($null -ne $currentApp) {
                Write-Host ""
            }
            Write-Host ("[*] Processing: {0}" -f $item.AppName)
            Write-Host ""
            $currentApp = $item.AppName
        }

        Write-Host ("    Link:   {0}" -f $item.LinkPath)
        Write-Host ("    Target: {0}" -f $item.TargetPath)
        Write-Host ("    Type:   {0}" -f $item.LinkType)
        Write-Host ("    Target exists: {0}" -f ($(if ($item.TargetExists) { 'yes' } else { 'no' })))

        if ($item.TargetExists) {
            $targetType = if ($item.TargetIsDirectory) { 'directory' } else { 'file' }
            Write-Host ("    Target type: {0}" -f $targetType)
        }

        if ($item.ExistingExists) {
            if ($item.ExistingIsLink) {
                $linkType = if ($item.ExistingLinkType) { $item.ExistingLinkType } else { 'ReparsePoint' }
                Write-Host ("    Existing: link ({0})" -f $linkType)
                if ($null -ne $item.TargetMatch) {
                    Write-Host ("    Target match: {0}" -f ($(if ($item.TargetMatch) { 'yes' } else { 'no' })))
                }
                if (-not $item.TargetMatch -and $item.ExistingTargets) {
                    $targets = $item.ExistingTargets -join '; '
                    Write-Host ("    Current target(s): {0}" -f $targets)
                }
            } else {
                Write-Host "    Existing: path (not a link)"
            }
        } else {
            Write-Host "    Existing: not found"
        }

        switch ($item.Action) {
            'CREATE' { Write-Host ("    Result: CREATE ({0})" -f $item.Reason) }
            'SKIP'   { Write-Host ("    Result: SKIP ({0})" -f $item.Reason) }
            'WARN'   {
                $hasWarnings = $true
                Write-Warning ("Persist link issue for {0}: {1}" -f $item.AppName, $item.Reason)
                Write-Host ("    Result: WARN ({0})" -f $item.Reason)
            }
        }
        Write-Host ""
    }

    $toCreate = @($plan | Where-Object { $_.Action -eq 'CREATE' })
    if ($toCreate.Count -eq 0) {
        if ($hasWarnings) {
            Write-Warning "Persist link warnings detected. Review the preview above."
        } else {
            Write-Host "[*] No relinks to apply."
        }
        Write-Host ""
        return
    }

    $confirm = Read-Host 'Proceed with relinks? (Y/N)'
    if ($confirm -notmatch '^(y|yes)$') {
        Write-Host "[*] Relinks cancelled."
        Write-Host ""
        return
    }

    $hasErrors = $false
    foreach ($item in $toCreate) {
        try {
            if ($item.LinkType -eq 'Junction') {
                if (-not (Test-Path -LiteralPath $item.TargetPath)) {
                    New-Item -ItemType Directory -LiteralPath $item.TargetPath -Force | Out-Null
                }
            } else {
                $targetParent = Split-Path -Parent $item.TargetPath
                if ($targetParent -and -not (Test-Path -LiteralPath $targetParent)) {
                    New-Item -ItemType Directory -LiteralPath $targetParent -Force | Out-Null
                }
                if (-not (Test-Path -LiteralPath $item.TargetPath)) {
                    New-Item -ItemType File -LiteralPath $item.TargetPath -Force | Out-Null
                }
            }

            $linkParent = Split-Path -Parent $item.LinkPath
            if ($linkParent -and -not (Test-Path -LiteralPath $linkParent)) {
                New-Item -ItemType Directory -LiteralPath $linkParent -Force | Out-Null
            }

            if ($item.LinkType -eq 'Junction') {
                New-Item -ItemType Junction -Path $item.LinkPath -Target $item.TargetPath | Out-Null
            } else {
                New-Item -ItemType HardLink -Path $item.LinkPath -Target $item.TargetPath | Out-Null
            }

            Write-Host ("[OK] Linked {0}: {1} -> {2} ({3})" -f $item.AppName, $item.LinkPath, $item.TargetPath, $item.LinkType)
        } catch {
            $hasErrors = $true
            Write-Error "Failed to create link for $($item.AppName): $($_.Exception.Message)"
        }
    }

    if ($hasErrors) {
        Write-Warning "Some persist links failed to create. Review the errors above."
    }

    Write-Host ""
}

Export-ModuleMember -Function @(
    'Get-PersistLinksConfig',
    'Invoke-PersistLinks'
)
