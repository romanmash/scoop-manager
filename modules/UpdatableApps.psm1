<#
.SYNOPSIS
Shared module for detecting updatable apps and app metadata

.DESCRIPTION
Provides functions to detect which apps can be updated by filtering out held apps
and pinned versions. This module centralizes the logic shared between the check
updates script (41) and the update apps script (42).

Get-HeldApps uses metadata-based detection (reads from install.json files) which
is more reliable than parsing console output. This provides consistent hold detection
across all scripts in the project.

.EXAMPLE
Import-Module "$PSScriptRoot\UpdatableApps.psm1" -Force
$heldApps = Get-HeldApps -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
$pinnedVersions = Get-PinnedVersions -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
$updatableVersions = Get-UpdatableVersions -AppsList $appsList -HeldApps $heldApps -PinnedVersions $pinnedVersions -LatestBucketVersions $latestBucketVersions

.NOTES
Get-HeldApps is the centralized function for hold detection used throughout the project.
It reads from install.json files via Get-InstalledAppVersions, providing consistent
metadata-based detection instead of unreliable console output parsing.
#>

function Get-HeldApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$false)]
        [string]$ProjectRoot
    )
    
    $heldApps = @{}
    try {
        # Use install.json as source of truth for hold status (metadata-based detection)
        # Reads from apps/<app>/current/install.json files instead of parsing console output
        if (-not (Get-Command Get-InstalledAppVersions -ErrorAction SilentlyContinue)) {
            if ($ProjectRoot) {
                $InstalledAppVersionsPath = Join-Path $ProjectRoot 'modules\InstalledAppVersions.psm1'
            } else {
                $InstalledAppVersionsPath = Join-Path $PSScriptRoot 'InstalledAppVersions.psm1'
            }
            if (-not (Test-Path $InstalledAppVersionsPath)) {
                throw "InstalledAppVersions module not found at: $InstalledAppVersionsPath"
            }
            Import-Module $InstalledAppVersionsPath -Force -ErrorAction Stop
        }
        
        $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
        if ($versionsData -and $versionsData.HeldApps) {
            $heldApps = $versionsData.HeldApps
        }
    } catch {
        Write-Warning "Failed to detect held apps from install.json: $($_.Exception.Message)"
    }
    return $heldApps
}

function Get-PinnedVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    $pinnedVersions = @{}
    try {
        # Ensure module is available (re-import if needed)
        if (-not (Get-Command Get-InstalledAppVersions -ErrorAction SilentlyContinue)) {
            $GetVersionsPath = Join-Path $ProjectRoot 'modules\InstalledAppVersions.psm1'
            if (-not (Test-Path $GetVersionsPath)) {
                throw "InstalledAppVersions module not found at: $GetVersionsPath"
            }
            Import-Module $GetVersionsPath -Force -ErrorAction Stop
        }
        $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
        $pinnedVersions = $versionsData.PinnedVersions
    } catch {
        Write-Warning "Failed to load pinned versions: $($_.Exception.Message)"
    }
    return $pinnedVersions
}

