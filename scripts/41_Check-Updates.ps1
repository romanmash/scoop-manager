<#
.SYNOPSIS
Checks for available app updates

.CMD
scoop list
scoop status
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (centralized environment setup)
# Standard bootstrap
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment -UpdateBuckets
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot   = $ctx.ScoopRoot
$ScoopShim   = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Check if Scoop is installed - required for checking updates (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load extended list module
$ModulePath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
if (-not (Test-Path $ModulePath)) {
    Write-Error "ExtendedAppList module not found at: $ModulePath"
    exit 4
}
Import-Module $ModulePath -Force

# Load updatable apps module (shared logic for scripts 41 and 42)
$UpdatableAppsPath = Join-Path $ProjectRoot 'modules\UpdatableApps.psm1'
if (-not (Test-Path $UpdatableAppsPath)) {
    Write-Error "UpdatableApps module not found at: $UpdatableAppsPath"
    exit 4
}
Import-Module $UpdatableAppsPath -Force

# Verify Get-HeldApps is available after import
if (-not (Get-Command Get-HeldApps -ErrorAction SilentlyContinue)) {
    Write-Error "Get-HeldApps not available after importing UpdatableApps.psm1"
    exit 4
}

Write-SectionHeader -Title 'CHECKING FOR UPDATES'
Write-SubsectionHeader -Title 'Currently Installed Apps'

# Use shared module to display extended list with updates (same as script 21)
Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowUpdates

Write-SubsectionHeader -Title 'Available Updates'

# Build apps list data structure using shared module
$heldApps = Get-HeldApps -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
$pinnedVersions = Get-PinnedVersions -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
$appSources = Get-AppSources -ScoopShim $ScoopShim -ScoopRoot $ScoopRoot
$latestBucketVersions = Get-LatestBucketVersions -ScoopRoot $ScoopRoot -AppSources $appSources
$appsList = Get-InstalledAppsList -ScoopRoot $ScoopRoot
$updatableVersions = Get-UpdatableVersions -AppsList $appsList -HeldApps $heldApps -PinnedVersions $pinnedVersions -LatestBucketVersions $latestBucketVersions

# Display updatable versions table using shared function
$bucketsDir = Join-Path $ScoopRoot 'buckets'
# Ensure we have an array (PowerShell might unwrap single-item arrays)
if ($updatableVersions -isnot [array]) {
    if ($updatableVersions) {
        $updatableVersions = @($updatableVersions)
    } else {
        $updatableVersions = @()
    }
}
if ($updatableVersions.Count -gt 0) {
    Format-AppListTable -AppsList $updatableVersions `
                        -HeldApps $heldApps `
                        -PinnedVersions $pinnedVersions `
                        -AppSources $appSources `
                        -LatestBucketVersions $latestBucketVersions `
                        -BucketsDir $bucketsDir `
                        -ShowUpdates `
                        -Title "Apps to be updated:"
} else {
    Write-Host "No updates available."
}
Write-Host ""

# Check for Scoop updates
Write-SubsectionHeader -Title 'Scoop Updates'

try {
    $statusCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('status') -Stream:$false -NoHostOutput
    $statusOutput = if ($statusCmd.Output) { $statusCmd.Output -split "\r?\n" } else { @() }
    $scoopUpdateAvailable = $false
    $currentScoopVersion = $null
    $latestScoopVersion = $null
    
    foreach ($line in $statusOutput) {
        # Check for Scoop update messages
        if ($line -match 'Scoop.*is.*up.*to.*date' -or $line -match 'Scoop.*was.*updated') {
            # Scoop is up to date
            break
        }
        # Check for version info in status output
        if ($line -match 'Scoop:\s*(\S+)\s*->\s*(\S+)') {
            $scoopUpdateAvailable = $true
            $currentScoopVersion = $Matches[1]
            $latestScoopVersion = $Matches[2]
            break
        }
    }
    
    # If no update message found, check Scoop git repository
    if (-not $scoopUpdateAvailable) {
        $scoopDir = Join-Path $ScoopRoot 'apps\scoop\current'
        if (Test-Path $scoopDir) {
            try {
                Push-Location $scoopDir
                $null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath 'git' -ArgumentList @('fetch') -Stream:$false -NoHostOutput
                $gitStatusCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath 'git' -ArgumentList @('status') -Stream:$false -NoHostOutput
                $gitStatus = if ($gitStatusCmd.Output) { $gitStatusCmd.Output -split "\r?\n" } else { @() }
                if ($gitStatus -match 'behind') {
                    $scoopUpdateAvailable = $true
                    # Try to get version info
                    $currentCommitCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath 'git' -ArgumentList @('rev-parse','--short','HEAD') -Stream:$false -NoHostOutput
                    $latestCommitCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath 'git' -ArgumentList @('rev-parse','--short','origin/master') -Stream:$false -NoHostOutput
                    $currentCommit = (($currentCommitCmd.Output -split "\r?\n" | Select-Object -First 1) -as [string]).Trim()
                    $latestCommit = (($latestCommitCmd.Output -split "\r?\n" | Select-Object -First 1) -as [string]).Trim()
                    if ($currentCommit -and $latestCommit) {
                        $currentScoopVersion = $currentCommit
                        $latestScoopVersion = $latestCommit
                    }
                }
            } catch { }
            finally {
                Pop-Location
            }
        }
    }
    
    if ($scoopUpdateAvailable) {
        Write-Host "Scoop update available:"
        Write-Host ""
        if ($currentScoopVersion -and $latestScoopVersion) {
            Write-Host "Current: $currentScoopVersion"
            Write-Host "Latest:  $latestScoopVersion"
        } else {
            Write-Host "A newer version of Scoop is available."
        }
        Write-Host ""
        Write-Host "To update Scoop, run script 49_Update-Scoop"
        Write-Host ""
    } else {
        Write-Host "Scoop is up to date."
        Write-Host ""
    }
} catch {
    Write-Host "Unable to check Scoop update status."
    Write-Host ""
}

exit 0
