<#
.SYNOPSIS
Exports apps in internal JSON format

.CMD
scoop list
scoop cat
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

$AddVersionToUnlockedApps = $false
try {
    $ManagerConfigPath = Join-Path $ProjectRoot 'modules\ManagerConfig.psm1'
    Import-Module $ManagerConfigPath -Force
    if (Get-Command Get-ExportsAddVersionToUnlockedApps -ErrorAction SilentlyContinue) {
        $AddVersionToUnlockedApps = Get-ExportsAddVersionToUnlockedApps -ProjectRoot $ProjectRoot
    }
} catch { }

# Check if Scoop is installed - required for exporting apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load shared modules
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$EnsureConfigPath = Join-Path $ProjectRoot 'modules\ConfigDirectory.psm1'
Import-Module $EnsureConfigPath -Force
$ExtendedListPath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
Import-Module $ExtendedListPath -Force

# Output folder + timestamped filename
$OutDir = New-ConfigDirectory -ProjectRoot $ProjectRoot -Subdirectory "apps"
$stamp = Get-Timestamp
$extJson = Join-Path $OutDir ("export_apps_{0}.json" -f $stamp)

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host "[*] Exporting to: $OutDir"
Write-Host ""

Write-SectionHeader -Title 'EXPORTING APPS (INTERNAL FORMAT)'

# Show what's being exported (extended table shows all versions)
Write-SubsectionHeader -Title 'Current Apps (All Versions)'

# Use extended list to show all installed versions (matches what we export)
Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim

# Get canonical list output for checking if apps are installed
$listOutput = & $ScoopShim list 6>&1
$listText = $listOutput -join "`n"

