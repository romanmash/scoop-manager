<#
.SYNOPSIS
Shared module for displaying extended app list table

.DESCRIPTION
Provides reusable function to display installed apps in extended table format
with columns: Name, Shim, Version, Update, Hold, Pin, Source

.PARAMETER ScoopRoot
Path to Scoop root directory

.PARAMETER ScoopShim
Path to Scoop shim executable

.PARAMETER ShowUpdates
If true, includes Update column (requires bucket manifest reading)

.EXAMPLE
Import-Module "$PSScriptRoot\..\modules\ExtendedAppList.psm1" -Force
Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim
#>

function Format-AppListTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$AppsList,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$HeldApps,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$PinnedVersions,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$AppSources,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$LatestBucketVersions = @{},
        
        [Parameter(Mandatory=$true)]
        [string]$BucketsDir,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowUpdates = $false,

        # Optional cache: app name -> (version string -> $true).
        # When provided, avoids rebuilding the map in callers that already computed it.
        [Parameter(Mandatory=$false)]
        [hashtable]$InstalledVersionsByApp = $null,

        # Defensive: absorb unexpected default params like -LiteralPath from shell defaults
        [Parameter(Mandatory=$false)]
        [object]$LiteralPath = $null,
        
        [Parameter(Mandatory=$false)]
        [string]$Title = "Installed apps (all versions):"
    )
    
    if ($AppsList.Count -eq 0) {
        return
    }

    function Limit-AppListCellValue {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [string]$Value,

            # Column width as used by "{0,-N}" formatting.
            [Parameter(Mandatory = $true)]
            [int]$Width
        )

        if ([string]::IsNullOrEmpty($Value)) {
            return ''
        }

        # Keep 1 trailing space for readability between adjacent padded columns.
        $maxLen = [Math]::Max(0, $Width - 1)
        if ($Value.Length -le $maxLen) {
            return $Value
        }

        if ($maxLen -le 1) {
            return $Value.Substring(0, $maxLen)
        }

        # 15 chars + "~" (then the formatter adds the final space padding).
        return ($Value.Substring(0, $maxLen - 1) + '~')
    }

    # Column widths (Version/Update are wider to fit longer version strings).
    $versionWidth = 17
    $updateWidth = 17

    # Map installed versions per app for "latest already installed" detection.
    # If the latest bucket version is already installed for an app, we treat it as up-to-date
    # even if older versions also exist.
    $installedVersionsByApp = $InstalledVersionsByApp
    if (-not $installedVersionsByApp) {
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
    }
    
    # Sort by name, then by version (current first)
    $sortedApps = $AppsList | Sort-Object Name, @{Expression={-[int]$_.Current}}, Version
    
    Write-Host $Title
    Write-Host ""
    
    if ($ShowUpdates) {
        Write-Host ("{0,-30}{1,-6}{2,-17}{3,-17}{4,-6}{5,-8}{6}" -f "Name", "Shim", "Version", "Update", "Hold", "Pin", "Source")
        Write-Host ("{0,-30}{1,-6}{2,-17}{3,-17}{4,-6}{5,-8}{6}" -f "----", "----", "-------", "------", "----", "-----", "------")
    } else {
        Write-Host ("{0,-30}{1,-6}{2,-17}{3,-6}{4,-8}{5}" -f "Name", "Shim", "Version", "Hold", "Pin", "Source")
        Write-Host ("{0,-30}{1,-6}{2,-17}{3,-6}{4,-8}{5}" -f "----", "----", "-------", "----", "-----", "------")
    }
    
    $buckets = $null
    if (Test-Path $BucketsDir) {
        $buckets = Get-ChildItem -Path $BucketsDir -Directory
    }
    
    foreach ($app in $sortedApps) {
        $shimCol = if ($app.Current) { "   >" } else { "" }
        $versionCol = Limit-AppListCellValue -Value ([string]$app.Version) -Width $versionWidth
        $updateCol = ""
        $holdCol = ""
        $pinCol = ""
        
        # Get source - prefer from appSources, otherwise try to detect bucket from manifest
        $sourceCol = ""
        if ($AppSources.ContainsKey($app.Name)) {
            $sourceCol = $AppSources[$app.Name]
        } else {
            # Try to detect bucket for this app/version
            if ($buckets) {
                foreach ($bucket in $buckets) {
                    $manifestPath = Join-Path $bucket.FullName "bucket\$($app.Name).json"
                    if (Test-Path $manifestPath) {
                        $sourceCol = $bucket.Name
                        break
                    }
                }
            }
        }
        
        # Show update for any version that has a newer version available in bucket
        if ($ShowUpdates -and $LatestBucketVersions.ContainsKey($app.Name)) {
            $latestVersion = $LatestBucketVersions[$app.Name]
            $currentInstalledVersion = $app.Version

            # If latest is already installed for this app, don't show an update marker.
            $latestAlreadyInstalled = $false
            $latestVersionStr = [string]$latestVersion
            if ($installedVersionsByApp.ContainsKey($app.Name) -and $installedVersionsByApp[$app.Name].ContainsKey($latestVersionStr)) {
                $latestAlreadyInstalled = $true
            }
            
            # Check if latest bucket version is newer than this installed version
            if (-not $latestAlreadyInstalled -and $latestVersion -ne $currentInstalledVersion) {
                $isNewer = $false
                try {
                    if ([version]$latestVersion -gt [version]$currentInstalledVersion) {
                        $isNewer = $true
                    }
                } catch {
                    # If version comparison fails, treat as different (potential update)
                    if ($latestVersion -ne $currentInstalledVersion) {
                        $isNewer = $true
                    }
                }
                
                if ($isNewer) {
                    $updateCol = $latestVersion
                }
            }
        }

        if ($updateCol) {
            $updateCol = Limit-AppListCellValue -Value ([string]$updateCol) -Width $updateWidth
        }
        
        # Show hold status for all versions of held apps
        if ($HeldApps.ContainsKey($app.Name)) {
            $holdCol = "held"
        }
        
        # Show pin status for pinned versions
        if ($PinnedVersions.ContainsKey($app.Name) -and $PinnedVersions[$app.Name] -contains $app.Version) {
            $pinCol = "pinned"
        }
        
        if ($ShowUpdates) {
            Write-Host ("{0,-30}{1,-6}{2,-17}{3,-17}{4,-6}{5,-8}{6}" -f $app.Name, $shimCol, $versionCol, $updateCol, $holdCol, $pinCol, $sourceCol)
        } else {
            Write-Host ("{0,-30}{1,-6}{2,-17}{3,-6}{4,-8}{5}" -f $app.Name, $shimCol, $versionCol, $holdCol, $pinCol, $sourceCol)
        }
    }
    Write-Host ""
}

