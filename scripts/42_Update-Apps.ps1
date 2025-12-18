<#
.SYNOPSIS
Updates all installed apps

.CMD
scoop list
scoop install
scoop reset
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx         = Initialize-ScriptEnvironment -UpdateBuckets
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot   = $ctx.ScoopRoot
$ScoopShim   = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Check if Scoop is installed - required for updating apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load extended list module
$ExtendedListPath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
if (-not (Test-Path $ExtendedListPath)) {
    Write-Error "ExtendedAppList module not found at: $ExtendedListPath"
    exit 4
}
Import-Module $ExtendedListPath -Force
# Verify function is available
if (-not (Get-Command Format-AppListTable -ErrorAction SilentlyContinue)) {
    Write-Error "Format-AppListTable function not available after module import"
    exit 4
}

# Load updatable apps module (shared logic for scripts 41 and 42)
$UpdatableAppsPath = Join-Path $ProjectRoot 'modules\UpdatableApps.psm1'
if (-not (Test-Path $UpdatableAppsPath)) {
    Write-Error "UpdatableApps module not found at: $UpdatableAppsPath"
    exit 4
}
Import-Module $UpdatableAppsPath -Force

# Load before/after module
$BeforeAfterPath = Join-Path $ProjectRoot 'modules\BeforeAfterState.psm1'
Import-Module $BeforeAfterPath -Force

# Load RunningScoopApps module
$RunningAppsModulePath = Join-Path $ProjectRoot 'modules\RunningScoopApps.psm1'
Import-Module $RunningAppsModulePath -Force

# Load FileRemoval module for robust directory deletion
$FileRemovalPath = Join-Path $ProjectRoot 'modules\FileRemoval.psm1'
if (Test-Path $FileRemovalPath) {
    Import-Module $FileRemovalPath -Force
}

# Load VirusTotal integration (best-effort)
$vtSettings = $null
$VirusTotalInitPath = Join-Path $ProjectRoot 'modules\VirusTotalInit.psm1'
if (Test-Path -LiteralPath $VirusTotalInitPath) {
    Import-Module $VirusTotalInitPath -Force -ErrorAction SilentlyContinue
    if (Get-Command -Name Initialize-VirusTotalIntegration -ErrorAction SilentlyContinue) {
        $vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
    }
}

Write-SectionHeader -Title 'UPDATING APPS'

Test-NoRunningApps -ScoopRoot $ScoopRoot
Write-Host ""

# Show initial state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowBefore -ShowUpdates

# Build apps list data structure using shared module
$heldApps = Get-HeldApps -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
$pinnedVersions = Get-PinnedVersions -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
$appSources = Get-AppSources -ScoopShim $ScoopShim -ScoopRoot $ScoopRoot
$latestBucketVersions = Get-LatestBucketVersions -ScoopRoot $ScoopRoot -AppSources $appSources
$appsList = Get-InstalledAppsList -ScoopRoot $ScoopRoot
$updatableVersions = Get-UpdatableVersions -AppsList $appsList -HeldApps $heldApps -PinnedVersions $pinnedVersions -LatestBucketVersions $latestBucketVersions

# Ensure we have an array (PowerShell might unwrap single-item arrays)
if ($updatableVersions -isnot [array]) {
    if ($updatableVersions) {
        $updatableVersions = @($updatableVersions)
    } else {
        $updatableVersions = @()
    }
}

# Check if there are apps to update
if (-not $updatableVersions -or $updatableVersions.Count -eq 0) {
    Write-SubsectionHeader -Title 'Apps to be Updated'
    Write-Host "No apps to update."
    Write-Host ""
    exit 0
}

# Show apps to be updated
Write-SubsectionHeader -Title 'Apps to be Updated'

