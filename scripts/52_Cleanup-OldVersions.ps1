<#
.SYNOPSIS
Removes old app versions (preserves current, pinned, and held apps)

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment -UpdateBuckets:$false
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Load Get-InstalledAppVersions module
$GetVersionsPath = Join-Path $ProjectRoot 'modules\InstalledAppVersions.psm1'
Import-Module $GetVersionsPath -Force

# Load UpdatableApps module for Get-HeldApps
$UpdatableAppsPath = Join-Path $ProjectRoot 'modules\UpdatableApps.psm1'
Import-Module $UpdatableAppsPath -Force

# Load before/after module
$BeforeAfterPath = Join-Path $ProjectRoot 'modules\BeforeAfterState.psm1'
Import-Module $BeforeAfterPath -Force

# Load FileRemoval module for robust directory deletion
$FileRemovalPath = Join-Path $ProjectRoot 'modules\FileRemoval.psm1'
if (Test-Path $FileRemovalPath) {
    Import-Module $FileRemovalPath -Force
}

Write-SectionHeader -Title 'CLEANUP OLD VERSIONS'

# Check if Scoop is installed - required for cleanup (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Show initial state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowBefore

Write-SubsectionHeader -Title 'Scanning for Old Versions'

# Get list of held apps (held apps are skipped entirely - they're not updated, so no old versions)
# Use install.json-based detection instead of parsing scoop list output
$heldApps = @{}
try {
    $heldApps = Get-HeldApps -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
} catch {
    Write-Warning "Failed to retrieve held apps for cleanup: $($_.Exception.Message)"
}

# Get all installed versions, current versions, and pinned versions
$versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
$appVersions = $versionsData.AppVersions
$currentVersions = $versionsData.CurrentVersions
$pinnedVersions = $versionsData.PinnedVersions

if ($appVersions.Count -eq 0) {
    Write-Host "[*] No apps with multiple versions found."
    Write-Host ""
    exit 0
}

$totalRemoved = 0
$appsProcessed = 0

# Process each app
foreach ($appName in $appVersions.Keys) {
    # Skip held apps entirely (they're not updated, so no old versions to clean)
    if ($heldApps.ContainsKey($appName)) {
        continue
    }
    $versions = $appVersions[$appName]
    $currentVersion = if ($currentVersions.ContainsKey($appName)) { $currentVersions[$appName] } else { $null }
    $appPinnedVersions = if ($pinnedVersions.ContainsKey($appName)) { $pinnedVersions[$appName] } else { @() }
    
    # Filter out current and pinned versions - only keep versions that can be removed
    $versionsToRemove = $versions | Where-Object {
        $_ -ne $currentVersion -and
        $appPinnedVersions -notcontains $_
    }
    
    if ($versionsToRemove -and $versionsToRemove.Count -gt 0) {
        $appsProcessed++
        Write-Host "[*] Removing old versions for $appName : $($versionsToRemove -join ', ')"
        
        foreach ($version in $versionsToRemove) {
            $versionDir = Join-Path $ScoopRoot "apps\$appName\$version"
            if (Test-Path $versionDir) {
                try {
                    if (Get-Command Remove-DirectorySafe -ErrorAction SilentlyContinue) {
                        $removed = Remove-DirectorySafe -Path $versionDir -ScoopRoot $ScoopRoot
                        if ($removed) {
                            $totalRemoved++
                        } else {
                            Write-Error "Failed to remove $appName version $version (Remove-DirectorySafe returned false)."
                        }
                    } else {
                        Remove-Item -LiteralPath $versionDir -Recurse -Force -ErrorAction Stop
                        $totalRemoved++
                    }
                } catch {
                    Write-Error "Failed to remove $appName version $version : $_"
                }
            }
        }
        Write-Host ""
    }
}

if ($appsProcessed -eq 0) {
    Write-Host "[*] No old versions to remove (all versions are current or pinned)."
    Write-Host ""
} else {
    Write-Host "[OK] Cleanup completed. Removed $totalRemoved old version(s) from $appsProcessed app(s)."
    Write-Host ""
}

# Show final state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter

exit 0