function Show-ExtendedAppList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowUpdates = $false
    )
    
    # Validate inputs - handle missing Scoop gracefully
    if (-not (Test-Path $ScoopRoot)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        return
    }
    
    if (-not (Test-Path $ScoopShim)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        return
    }
    
    # Get list of held apps using shared UpdatableApps module
    $heldApps = @{}
    try {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
        $heldApps = Get-HeldApps -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
    } catch { }
    
    # Get pinned versions using shared UpdatableApps module
    $pinnedVersions = @{}
    try {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
        $pinnedVersions = Get-PinnedVersions -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
    } catch { }
    
    # Get app sources from scoop list
    $appSources = @{}
    try {
        if (Test-Path $ScoopShim) {
            $ProjectRoot = Split-Path -Parent $PSScriptRoot
            Assert-ExternalCommandRunner -Caller 'Show-ExtendedAppList'

            $listCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$false -NoHostOutput
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
                    # Parse: Name Version Source ... (Source is the 3rd field)
                    # Handle lines that might have "Held package" or other text
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
                        # If source is "<auto-generated>", we'll try to detect bucket below
                        if ($source -ne '<auto-generated>') {
                            # Normalize source: if it's a path, extract bucket name
                            # Path format: D:\path\buckets\bucketname\bucket\app.json
                            if ($source -match '[\\/]buckets[\\/]([^\\/]+)[\\/]') {
                                $appSources[$appName] = $Matches[1]
                            } elseif ($source -match '^[a-zA-Z]:[\\/]') {
                                # It's a full path but didn't match bucket pattern - try to extract from path
                                # Look for bucket name in the path structure
                                if ($source -match '[\\/]([^\\/]+)[\\/]bucket[\\/]') {
                                    $appSources[$appName] = $Matches[1]
                                } else {
                                    # Fallback: use as-is if we can't parse
                                    $appSources[$appName] = $source
                                }
                            } else {
                                # Not a path, use as-is (should be bucket name)
                                $appSources[$appName] = $source
                            }
                        }
                    }
                }
            }
        }
    } catch { }
    
    # For apps with "<auto-generated>" source, try to detect bucket from manifest
    $bucketsDir = Join-Path $ScoopRoot 'buckets'
    if (Test-Path $bucketsDir) {
        $buckets = Get-ChildItem -Path $bucketsDir -Directory
        foreach ($appName in $appSources.Keys) {
            if ($appSources[$appName] -eq '<auto-generated>') {
                # Try to find bucket for this app
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
    
    # Also check for apps that might not be in scoop list output but exist in directories
    # This handles cases where scoop list parsing might miss some apps
    $appsDir = Join-Path $ScoopRoot 'apps'
    if (Test-Path $appsDir) {
        Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
            $appName = $_.Name
            if ($appName -eq 'scoop') { return }
            if (-not $appSources.ContainsKey($appName)) {
                # Try to find bucket for this app
                if (Test-Path $bucketsDir) {
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
    
    # Get latest bucket versions for all apps (if ShowUpdates is enabled)
    $latestBucketVersions = @{}  # app name -> latest version from bucket
    if ($ShowUpdates) {
        try {
            $bucketsDir = Join-Path $ScoopRoot 'buckets'
            if (Test-Path $bucketsDir) {
                $buckets = Get-ChildItem -Path $bucketsDir -Directory
                # Get all unique app names from installed apps
                $appsDir = Join-Path $ScoopRoot 'apps'
                $allAppNames = @()
                if (Test-Path $appsDir) {
                    $allAppNames = Get-ChildItem -Path $appsDir -Directory | 
                                  Where-Object { $_.Name -ne 'scoop' } | 
                                  Select-Object -ExpandProperty Name
                }
                
                # Check bucket manifests for all apps
                foreach ($appName in $allAppNames) {
                    foreach ($bucket in $buckets) {
                        $manifestPath = Join-Path $bucket.FullName "bucket\$appName.json"
                        if (Test-Path $manifestPath) {
                            try {
                                $manifestContent = Get-Content -Raw -Path $manifestPath
                                $manifest = $manifestContent | ConvertFrom-Json
                                if ($manifest.version) {
                                    $latestBucketVersions[$appName] = $manifest.version
                                    break
                                }
                            } catch { }
                        }
                    }
                }
            }
        } catch { }
    }
    
    # Collect all apps and their versions
    $appsDir = Join-Path $ScoopRoot 'apps'
    $appsList = @()
    if (Test-Path $appsDir) {
        Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
            $appName = $_.Name
            if ($appName -eq 'scoop') { return }
            
            # Get all version directories (exclude 'current' symlink)
            $versions = Get-ChildItem -Path $_.FullName -Directory | 
                       Where-Object { $_.Name -ne 'current' } | 
                       Select-Object -ExpandProperty Name
            
            if ($versions -and $versions.Count -gt 0) {
                # Resolve current symlink
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
                
                # Add each version as a separate entry
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
    
    # Display in table format using shared function
    if ($appsList.Count -gt 0) {
        # Map installed versions per app for "latest already installed" checks in the summary.
        $installedVersionsByApp = @{}
        foreach ($entry in $appsList) {
            $name = [string]$entry.Name
            $ver  = [string]$entry.Version
            if (-not $name -or -not $ver) { continue }
            if (-not $installedVersionsByApp.ContainsKey($name)) {
                $installedVersionsByApp[$name] = @{}
            }
            $installedVersionsByApp[$name][$ver] = $true
        }

        Format-AppListTable -AppsList $appsList `
                            -HeldApps $heldApps `
                            -PinnedVersions $pinnedVersions `
                            -AppSources $appSources `
                            -LatestBucketVersions $latestBucketVersions `
                            -BucketsDir $bucketsDir `
                            -ShowUpdates:$ShowUpdates `
                            -InstalledVersionsByApp $installedVersionsByApp
        
        # Summary
        $totalApps = ($appsList | Select-Object -Unique Name).Count
        $totalVersions = $appsList.Count
        $heldCount = $heldApps.Count

        # Calculate pinned versions count once (shown in summary regardless of ShowUpdates)
        $pinnedVersionsCount = 0
        foreach ($appName in $pinnedVersions.Keys) {
            $appPinnedVersions = $pinnedVersions[$appName]
            if ($appPinnedVersions -is [array]) {
                $pinnedVersionsCount += $appPinnedVersions.Count
            } else {
                $pinnedVersionsCount += 1
            }
        }

        Write-Host "Apps: $totalApps"
        Write-Host "Held apps: $heldCount"
        Write-Host "Versions: $totalVersions"
        Write-Host "Pinned versions: $pinnedVersionsCount"

        if ($ShowUpdates) {
            # Count updates for held apps
            $heldAppsWithUpdates = 0
            foreach ($heldAppName in $heldApps.Keys) {
                if ($latestBucketVersions.ContainsKey($heldAppName)) {
                    $latestVersion = $latestBucketVersions[$heldAppName]
                    # Check if any version of this held app has an update
                    $heldAppVersions = $appsList | Where-Object { $_.Name -eq $heldAppName }
                    foreach ($app in $heldAppVersions) {
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
                                $heldAppsWithUpdates++
                                break
                            }
                        }
                    }
                }
            }
            if ($heldAppsWithUpdates -gt 0) {
                Write-Host "Updates for held: $heldAppsWithUpdates"
            }
            
            # Count updates for pinned versions
            $pinnedVersionsWithUpdates = 0
            foreach ($appName in $pinnedVersions.Keys) {
                if ($latestBucketVersions.ContainsKey($appName)) {
                    $latestVersion = $latestBucketVersions[$appName]
                    # Check each pinned version of this app for updates
                    $appPinnedVersions = $pinnedVersions[$appName]
                    if ($appPinnedVersions -isnot [array]) {
                        $appPinnedVersions = @($appPinnedVersions)
                    }
                    foreach ($pinnedVer in $appPinnedVersions) {
                        $pinnedVerStr = [string]$pinnedVer
                        if ($latestVersion -ne $pinnedVerStr) {
                            $isNewer = $false
                            try {
                                if ([version]$latestVersion -gt [version]$pinnedVerStr) {
                                    $isNewer = $true
                                }
                            } catch {
                                if ($latestVersion -ne $pinnedVerStr) {
                                    $isNewer = $true
                                }
                            }
                            if ($isNewer) {
                                $pinnedVersionsWithUpdates++
                            }
                        }
                    }
                }
            }
            if ($pinnedVersionsWithUpdates -gt 0) {
                Write-Host "Updates for pinned: $pinnedVersionsWithUpdates"
            }
            
            # Count versions to be updated (non-held, non-pinned versions with updates)
            $versionsToUpdate = 0
            foreach ($app in $appsList) {
                # Skip if app is held
                if ($heldApps.ContainsKey($app.Name)) {
                    continue
                }

                # If latest is already installed for this app, treat it as up-to-date.
                if ($latestBucketVersions.ContainsKey($app.Name)) {
                    $latestVerStr = [string]$latestBucketVersions[$app.Name]
                    if ($installedVersionsByApp.ContainsKey($app.Name) -and $installedVersionsByApp[$app.Name].ContainsKey($latestVerStr)) {
                        continue
                    }
                }
                
                # Skip if this specific version is pinned
                $isPinned = $false
                if ($pinnedVersions.ContainsKey($app.Name)) {
                    $appPinnedVersions = $pinnedVersions[$app.Name]
                    if ($appPinnedVersions -isnot [array]) {
                        $appPinnedVersions = @($appPinnedVersions)
                    }
                    $appVersionStr = [string]$app.Version
                    foreach ($pinnedVer in $appPinnedVersions) {
                        $pinnedVerStr = [string]$pinnedVer
                        if ($appVersionStr -eq $pinnedVerStr) {
                            $isPinned = $true
                            break
                        }
                    }
                }
                if ($isPinned) {
                    continue
                }
                
                # Check if update is available
                if ($latestBucketVersions.ContainsKey($app.Name)) {
                    $latestVersion = $latestBucketVersions[$app.Name]
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
                            $versionsToUpdate++
                        }
                    }
                }
            }
            if ($versionsToUpdate -gt 0) {
                Write-Host "Versions to be updated: $versionsToUpdate"
            } else {
                Write-Host "Versions to be updated: 0"
            }
        }
    } else {
        Write-Host "No apps installed."
    }
    
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Show-ExtendedAppList'
    'Format-AppListTable'
)