function Get-AppSources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    $appSources = @{}
    $bucketsDir = Join-Path $ScoopRoot 'buckets'
    try {
        if (Test-Path $ScoopShim) {
            $projectRoot = Split-Path -Parent $PSScriptRoot
            Assert-ExternalCommandRunner -Caller 'Get-AppSources'

            $listCmd = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$false -NoHostOutput
            $listOutput = if ($listCmd.Output) { $listCmd.Output -split "\r?\n" } else { @() }
            $inTable = $false
            foreach ($line in $listOutput) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^Name\s+Version') {
                    $inTable = $true
                    continue
                }
                if ($trimmed -match '^----') {
                    continue
                }
                if ($inTable -and $trimmed -and $trimmed -notmatch '^Installed apps:') {
                    # Handle paths with spaces by intelligently splitting the line
                    $appName = $null
                    $version = $null
                    $source = $null
                    
                    # Split line by whitespace, but handle paths with spaces
                    $tokens = $trimmed -split '\s+'
                    if ($tokens.Count -ge 3) {
                        $appName = $tokens[0]
                        $version = $tokens[1]
                        $source = $tokens[2]
                        
                        # If source starts with drive letter, it's likely a path - collect tokens until we find path end markers
                        if ($source -match '^[a-zA-Z]:') {
                            $pathParts = @($source)
                            for ($i = 3; $i -lt $tokens.Count; $i++) {
                                $pathParts += $tokens[$i]
                                $combinedPath = ($pathParts -join ' ').Trim()
                                
                                # Stop conditions (in order of reliability):
                                # 1. Path ends with .json (most reliable - indicates complete manifest path)
                                # 2. Path contains \bucket\ (Scoop bucket structure)
                                # 3. Next token is a keyword like "Held", "pinned" (indicates path ended, keyword follows)
                                if ($combinedPath -match '\.json$' -or 
                                    $combinedPath -match '\\bucket\\' -or
                                    ($i + 1 -lt $tokens.Count -and $tokens[$i + 1] -match '^(Held|pinned|auto-generated)$')) {
                                    # Path is complete
                                    break
                                }
                            }
                            $source = ($pathParts -join ' ').Trim()
                        }
                    }
                    
                    if ($appName -and $source) {
                        if ($source -ne '<auto-generated>') {
                            if ($source -match '[\\/]buckets[\\/]([^\\/]+)[\\/]') {
                                $appSources[$appName] = $Matches[1]
                            } elseif ($source -match '[\\/]([^\\/]+)[\\/]bucket[\\/]') {
                                $appSources[$appName] = $Matches[1]
                            } else {
                                $appSources[$appName] = $source
                            }
                        }
                    }
                }
            }
        }
        
        # For apps with "<auto-generated>" source, try to detect bucket from manifest
        if (Test-Path $bucketsDir) {
            $buckets = Get-ChildItem -Path $bucketsDir -Directory
            foreach ($appName in $appSources.Keys) {
                if ($appSources[$appName] -eq '<auto-generated>') {
                    foreach ($bucket in $buckets) {
                        $manifestPath = Join-Path $bucket.FullName "bucket\$appName.json"
                        if (Test-Path $manifestPath) {
                            $appSources[$appName] = $bucket.Name
                            break
                        }
                    }
                }
            }
            
            # For apps not in appSources, try to find their bucket
            $appsDir = Join-Path $ScoopRoot 'apps'
            if (Test-Path $appsDir) {
                Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
                    $appName = $_.Name
                    if ($appName -eq 'scoop') { return }
                    if (-not $appSources.ContainsKey($appName)) {
                        foreach ($bucket in $buckets) {
                            $manifestPath = Join-Path $bucket.FullName "bucket\$appName.json"
                            if (Test-Path $manifestPath) {
                                $appSources[$appName] = $bucket.Name
                                break
                            }
                        }
                    }
                }
            }
        }
    } catch { }
    return $appSources
}

function Get-LatestBucketVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$AppSources
    )
    
    $latestBucketVersions = @{}
    $bucketsDir = Join-Path $ScoopRoot 'buckets'
    try {
        if (Test-Path $bucketsDir) {
            foreach ($appName in $AppSources.Keys) {
                $bucketName = $AppSources[$appName]
                $bucketPath = Join-Path $bucketsDir $bucketName
                if (Test-Path $bucketPath) {
                    $manifestPath = Join-Path $bucketPath "bucket\$appName.json"
                    if (Test-Path $manifestPath) {
                        try {
                            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
                            if ($manifest.version) {
                                $latestBucketVersions[$appName] = $manifest.version
                            }
                        } catch { }
                    }
                }
            }
        }
    } catch { }
    return $latestBucketVersions
}

