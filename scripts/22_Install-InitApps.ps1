<#
.SYNOPSIS
Installs apps and buckets from init_apps.json

.CMD
scoop bucket add
scoop install
scoop hold
scoop unhold
scoop reset
scoop update
scoop uninstall
#>

[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# Load bootstrap module (standard)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Ensure console UI helpers are available (for standalone runs outside the menu host).
if (-not (Get-Command -Name Write-SectionHeader -ErrorAction SilentlyContinue)) {
    $ConsoleUiPath = Join-Path $ProjectRoot 'modules\ConsoleUi.psm1'
    if (Test-Path -LiteralPath $ConsoleUiPath) {
        Import-Module $ConsoleUiPath -Force -ErrorAction SilentlyContinue
    }
}

# Load shared modules
$ModulePath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
$ModulePath = Resolve-LiteralPathSafe -Path $ModulePath
Import-Module $ModulePath -Force

# Load UpdatableApps for held/pinned metadata used by ExtendedAppList
$UpdatableAppsPath = Join-Path $ProjectRoot 'modules\UpdatableApps.psm1'
if (-not (Test-Path $UpdatableAppsPath)) {
    Write-Error "UpdatableApps module not found at: $UpdatableAppsPath"
    exit 4
}
Import-Module $UpdatableAppsPath -Force

# Load fresh installation check module
$TestFreshPath = Join-Path $ProjectRoot 'modules\FreshInstallation.psm1'
$TestFreshPath = Resolve-LiteralPathSafe -Path $TestFreshPath
Import-Module $TestFreshPath -Force

# Default to init_apps.json if no path specified
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ProjectRoot 'config\apps\init_apps.json'
}

# Resolve path to handle spaces correctly (ensures proper path expansion)
# Use GetFullPath which works even if file doesn't exist yet
try {
    if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
        $ConfigPath = Resolve-LiteralPathSafe -Path $ConfigPath
    } else {
        $ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
    }
} catch { }

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host "[*] Importing from: $ConfigPath"
Write-Host ""

# Check if Scoop is installed - required for installing apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Check if installation is fresh (no apps installed except scoop)
$isFresh = Test-FreshInstallation -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim
if (-not $isFresh) {
    # Apps are already installed - exit with code 4
    exit 4
}

# Load VirusTotal integration (best-effort, only when Scoop is installed and installation is allowed)
$vtSettings = $null
$VirusTotalInitPath = Join-Path $ProjectRoot 'modules\VirusTotalInit.psm1'
if (Test-Path -LiteralPath $VirusTotalInitPath) {
    Import-Module $VirusTotalInitPath -Force -ErrorAction SilentlyContinue
    if (Get-Command -Name Initialize-VirusTotalIntegration -ErrorAction SilentlyContinue) {
        $vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
    }
}

Write-SectionHeader -Title 'INSTALLATION'

# Load before/after module (this script only shows "After" state, not "Before")
$BeforeAfterPath = Join-Path $ProjectRoot 'modules\BeforeAfterState.psm1'
$BeforeAfterPath = Resolve-LiteralPathSafe -Path $BeforeAfterPath
try {
    Remove-Module -Name BeforeAfterState -Force -ErrorAction SilentlyContinue
} catch { }
if (Test-Path $BeforeAfterPath) {
    try {
        Import-Module $BeforeAfterPath -Force
    } catch {
        . "$BeforeAfterPath"
    }
}

# Read configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    Write-Host ""
    exit 4
}

Write-Host "[*] Reading configuration from: $ConfigPath"
$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
Write-Host ""

# Update Scoop and buckets to get latest manifests
Write-Host "[*] Updating Scoop and buckets to get latest manifests..."
Write-Host "[*] This may take a while..."
Write-Host ""

# Force output flush
[Console]::Out.Flush()

# Ensure patch is active before update (prevents registry writes during update)
# The patch includes a modification to scoop-update.ps1 that ignores our patch files
# when checking for uncommitted changes, so updates work even with patches present
# Note: Patching is already done by Initialize-ScoopEnvironment, so we only need to check
# if re-patching is needed after update (Scoop may have overwritten lib/system.ps1)
& $ScoopShim update | Out-Host
[Console]::Out.Flush()
Write-Host ""

# Patch Scoop core after update (Scoop may have overwritten lib/system.ps1)
# This is expected behavior - we automatically patch to maintain stealth mode
# Only patch if needed (already checked by Initialize-ScoopEnvironment)
$PatchingModulePath = Join-Path $ProjectRoot 'modules\ScoopPatching.psm1'
if (Test-Path $PatchingModulePath) {
    Import-Module $PatchingModulePath -Force -ErrorAction SilentlyContinue
    # Apply lib patches after update
    Update-ScoopLibPatches -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
}

