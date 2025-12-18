<#
.SYNOPSIS
Updates Scoop itself and all buckets

.CMD
scoop status
scoop update
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

# Check if Scoop is installed - required for updating Scoop (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

Write-SectionHeader -Title 'UPDATING SCOOP'

# Check Scoop status and determine if update is available
Write-SubsectionHeader -Title 'Scoop Status'

# Initialize variables
$scoopUpdateAvailable = $false
$currentScoopVersion = $null
$latestScoopVersion = $null

try {
    $statusOutput = & $ScoopShim status 2>&1
    
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
                $gitStatus = & git fetch 2>&1
                $gitStatus = & git status 2>&1
                if ($gitStatus -match 'behind') {
                    $scoopUpdateAvailable = $true
                    # Try to get version info
                    $currentCommit = & git rev-parse --short HEAD 2>&1
                    $latestCommit = & git rev-parse --short origin/master 2>&1
                    if ($currentCommit -and $latestCommit) {
                        $currentScoopVersion = $currentCommit
                        $latestScoopVersion = $latestCommit
                    }
                } else {
                    # Get current version even when up to date
                    $currentCommit = & git rev-parse --short HEAD 2>&1
                    if ($currentCommit) {
                        $currentScoopVersion = $currentCommit
                    }
                }
            } catch { }
            finally {
                Pop-Location
            }
        }
    }
    
    # If still no version, try to get it from git
    if (-not $currentScoopVersion) {
        $scoopDir = Join-Path $ScoopRoot 'apps\scoop\current'
        if (Test-Path $scoopDir) {
            try {
                Push-Location $scoopDir
                $currentCommit = & git rev-parse --short HEAD 2>&1
                if ($currentCommit) {
                    $currentScoopVersion = $currentCommit
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
    } else {
        Write-Host "Scoop is up to date."
        if ($currentScoopVersion) {
            Write-Host "Current version: $currentScoopVersion"
        }
        Write-Host ""
    }
} catch {
    Write-Host "Unable to check Scoop update status."
    Write-Host ""
}

# Update Scoop (only if update is available)
if ($scoopUpdateAvailable) {
    Write-SubsectionHeader -Title 'Updating Scoop'

    $PatchingModulePath = Join-Path $ProjectRoot 'modules\ScoopPatching.psm1'

    try {
        & $ScoopShim update
        Write-Host ""
        
        # Apply lib patches after update (Scoop may have overwritten lib files)
        if (Test-Path $PatchingModulePath) {
            Update-ScoopLibPatches -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
        }
    } catch {
        Write-Error "Failed to update Scoop: $_"
        Write-Host ""
    }
}

# Check Scoop status after update (only if update was performed)
if ($scoopUpdateAvailable) {
    Write-SubsectionHeader -Title 'Scoop Status (After)'
    
    try {
        $statusOutput = & $ScoopShim status 2>&1
        $scoopUpToDate = $false
        $currentScoopVersionAfter = $null
        
        foreach ($line in $statusOutput) {
            if ($line -match 'Scoop.*is.*up.*to.*date' -or $line -match 'Scoop.*was.*updated') {
                $scoopUpToDate = $true
            }
            # Try to get current version
            if ($line -match 'Scoop:\s*(\S+)') {
                $currentScoopVersionAfter = $Matches[1]
            }
        }
        
        # Also check git repository for current version
        if (-not $currentScoopVersionAfter) {
            $scoopDir = Join-Path $ScoopRoot 'apps\scoop\current'
            if (Test-Path $scoopDir) {
                try {
                    Push-Location $scoopDir
                    $currentCommit = & git rev-parse --short HEAD 2>&1
                    if ($currentCommit) {
                        $currentScoopVersionAfter = $currentCommit
                    }
                } catch { }
                finally {
                    Pop-Location
                }
            }
        }
        
        Write-Host "Scoop update completed."
        if ($currentScoopVersionAfter) {
            Write-Host "Current version: $currentScoopVersionAfter"
        }
        Write-Host ""
    } catch {
        Write-Host "Unable to verify Scoop update status."
        Write-Host ""
    }
}

exit 0