# Display updatable versions table using shared function
# Ensure module is available (re-import if needed)
if (-not (Get-Command Format-AppListTable -ErrorAction SilentlyContinue)) {
    $ExtendedListPath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
    if (Test-Path $ExtendedListPath) {
        Import-Module $ExtendedListPath -Force -ErrorAction Stop
    }
}
$bucketsDir = Join-Path $ScoopRoot 'buckets'
Format-AppListTable -AppsList $updatableVersions `
                    -HeldApps $heldApps `
                    -PinnedVersions $pinnedVersions `
                    -AppSources $appSources `
                    -LatestBucketVersions $latestBucketVersions `
                    -BucketsDir $bucketsDir `
                    -ShowUpdates `
                    -Title "Apps to be updated:"

# --- Automatic Backup Before Update ---
# Only create backup if there are apps to update

Write-SubsectionHeader -Title 'Creating Backup Before Update'

# Load backup and export modules
$BackupPersistPath = Join-Path $ProjectRoot 'modules\BackupPersist.psm1'
Import-Module $BackupPersistPath -Force
$ExportAppsPath = Join-Path $ProjectRoot 'modules\ExportApps.psm1'
Import-Module $ExportAppsPath -Force
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$UpdateConfigPath = Join-Path $ProjectRoot 'modules\UpdateConfig.psm1'
Import-Module $UpdateConfigPath -Force

# Generate timestamp for this backup
$backupTimestamp = Get-Timestamp

# Backup persist folder
Write-Host "[*] Creating Persist Backup..."
$persistBackupPath = Backup-PersistFolder -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -Timestamp $backupTimestamp
if ($persistBackupPath) {
    $archiveSize = (Get-Item $persistBackupPath).Length
    $archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
    Write-Host "[OK] Persist backup created: $persistBackupPath ($archiveSizeMB MB)"
} else {
    Write-Host "[*] No persist folder to backup"
}

# Export apps configuration
Write-Host "[*] Creating Apps Export..."
$appsExportPath = Export-AppsConfiguration -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -Timestamp $backupTimestamp
if ($appsExportPath) {
    Write-Host "[OK] Apps export created: $appsExportPath"
} else {
    Write-Host "[*] No apps to export"
}

Write-Host ""

# Get update configuration
$removeOldVersions = Get-UpdateConfig -ProjectRoot $ProjectRoot

# Track original current versions before updates
$originalCurrentVersions = @{}
foreach ($app in $appsList) {
    if ($app.Current) {
        if (-not $originalCurrentVersions.ContainsKey($app.Name)) {
            $originalCurrentVersions[$app.Name] = $app.Version
        }
    }
}

# Update apps
Write-SubsectionHeader -Title 'Updating Apps'

if ($updatableVersions -and $updatableVersions.Count -gt 0) {
    # Group by app name to update each app once (install latest version)
    $appsToUpdate = @{}
    $versionsBeingUpdated = @{}  # Track which versions are being updated per app
    foreach ($app in $updatableVersions) {
        if (-not $appsToUpdate.ContainsKey($app.Name)) {
            $appsToUpdate[$app.Name] = $latestBucketVersions[$app.Name]
            $versionsBeingUpdated[$app.Name] = @()
        }
        $versionsBeingUpdated[$app.Name] += $app.Version
    }
    
    foreach ($appName in $appsToUpdate.Keys) {
        $latestVersion = $appsToUpdate[$appName]
        $originalCurrent = if ($originalCurrentVersions.ContainsKey($appName)) { $originalCurrentVersions[$appName] } else { $null }
        $isUpdatingCurrent = ($originalCurrent -in $versionsBeingUpdated[$appName])
        
        Write-Host "[*] Updating $appName to version $latestVersion..."
        Write-Host ""

        # Optional VirusTotal pre-update check
        if ($vtSettings) {
            $vtCheck = Invoke-VirusTotalCheckForApp -AppName $appName -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Install'
            if ($vtCheck.Status -eq 'Risky') {
                $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $vtCheck
                if ($decision -eq 'Abort') {
                    Write-Warning "Aborting updates due to VirusTotal detections."
                    Write-Host ""
                    exit 4
                } elseif ($decision -eq 'Skip') {
                    Write-Host "[*] Skipping update of $appName due to user decision."
                    Write-Host ""
                    continue
                }
            } elseif ($vtCheck.Status -eq 'Error') {
                Write-Warning "VirusTotal check encountered an error for app '$appName'. Continuing update."
                Write-Host ""
            }
        }
        
        # Install the latest version from bucket
        $installResult = & $ScoopShim install "${appName}@${latestVersion}" 2>&1
        $installResult | Out-Host
        
        if ($LASTEXITCODE -eq 0) {
            # If we're updating a non-current version, restore the original current version
            if (-not $isUpdatingCurrent -and $originalCurrent) {
                Write-Host "[*] Restoring original current version: $originalCurrent"
                $resetResult = & $ScoopShim reset "${appName}@${originalCurrent}" 2>&1
                $resetResult | Out-Host
            } else {
                # If updating current version, activate the new version
                $resetResult = & $ScoopShim reset $appName 2>&1
                $resetResult | Out-Host
            }
            
            # Remove old versions if configured
            if ($removeOldVersions) {
                $versionsToRemove = $versionsBeingUpdated[$appName]
                foreach ($oldVersion in $versionsToRemove) {
                    # Don't remove if it's the original current version (unless we're updating it)
                    # Don't remove pinned versions
                    $isPinned = ($pinnedVersions.ContainsKey($appName) -and $pinnedVersions[$appName] -contains $oldVersion)
                    if (($isUpdatingCurrent -or $oldVersion -ne $originalCurrent) -and -not $isPinned) {
                        Write-Host "[*] Removing old version: $oldVersion"
                        # Use shared removal helper for robust deletion (handles attributes/locks)
                        $versionDir = Join-Path $ScoopRoot "apps\$appName\$oldVersion"
                        if (Test-Path $versionDir) {
                            if (Get-Command Remove-DirectorySafe -ErrorAction SilentlyContinue) {
                                $removed = Remove-DirectorySafe -Path $versionDir -ScoopRoot $ScoopRoot
                                if ($removed) {
                                    Write-Host "[OK] Removed version folder: $oldVersion"
                                } else {
                                    Write-Error "Failed to remove version folder $oldVersion (Remove-DirectorySafe returned false)."
                                }
                            } else {
                                try {
                                    Remove-Item -Path $versionDir -Recurse -Force -ErrorAction Stop
                                    Write-Host "[OK] Removed version folder: $oldVersion"
                                } catch {
                                    Write-Error "Failed to remove version folder $oldVersion : $_"
                                }
                            }
                        } else {
                            Write-Warning "Version folder not found: $oldVersion"
                        }
                    }
                }
            }
            
            Write-Host "[OK] $appName updated to version $latestVersion"
        } else {
            Write-Error "Failed to install $appName version $latestVersion"
        }
        Write-Host ""
    }
} else {
    Write-Host "No apps to update."
    Write-Host ""
}

# Show final state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter -ShowUpdates
Write-Host ""

exit 0