Write-Host ""

# Add buckets
if ($config.buckets -and $config.buckets.Count -gt 0) {
    Write-SubsectionHeader -Title 'Adding Buckets'
    
    foreach ($bucket in $config.buckets) {
        $bucketName = $bucket.name
        Write-Host "[*] Adding bucket: $bucketName"
        [Console]::Out.Flush()
        & $ScoopShim bucket add $bucketName | Out-Host
        [Console]::Out.Flush()
        Write-Host ""
    }
}

# Install apps - process by app-set (all versions of one app together)
if ($config.apps -and $config.apps.Count -gt 0) {
    Write-SubsectionHeader -Title 'Installing Apps'
    
    # Load required modules
    $GetVersionsPath = Join-Path $ProjectRoot 'modules\InstalledAppVersions.psm1'
    Import-Module $GetVersionsPath -Force
    $PatchInstallJsonPath = Join-Path $ProjectRoot 'modules\InstallJson.psm1'
    Import-Module $PatchInstallJsonPath -Force
    
    # Group entries by app name
    $appSets = @{}
    foreach ($app in $config.apps) {
        $appName = $app.name
        $shouldSkip = $app.skip -eq $true
        
        if ($shouldSkip) {
            Write-Host "[SKIP] $appName (skip flag is set)"
            Write-Host ""
            continue
        }
        
        if (-not $appSets.ContainsKey($appName)) {
            $appSets[$appName] = @()
        }
        $appSets[$appName] += $app
    }
    
    # Process each app-set
    foreach ($appName in ($appSets.Keys | Sort-Object)) {
        $appEntries = $appSets[$appName]

        # Sub-subsection: keep it lightweight (blank line + label) for consistent UX.
        Write-Host ""
        Write-Host ("[*] Processing: {0}" -f $appName)
        Write-Host ""
        
        # Load current state for this app
        $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
        $allInstalledVersions = if ($versionsData.AppVersions.ContainsKey($appName)) { $versionsData.AppVersions[$appName] } else { @() }
        $currentVersion = if ($versionsData.CurrentVersions.ContainsKey($appName)) { $versionsData.CurrentVersions[$appName] } else { $null }
        $pinnedVersions = if ($versionsData.PinnedVersions.ContainsKey($appName)) { $versionsData.PinnedVersions[$appName] } else { @() }
        
        # Build entry objects with metadata (preserve JSON order)
        $entryOrder = 0
        $targetVersions = @{}  # For tracking which versions should exist (for cleanup)
        $processedEntries = @()
        foreach ($app in $appEntries) {
            $entryOrder++
            $processedEntries += [pscustomobject]@{
                Name = $appName
                Version = $app.version  # may be $null for non-versioned entries
                Pin = [bool]($app.pin -eq $true)
                Hold = [bool]($app.hold -eq $true)
                CurrentFlag = [bool]($app.current -eq $true)
                Order = $entryOrder
                ResolvedVersion = $null  # will be filled after install
            }
        }
        
        # Build target versions set for cleanup (only versioned entries)
        foreach ($entry in $processedEntries) {
            if ($entry.Version) {
                $targetVersions[$entry.Version] = $true
            }
        }
        
        # Step 1: Uninstall non-pinned versions that shouldn't exist
        foreach ($installedVersion in $allInstalledVersions) {
            $isPinned = $pinnedVersions -contains $installedVersion
            $shouldExist = $targetVersions.ContainsKey($installedVersion)
            
            # Keep if: pinned OR should exist in target
            if (-not $isPinned -and -not $shouldExist) {
                Write-Host "[*] Uninstalling non-pinned version: $appName@$installedVersion"
                & $ScoopShim uninstall "${appName}@${installedVersion}" | Out-Host
                Write-Host ""
            }
        }
        
        # Step 2: Install each entry in JSON order and resolve actual version
        foreach ($entry in ($processedEntries | Sort-Object Order)) {
            if ($entry.Order -gt 1) {
                # Add spacing between multiple entries for the same app (better readability)
                Write-Host ""
                Write-Host ""
            }
            $identifier = if ($entry.Version) {
                "$appName@$($entry.Version)"
            } else {
                $appName
            }
            
            # Handle installation based on entry type
            if ($entry.Version) {
                # Versioned entry - check if this specific version is installed
                $isInstalled = $allInstalledVersions -contains $entry.Version
                
                if (-not $isInstalled) {
                    # Optional VirusTotal pre-install check (deep for explicit version)
                    if ($vtSettings) {
                        $vtCheck = Invoke-VirusTotalCheckForApp -AppName $appName -AppSpec $identifier -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Install'
                        if ($vtCheck.Status -eq 'Risky') {
                            $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $vtCheck
                            if ($decision -eq 'Abort') {
                                Write-Warning "Aborting installation due to VirusTotal detections."
                                Write-Host ""
                                exit 4
                            } elseif ($decision -eq 'Skip') {
                                Write-Host "[*] Skipping installation of $identifier due to user decision."
                                Write-Host ""
                                continue
                            }
                        } elseif ($vtCheck.Status -eq 'Error') {
                            Write-Warning "VirusTotal check encountered an error for app '$appName'. Continuing install."
                            Write-Host ""
                        }
                    }

                    Write-Host ""
                    Write-Host "[*] Installing: $identifier"
                    [Console]::Out.Flush()
                    & $ScoopShim install $identifier | Out-Host
                    [Console]::Out.Flush()
                    
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Install failed for $identifier (exit code $LASTEXITCODE)"
                        Write-Host ""
                        continue
                    }
                } else {
                    Write-Host "[OK] Already installed: $identifier"
                    Write-Host ""
                }
            } else {
                # Non-versioned entry - always check and install latest version from bucket
                # Refresh installed versions first
                $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
                $allInstalledVersions = if ($versionsData.AppVersions.ContainsKey($appName)) { 
                    $versionsData.AppVersions[$appName] 
                } else { 
                    @() 
                }
                
                # Get latest version from bucket
                $bucketsDir = Join-Path $ScoopRoot 'buckets'
                $latestBucketVersion = $null
                if (Test-Path $bucketsDir) {
                    $buckets = Get-ChildItem -Path $bucketsDir -Directory
                    foreach ($bucket in $buckets) {
                        $manifestPath = Join-Path $bucket.FullName "bucket\$appName.json"
                        if (Test-Path $manifestPath) {
                            $manifestContent = Get-Content -Raw -Path $manifestPath
                            $manifest = $manifestContent | ConvertFrom-Json
                            if ($manifest.version) {
                                $latestBucketVersion = $manifest.version
                                break
                            }
                        }
                    }
                }
                
                # Check if latest is already installed
                if ($latestBucketVersion -and -not ($allInstalledVersions -contains $latestBucketVersion)) {
                    # Latest version is not installed, install it
                    # If an older version is current, scoop install will say "already installed"
                    # So we need to explicitly install the latest version with version specifier
                    $latestIdentifier = "$appName@$latestBucketVersion"

                    # Optional VirusTotal pre-install check (shallow for latest: app only)
                    if ($vtSettings) {
                        $vtCheck = Invoke-VirusTotalCheckForApp -AppName $appName -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Install'
                        if ($vtCheck.Status -eq 'Risky') {
                            $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $vtCheck
                            if ($decision -eq 'Abort') {
                                Write-Warning "Aborting installation due to VirusTotal detections."
                                Write-Host ""
                                exit 4
                            } elseif ($decision -eq 'Skip') {
                                Write-Host "[*] Skipping installation of $latestIdentifier due to user decision."
                                Write-Host ""
                                continue
                            }
                        } elseif ($vtCheck.Status -eq 'Error') {
                            Write-Warning "VirusTotal check encountered an error for app '$appName'. Continuing install."
                            Write-Host ""
                        }
                    }

                    Write-Host ""
                    Write-Host "[*] Installing latest version explicitly: $latestIdentifier"
                    [Console]::Out.Flush()
                    & $ScoopShim install $latestIdentifier | Out-Host
                    [Console]::Out.Flush()
                    Write-Host ""
                } elseif ($latestBucketVersion -and ($allInstalledVersions -contains $latestBucketVersion)) {
                    # Latest version is already installed, just verify it's from bucket
                    Write-Host "[OK] Latest version $latestBucketVersion is already installed for $appName"
                    Write-Host ""
                } else {
                    if ($latestBucketVersion) {
                        Write-Host "[OK] Latest version $latestBucketVersion is already installed for $appName"
                    } else {
                        Write-Host "[OK] Already installed: $identifier"
                    }
                    Write-Host ""
                }
            }
            
            # After this install, query the actual installed version
            $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
            $currentVersion = if ($versionsData.CurrentVersions.ContainsKey($appName)) { 
                $versionsData.CurrentVersions[$appName] 
            } else { 
                $null 
            }
            
            if ($currentVersion) {
                $entry.ResolvedVersion = $currentVersion
            } elseif ($entry.Version) {
                # Fallback: use version from config if query fails
                $entry.ResolvedVersion = $entry.Version
            } else {
                Write-Warning "Could not determine installed version for $identifier"
                Write-Host ""
            }
            
            # Create/verify .pin file if needed (for logical pinning)
            if ($entry.Pin -and $entry.ResolvedVersion) {
                $appPath = Join-Path $ScoopRoot "apps\$appName\$($entry.ResolvedVersion)"
                if (Test-Path $appPath) {
                    $pinFile = Join-Path $appPath '.pin'
                    if (-not (Test-Path $pinFile)) {
                        New-Item -ItemType File -Path $pinFile -Force | Out-Null
                        Write-Host "[OK] Created pin file for: $appName@$($entry.ResolvedVersion)"
                        Write-Host ""
                    }
                }
            }
            
            # Patch install.json to point to bucket instead of workspace
            if ($entry.ResolvedVersion) {
                $patched = Update-InstallJsonToBucket -ScoopRoot $ScoopRoot -AppName $appName -Version $entry.ResolvedVersion
                if ($patched) {
                    Write-Host "[OK] Patched install.json for $appName@$($entry.ResolvedVersion) to point to bucket"
                    Write-Host ""
                }
            }
        }
        
        # Step 3: Choose which entry should be current
        # Find last entry with current:true, or last entry if none
        $explicitCurrent = $processedEntries | Where-Object { $_.CurrentFlag } | Sort-Object Order | Select-Object -Last 1
        
        if ($explicitCurrent) {
            $currentEntry = $explicitCurrent
        } else {
            # No explicit current:true -> last entry in JSON order wins
            $currentEntry = $processedEntries | Sort-Object Order | Select-Object -Last 1
        }
        
        if (-not $currentEntry.ResolvedVersion) {
            Write-Warning "No resolved version for '$appName' current-entry; skipping reset/pin/hold."
            Write-Host ""
        } else {
            $desiredVersion = $currentEntry.ResolvedVersion
            
            # Step 4: Enforce current version with scoop reset
            $versionsData = Get-InstalledAppVersions -ScoopRoot $ScoopRoot
            $actualCurrent = if ($versionsData.CurrentVersions.ContainsKey($appName)) { 
                $versionsData.CurrentVersions[$appName] 
            } else { 
                $null 
            }
            
            if ($desiredVersion -ne $actualCurrent) {
                Write-Host "[*] Setting current version for $appName to $desiredVersion"
                & $ScoopShim reset "$appName@$desiredVersion" | Out-Host
                Write-Host ""
                
                # Patch install.json after reset (reset might recreate it pointing to workspace)
                $patched = Update-InstallJsonToBucket -ScoopRoot $ScoopRoot -AppName $appName -Version $desiredVersion
                if ($patched) {
                    Write-Host "[OK] Patched install.json after reset for $appName@$desiredVersion"
                    Write-Host ""
                }
            } else {
                # Even if current version is already correct, ensure install.json is patched
                $patched = Update-InstallJsonToBucket -ScoopRoot $ScoopRoot -AppName $appName -Version $desiredVersion
                if ($patched) {
                    Write-Host "[OK] Verified install.json for $appName@$desiredVersion points to bucket"
                    Write-Host ""
                }
            }
            
            # Step 5: PIN – per version (entry)
            # Pinning is handled via .pin files (already created above for pinned versions)
            # No Scoop commands needed - pinning is a logical flag managed by .pin files
            if ($currentEntry.Pin) {
                Write-Host "[OK] Current version $desiredVersion is pinned (via .pin file)"
                Write-Host ""
            }
        }
        
        # Step 6: HOLD – per app in this app-set
        # Hold if any entry has hold:true
        $shouldHold = $false
        foreach ($entry in $processedEntries) {
            if ($entry.Hold) {
                $shouldHold = $true
                break
            }
        }
        
        if ($shouldHold) {
            Write-Host "[*] Holding $appName (app-set has 'hold:true')"
            & $ScoopShim hold $appName | Out-Host
            Write-Host ""
        } else {
            # Only unhold if we're sure there's no hold - don't call unhold if already not held
            # (scoop unhold on a non-held app shows INFO message, which is fine)
            Write-Host "[*] Ensuring $appName is not held (no 'hold:true' in app-set)"
            & $ScoopShim unhold $appName 2>&1 | Out-Null  # Suppress INFO messages
            Write-Host ""
        }
        
        Write-Host ""
    }
}

Write-Host ""
Write-SectionHeader -Title '[OK] Installation complete!'

# Show final state
# Note: ConvertFrom-ScoopList now uses file-based output capture to reliably detect held apps
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter

exit 0