function Get-InstalledAppsList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    # Initialize to empty array - ensures we always return an array (never null)
    $appsList = @()

    try {
        $appsDir = Join-Path $ScoopRoot 'apps'
        if (Test-Path $appsDir) {
            Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
                $appName = $_.Name
                if ($appName -eq 'scoop') { return }

                $versions = Get-ChildItem -Path $_.FullName -Directory |
                           Where-Object { $_.Name -ne 'current' } |
                           Select-Object -ExpandProperty Name
                
                if ($versions -and $versions.Count -gt 0) {
                    $currentLink = Join-Path $_.FullName 'current'
                    $currentVersion = $null
                    if (Test-Path $currentLink) {
                        try {
                            $target = (Get-Item $currentLink).Target
                            if ($target) {
                                $currentVersion = Split-Path -Leaf $target
                            }
                        } catch { }
                    }

                    foreach ($version in $versions) {
                        $isCurrent = ($version -eq $currentVersion)
                        $appsList += [pscustomobject]@{
                            Name = $appName
                            Version = $version
                            Current = $isCurrent
                        }
                    }
                }
            }
        }
    } catch {
        # On any error, return empty array
        Write-Warning "Error getting installed apps list: $($_.Exception.Message)"
        $appsList = @()
    }

    # Always return an array (never null) - handle edge cases in one place
    if ($null -eq $appsList -or $appsList -isnot [array]) {
        return @()
    }
    return $appsList
}

function Get-UpdatableVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [array]$AppsList = @(),
        
        [Parameter(Mandatory=$true)]
        [hashtable]$HeldApps,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$PinnedVersions,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$LatestBucketVersions
    )

    # Handle null or invalid AppsList parameter (defensive programming)
    # Default value handles most cases, but this check provides additional safety
    if ($null -eq $AppsList -or $AppsList -isnot [array]) {
        return @()
    }

    # If the latest bucket version is already installed for an app (any version folder),
    # treat that app as up-to-date even if older versions also exist.
    $installedVersionsByApp = @{}
    foreach ($entry in $AppsList) {
        $name = [string]$entry.Name
        $ver  = [string]$entry.Version
        if (-not $name -or -not $ver) { continue }
        if (-not $installedVersionsByApp.ContainsKey($name)) {
            $installedVersionsByApp[$name] = @{}
        }
        $installedVersionsByApp[$name][$ver] = $true
    }
    
    $updatableVersions = @()
    foreach ($app in $AppsList) {
        # Skip if app is held (all versions of held apps cannot be updated)
        if ($HeldApps.ContainsKey($app.Name)) {
            continue
        }

        # If the latest version is already installed for this app, skip all updates for it.
        if ($LatestBucketVersions.ContainsKey($app.Name)) {
            $latestVersionStr = [string]$LatestBucketVersions[$app.Name]
            if ($installedVersionsByApp.ContainsKey($app.Name) -and $installedVersionsByApp[$app.Name].ContainsKey($latestVersionStr)) {
                continue
            }
        }
        
        # Skip if this specific version is pinned (pinned versions cannot be updated)
        if ($PinnedVersions.ContainsKey($app.Name)) {
            $appPinnedVersions = $PinnedVersions[$app.Name]
            # Ensure it's an array
            if ($appPinnedVersions -isnot [array]) {
                $appPinnedVersions = @($appPinnedVersions)
            }
            # Check if this version is in the pinned list
            # Convert both to strings to ensure exact match
            $appVersionStr = [string]$app.Version
            $isPinned = $false
            foreach ($pinnedVer in $appPinnedVersions) {
                $pinnedVerStr = [string]$pinnedVer
                if ($appVersionStr -eq $pinnedVerStr) {
                    $isPinned = $true
                    break
                }
            }
            if ($isPinned) {
                continue
            }
        }
        
        # Check if update is available
        if ($LatestBucketVersions.ContainsKey($app.Name)) {
            $latestVersion = $LatestBucketVersions[$app.Name]
            $installedVersion = $app.Version
            
            if ($latestVersion -ne $installedVersion) {
                $isNewer = $false
                try {
                    if ([version]$latestVersion -gt [version]$installedVersion) {
                        $isNewer = $true
                    }
                } catch {
                    if ($latestVersion -ne $installedVersion) {
                        $isNewer = $true
                    }
                }
                
                if ($isNewer) {
                    $updatableVersions += $app
                }
            }
        }
    }
    # Ensure we always return an array (PowerShell might unwrap single-item arrays)
    if ($updatableVersions -isnot [array]) {
        if ($updatableVersions) {
            return @($updatableVersions)
        } else {
            return @()
        }
    }
    return $updatableVersions
}

Export-ModuleMember -Function @(
    'Get-HeldApps',
    'Get-PinnedVersions',
    'Get-AppSources',
    'Get-LatestBucketVersions',
    'Get-InstalledAppsList',
    'Get-UpdatableVersions'
)