# Check if there are no apps installed
if ($listText -match "There aren't any apps installed") {
    Write-Host "[*] No apps installed."
    Write-Host ""
    
    $buckets = @()
    $apps = @()
} else {
    Write-SubsectionHeader -Title 'Gathering Bucket Information'
    
    # Load parsing modules
    $ParseBucketPath = Join-Path $ProjectRoot 'modules\ScoopBucketList.psm1'
    Import-Module $ParseBucketPath -Force
    $ParseListPath = Join-Path $ProjectRoot 'modules\ScoopList.psm1'
    Import-Module $ParseListPath -Force
    $GetVersionsPath = Join-Path $ProjectRoot 'modules\InstalledAppVersions.psm1'
    Import-Module $GetVersionsPath -Force
    
    # Get buckets
    $buckets = ConvertFrom-ScoopBucketList -ScoopShim $ScoopShim
    
    # Get current version from scoop list (still needed for version info)
    Write-SubsectionHeader -Title 'Analyzing Installed Apps'
    
    $appCurrentVersion = @{}  # app name -> current version string
    
    $apps = ConvertFrom-ScoopList -ScoopShim $ScoopShim
    foreach ($app in $apps) {
        $appCurrentVersion[$app.Name] = $app.Version
    }
    
    # Scan apps directory to find ALL installed versions
    # Scoop stores versions in separate directories: apps\appname\version\
    # The 'current' symlink points to the active version directory
    Write-SubsectionHeader -Title 'Scanning for All Installed Versions'
    
    $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
    $appVersionsMap = $versionsData.AppVersions
    $appCurrentDirVersion = $versionsData.CurrentVersions
    $pinnedVersions = $versionsData.PinnedVersions
    $heldAppsMap = $versionsData.HeldApps  # Use install.json as source of truth for hold status
    
    # Try to exclude dependencies by checking install.json
    Write-SubsectionHeader -Title 'Detecting Dependencies'
    $explicitlyInstalled = @{}  # app name -> true if explicitly installed (not a dependency)
    
    $appsDir = Join-Path $ScoopRoot 'apps'
    foreach ($appName in $appVersionsMap.Keys) {
        $installJsonPath = Join-Path $appsDir "$appName\current\install.json"
        $isExplicit = $true  # Default to explicit if we can't determine
        
        if (Test-Path $installJsonPath) {
            $installInfo = Get-Content -Raw -Path $installJsonPath | ConvertFrom-Json
            # Check for dependency indicators
            if ($installInfo.PSObject.Properties.Name -contains 'installed_by' -or
                $installInfo.PSObject.Properties.Name -contains 'installed_as_dependency') {
                $isExplicit = $false
                Write-Host "  [SKIP] $appName (detected as dependency)"
            }
        }
        
        $explicitlyInstalled[$appName] = $isExplicit
    }
    
    # Helper function to find latest version from an array of version strings
    # Uses semantic versioning comparison when possible, falls back to string comparison
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
                # If version can't be parsed (e.g., "1.2.3-beta"), use string comparison
                # Compare as strings - this is a fallback for non-standard version formats
                if ($version -gt $latest) {
                    $latest = $version
                }
            }
        }
        return $latest
    }
    
    # Build apps array following golden patterns
    Write-SubsectionHeader -Title 'Building Export with Metadata'
    $apps = @()
    
    foreach ($appName in ($appVersionsMap.Keys | Sort-Object)) {
        # Skip dependencies
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
                # License can be a string or an object with identifier/url
                if ($manifest.license -is [string]) {
                    $license = $manifest.license
                } elseif ($manifest.license.identifier) {
                    $license = $manifest.license.identifier
                }
            }
        }
        
        if ($versions.Count -eq 1) {
            # Single version installed - no current flag needed (it's current by default)
            
            if ($isHeld) {
                # Pattern 2: Single version + held
                # Use version from scoop list, not from directory name
                # Use ordered hashtable to ensure consistent property order: name, version, current, hold, pin, then metadata
                $appEntry = [ordered]@{
                    name = $appName
                    version = $currentVersion
                    hold = $true
                }
                # Check if this version is pinned (add after hold to maintain order)
                if ($appPinnedVersions -contains $currentVersion) {
                    $appEntry['pin'] = $true
                }
                if ($description) { $appEntry['description'] = $description }
                if ($homepage) { $appEntry['homepage'] = $homepage }
                if ($license) { $appEntry['license'] = $license }
                $apps += [pscustomobject]$appEntry
            } else {
                # Pattern 1: Single version + updateable (no current flag for single-version apps)
                # Use ordered hashtable to ensure "name" is always first
                $appEntry = [ordered]@{
                    name = $appName
                }
                if ($AddVersionToUnlockedApps) {
                    $appEntry['version'] = $currentVersion
                }
                if ($description) { $appEntry['description'] = $description }
                if ($homepage) { $appEntry['homepage'] = $homepage }
                if ($license) { $appEntry['license'] = $license }
                $apps += [pscustomobject]$appEntry
            }
        } else {
            # Multiple versions installed (Pattern 3 or Pattern 4)
            # All entries for this app-set must be grouped together
            
            # Get the directory name of the current version (from resolved symlink)
            $currentDirVersion = $appCurrentDirVersion[$appName]
            
            # Determine latest version
            $latestVersion = Get-LatestVersion -VersionStrings $versions
            
            # Step 1: Export pinned versions first (in order they appear in versions array)
            foreach ($version in $versions) {
                if ($appPinnedVersions -contains $version) {
                    # Use ordered hashtable to ensure consistent property order: name, version, current, hold, pin, then metadata
                    $pinnedEntry = [ordered]@{
                        name = $appName
                        version = $version
                    }
                    # Add current flag if this pinned version is current (before pin to maintain order)
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
                # Current is not pinned
                if ($currentDirVersion -eq $latestVersion) {
                    # Current is latest - export as non-versioned entry (updateable)
                    # Use ordered hashtable to ensure "name" is always first
                    $currentEntry = [ordered]@{
                        name = $appName
                    }
                    if (-not $isHeld -and $AddVersionToUnlockedApps) {
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
                    # Current is not latest - export as versioned entry with current flag
                    # Use ordered hashtable to ensure "name" is always first
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
                # If current is not found but app is held, export as versioned entry with hold
                # Use ordered hashtable to ensure "name" is always first
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
            
            # Step 3: Export other non-pinned, non-current versions (if any)
            foreach ($version in $versions) {
                # Skip if this is the current version or if it's pinned (already exported)
                if (($currentDirVersion -and $version -eq $currentDirVersion) -or 
                    ($appPinnedVersions -contains $version)) {
                    continue
                }
                
                # Check if this version is the latest
                if ($version -eq $latestVersion) {
                    # Latest version (but not current and not pinned) - export as non-versioned
                    # Use ordered hashtable to ensure "name" is always first
                    $otherEntry = [ordered]@{
                        name = $appName
                    }
                    if (-not $isHeld -and $AddVersionToUnlockedApps) {
                        $otherEntry['version'] = $version
                    }
                    if ($description) { $otherEntry['description'] = $description }
                    if ($homepage) { $otherEntry['homepage'] = $homepage }
                    if ($license) { $otherEntry['license'] = $license }
                    $apps += [pscustomobject]$otherEntry
                } else {
                    # Non-current, non-pinned, non-latest version entry
                    # Use ordered hashtable to ensure "name" is always first
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
# Resolve path to handle spaces correctly
try {
    $configPath = [System.IO.Path]::GetFullPath($configPath)
} catch {
    # If GetFullPath fails, use as-is (Test-Path will handle it)
}
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

# Use -Depth 3 to avoid deep serialization of complex objects
# ConvertTo-Json produces pretty-printed, human-readable JSON
$jsonContent = $ext | ConvertTo-Json -Depth 3

# Write UTF-8 without BOM (Set-Content with -Encoding UTF8 adds BOM)
Write-TextFileUtf8NoBom -Path $extJson -Content $jsonContent

Write-Host "[OK] Wrote: $extJson"
Write-Host ""

Write-SectionHeader -Title '[OK] Export complete!'

exit 0
