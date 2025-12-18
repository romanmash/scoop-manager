<#
.SYNOPSIS
Apps configuration export operations

.DESCRIPTION
Provides functions for exporting apps configuration to JSON file.

.EXAMPLE
Import-Module "$PSScriptRoot\ExportApps.psm1" -Force
$exportPath = Export-AppsConfiguration -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -Timestamp $timestamp
#>

function Export-AppsConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$true)]
        [string]$Timestamp
    )
    
    # Load required modules
    $ConfigDirectoryPath = Join-Path $PSScriptRoot 'ConfigDirectory.psm1'
    Import-Module $ConfigDirectoryPath -Force
    $ScoopBucketListPath = Join-Path $PSScriptRoot 'ScoopBucketList.psm1'
    Import-Module $ScoopBucketListPath -Force
    $ScoopListPath = Join-Path $PSScriptRoot 'ScoopList.psm1'
    Import-Module $ScoopListPath -Force
    $InstalledAppVersionsPath = Join-Path $PSScriptRoot 'InstalledAppVersions.psm1'
    Import-Module $InstalledAppVersionsPath -Force
    $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
    Import-Module $ManagerConfigPath -Force
    
    # Output folder + timestamped filename
    $OutDir = New-ConfigDirectory -ProjectRoot $ProjectRoot -Subdirectory "apps"
    $extJson = Join-Path $OutDir ("export_apps_{0}.json" -f $Timestamp)

    $addVersionToUnlockedApps = $false
    try {
        if (Get-Command Get-ExportsAddVersionToUnlockedApps -ErrorAction SilentlyContinue) {
            $addVersionToUnlockedApps = Get-ExportsAddVersionToUnlockedApps -ProjectRoot $ProjectRoot
        }
    } catch { }
    
    # Get canonical list output for checking if apps are installed
    $listOutput = & $ScoopShim list 6>&1
    $listText = $listOutput -join "`n"
    
    # Check if there are no apps installed
    if ($listText -match "There aren't any apps installed") {
        $buckets = @()
        $apps = @()
    } else {
        # Get buckets
        $buckets = ConvertFrom-ScoopBucketList -ScoopShim $ScoopShim
        
        # Scan apps directory to find ALL installed versions
        $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
        $appVersionsMap = $versionsData.AppVersions
        $appCurrentDirVersion = $versionsData.CurrentVersions
        $pinnedVersions = $versionsData.PinnedVersions
        $heldAppsMap = $versionsData.HeldApps  # Use install.json as source of truth for hold status
        
        # Get current version from scoop list (still needed for version info)
        $appCurrentVersion = @{}
        $parsedApps = ConvertFrom-ScoopList -ScoopShim $ScoopShim
        foreach ($app in $parsedApps) {
            $appCurrentVersion[$app.Name] = $app.Version
        }
        
        # Try to exclude dependencies by checking install.json
        $explicitlyInstalled = @{}
        
        $appsDir = Join-Path $ScoopRoot 'apps'
        foreach ($appName in $appVersionsMap.Keys) {
            $installJsonPath = Join-Path $appsDir "$appName\current\install.json"
            $isExplicit = $true
            
            if (Test-Path $installJsonPath) {
                $installInfo = Get-Content -Raw -Path $installJsonPath | ConvertFrom-Json
                if ($installInfo.PSObject.Properties.Name -contains 'installed_by' -or
                    $installInfo.PSObject.Properties.Name -contains 'installed_as_dependency') {
                    $isExplicit = $false
                }
            }
            
            $explicitlyInstalled[$appName] = $isExplicit
        }
        
        # Helper function to find latest version (internal - not exported)
        function Get-LatestVersion {
            param([string[]]$VersionStrings)
            
            if ($VersionStrings.Count -eq 0) { return $null }
            if ($VersionStrings.Count -eq 1) { return $VersionStrings[0] }
            
            $latest = $VersionStrings[0]
            foreach ($version in $VersionStrings) {
                try {
                    $ver = [version]$version
                    $latestVer = [version]$latest
                    if ($ver -gt $latestVer) {
                        $latest = $version
                    }
                } catch {
                    if ($version -gt $latest) {
                        $latest = $version
                    }
                }
            }
            return $latest
        }
        
        # Build apps array following golden patterns (same logic as script 71)
        $apps = @()
        
        foreach ($appName in ($appVersionsMap.Keys | Sort-Object)) {
            if (-not $explicitlyInstalled[$appName]) { continue }
            
            $versions = $appVersionsMap[$appName]
            $currentVersion = $appCurrentVersion[$appName]
            $isHeld = $heldAppsMap.ContainsKey($appName)  # Use install.json-based hold detection
            $appPinnedVersions = if ($pinnedVersions.ContainsKey($appName)) { $pinnedVersions[$appName] } else { @() }
            
            # Get manifest metadata
            $description = $null
            $homepage = $null
            $license = $null
            $manifestOutput = & $ScoopShim cat $appName 2>&1 | Out-String
            if ($manifestOutput) {
                $manifest = $manifestOutput | ConvertFrom-Json
                if ($manifest.description) { $description = $manifest.description }
                if ($manifest.homepage) { $homepage = $manifest.homepage }
                if ($manifest.license) {
                    if ($manifest.license -is [string]) {
                        $license = $manifest.license
                    } elseif ($manifest.license.identifier) {
                        $license = $manifest.license.identifier
                    }
                }
            }
            
            if ($versions.Count -eq 1) {
                # Single version installed
                if ($isHeld) {
                    $appEntry = [ordered]@{
                        name = $appName
                        version = $currentVersion
                        hold = $true
                    }
                    if ($appPinnedVersions -contains $currentVersion) {
                        $appEntry['pin'] = $true
                    }
                    if ($description) { $appEntry['description'] = $description }
                    if ($homepage) { $appEntry['homepage'] = $homepage }
                    if ($license) { $appEntry['license'] = $license }
                    $apps += [pscustomobject]$appEntry
                } else {
                    $appEntry = [ordered]@{
                        name = $appName
                    }
                    if ($addVersionToUnlockedApps) {
                        $appEntry['version'] = $currentVersion
                    }
                    if ($description) { $appEntry['description'] = $description }
                    if ($homepage) { $appEntry['homepage'] = $homepage }
                    if ($license) { $appEntry['license'] = $license }
                    $apps += [pscustomobject]$appEntry
                }
            } else {
                # Multiple versions installed
                $currentDirVersion = $appCurrentDirVersion[$appName]
                $latestVersion = Get-LatestVersion -VersionStrings $versions
                
                # Step 1: Export pinned versions first
                foreach ($version in $versions) {
                    if ($appPinnedVersions -contains $version) {
                        $pinnedEntry = [ordered]@{
                            name = $appName
                            version = $version
                        }
                        if ($currentDirVersion -and $version -eq $currentDirVersion) {
                            $pinnedEntry['current'] = $true
                        }
                        $pinnedEntry['pin'] = $true
                        if ($description) { $pinnedEntry['description'] = $description }
                        if ($homepage) { $pinnedEntry['homepage'] = $homepage }
                        if ($license) { $pinnedEntry['license'] = $license }
                        $apps += [pscustomobject]$pinnedEntry
                    }
                }
                
                # Step 2: Export current version
                if ($currentDirVersion -and -not ($appPinnedVersions -contains $currentDirVersion)) {
                    if ($currentDirVersion -eq $latestVersion) {
                        $currentEntry = [ordered]@{
                            name = $appName
                        }
                        if (-not $isHeld -and $addVersionToUnlockedApps) {
                            $currentEntry['version'] = $currentDirVersion
                        }
                        $currentEntry['current'] = $true
                        if ($isHeld) {
                            $currentEntry['hold'] = $true
                        }
                        if ($description) { $currentEntry['description'] = $description }
                        if ($homepage) { $currentEntry['homepage'] = $homepage }
                        if ($license) { $currentEntry['license'] = $license }
                        $apps += [pscustomobject]$currentEntry
                    } else {
                        $currentEntry = [ordered]@{
                            name = $appName
                            version = $currentDirVersion
                            current = $true
                        }
                        if ($isHeld) {
                            $currentEntry['hold'] = $true
                        }
                        if ($description) { $currentEntry['description'] = $description }
                        if ($homepage) { $currentEntry['homepage'] = $homepage }
                        if ($license) { $currentEntry['license'] = $license }
                        $apps += [pscustomobject]$currentEntry
                    }
                } elseif ($isHeld -and -not $currentDirVersion) {
                    $currentEntry = [ordered]@{
                        name = $appName
                        version = $currentVersion
                        hold = $true
                    }
                    if ($description) { $currentEntry['description'] = $description }
                    if ($homepage) { $currentEntry['homepage'] = $homepage }
                    if ($license) { $currentEntry['license'] = $license }
                    $apps += [pscustomobject]$currentEntry
                }
                
                # Step 3: Export other non-pinned, non-current versions
                foreach ($version in $versions) {
                    if (($currentDirVersion -and $version -eq $currentDirVersion) -or 
                        ($appPinnedVersions -contains $version)) {
                        continue
                    }
                    
                    if ($version -eq $latestVersion) {
                        $otherEntry = [ordered]@{
                            name = $appName
                        }
                        if (-not $isHeld -and $addVersionToUnlockedApps) {
                            $otherEntry['version'] = $version
                        }
                        if ($description) { $otherEntry['description'] = $description }
                        if ($homepage) { $otherEntry['homepage'] = $homepage }
                        if ($license) { $otherEntry['license'] = $license }
                        $apps += [pscustomobject]$otherEntry
                    } else {
                        $otherEntry = [ordered]@{
                            name = $appName
                            version = $version
                        }
                        if ($description) { $otherEntry['description'] = $description }
                        if ($homepage) { $otherEntry['homepage'] = $homepage }
                        if ($license) { $otherEntry['license'] = $license }
                        $apps += [pscustomobject]$otherEntry
                    }
                }
            }
        }
    }
    
    # Read config.json if it exists
    $config = $null
    $configPath = Join-Path $ScoopRoot 'config.json'
    if (Test-Path $configPath) {
        try {
            $configContent = Get-Content -Raw -Path $configPath
            $config = $configContent | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to read config.json: $($_.Exception.Message)"
            $config = $null
        }
    }
    
    # Build export matching init_apps.json format
    $ext = [pscustomobject]@{
        buckets = $buckets
        apps = $apps
    }
    
    # Add config key if config.json was read successfully
    if ($null -ne $config) {
        $ext | Add-Member -MemberType NoteProperty -Name 'config' -Value $config -Force
    }
    
    # Write JSON export
    try {
        Write-JsonFileUtf8NoBom -Path $extJson -Object $ext -Depth 3
        return $extJson
    } catch {
        Write-Warning "Failed to export apps configuration: $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function @(
    'Export-AppsConfiguration'
)
