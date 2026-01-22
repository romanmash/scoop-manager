<#
.SYNOPSIS
Shared module for scanning apps directory to get all installed versions and metadata

.DESCRIPTION
Scans the Scoop apps directory to find all installed versions of each app.
Also resolves the 'current' symlink to determine which version is active.
Detects pinned versions (via .pin files) and held apps (via install.json files).

.PARAMETER ScoopRoot
Path to Scoop root directory

.EXAMPLE
Import-Module "$PSScriptRoot\InstalledAppVersions.psm1" -Force
$versions = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
$heldApps = $versions.HeldApps  # Get held apps map

.NOTES
Returns a hashtable with:
- AppVersions: app name -> array of version strings
- CurrentVersions: app name -> current version directory name
- PinnedVersions: app name -> array of pinned version strings
- HeldApps: app name -> $true if held (reads from install.json files)
#>

function Get-InstalledAppVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    $appsDir = Join-Path $ScoopRoot 'apps'
    $result = @{
        AppVersions = @{}      # app name -> array of version strings
        CurrentVersions = @{}  # app name -> current version directory name
        PinnedVersions = @{}   # app name -> array of pinned version strings
        HeldApps = @{}         # app name -> $true if held (based on install.json)
    }
    
    if (-not (Test-Path $appsDir)) {
        return $result
    }
    
    Get-ChildItem -Path $appsDir -Directory | ForEach-Object {
        $appName = $_.Name
        if ($appName -eq 'scoop') { return }
        
        # Get all version directories (exclude 'current' symlink)
        $versions = Get-ChildItem -Path $_.FullName -Directory | 
                   Where-Object { $_.Name -ne 'current' } | 
                   Select-Object -ExpandProperty Name
        
        if ($versions -and $versions.Count -gt 0) {
            # Sort versions descending (latest first) without throwing on non-semver strings
            $sortable = foreach ($version in $versions) {
                $rawVersion = [string]$version
                $parsed = $null
                $isParsed = [version]::TryParse($rawVersion, [ref]$parsed)
                if (-not $isParsed) {
                    # Best-effort: parse numeric prefix (e.g., "3.0.6-1" => "3.0.6")
                    if ($rawVersion -match '^[vV]?(\d+(?:\.\d+){0,3})') {
                        $candidate = $Matches[1]
                        $isParsed = [version]::TryParse($candidate, [ref]$parsed)
                    }
                }
                [pscustomobject]@{
                    Raw = $rawVersion
                    IsParsed = if ($isParsed) { 0 } else { 1 }
                    Parsed = if ($isParsed) { $parsed } else { [version]'0.0.0.0' }
                }
            }
            $sortedVersions = $sortable |
                Sort-Object IsParsed, @{ Expression = { $_.Parsed }; Descending = $true }, @{ Expression = { $_.Raw }; Descending = $true } |
                Select-Object -ExpandProperty Raw
            $result.AppVersions[$appName] = $sortedVersions
            
            # Check for pinned versions (versions with .pin file)
            $pinnedVersions = @()
            foreach ($version in $sortedVersions) {
                $versionPath = Join-Path $_.FullName $version
                $pinFile = Join-Path $versionPath '.pin'
                if (Test-Path $pinFile) {
                    $pinnedVersions += $version
                }
            }
            if ($pinnedVersions.Count -gt 0) {
                $result.PinnedVersions[$appName] = $pinnedVersions
            }
        }
        
        # Resolve 'current' symlink to get the actual version directory name
        $currentLink = Join-Path $_.FullName 'current'
        if (Test-Path $currentLink) {
            try {
                $target = (Get-Item $currentLink).Target
                if ($target) {
                    # Target might be full path or relative, extract just the version folder name
                    $currentDirName = Split-Path -Leaf $target
                    $result.CurrentVersions[$appName] = $currentDirName
                }
            } catch {
                # If we can't resolve symlink, continue without it
            }
        }
        
        # Detect held apps via install.json (source of truth for hold status)
        $installJsonPath = Join-Path $_.FullName 'current\install.json'
        if (Test-Path $installJsonPath) {
            try {
                $installInfo = Get-Content -Raw -Path $installJsonPath | ConvertFrom-Json
                if ($installInfo.PSObject.Properties.Name -contains 'hold' -and
                    $installInfo.hold -eq $true) {
                    $result.HeldApps[$appName] = $true
                }
            } catch {
                # If install.json is malformed or missing, ignore and continue
            }
        }
    }
    
    return $result
}

Export-ModuleMember -Function @(
    'Get-InstalledAppVersions'
)
