<#
.SYNOPSIS
Installs Scoop and core apps to ../portable_scoop directory

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (automatically sets up stealth environment)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force

# Ensure console UI helpers are available (for standalone runs outside the menu host).
if (-not (Get-Command -Name Write-SectionHeader -ErrorAction SilentlyContinue)) {
    $ProjectRootForUi = Split-Path -Parent $PSScriptRoot
    $ConsoleUiPath = Join-Path $ProjectRootForUi 'modules\ConsoleUi.psm1'
    if (Test-Path -LiteralPath $ConsoleUiPath) {
        Import-Module $ConsoleUiPath -Force -ErrorAction SilentlyContinue
    }
}

# Calculate Scoop root path first to check if installation exists
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ScoopRootPath = Join-Path $ProjectRoot '..\portable_scoop'
$ScoopRoot = Resolve-Path $ScoopRootPath -ErrorAction SilentlyContinue
if (-not $ScoopRoot) {
    $ScoopRoot = [System.IO.Path]::GetFullPath($ScoopRootPath)
}

# Check if Scoop root already exists - require manual uninstall
if (Test-Path $ScoopRoot) {
    Write-Warning "Existing Scoop installation detected at: $ScoopRoot"
    Write-Host "Please run script 99_Uninstall-Scoop first to remove it manually, then run this script again."
    Write-Host ""
    exit 4
}

# Skip shim validation for installation - shim doesn't exist yet before installation
$ctx = Initialize-ScriptEnvironment -SkipShimValidation
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot

# Load RunningScoopApps module
$RunningAppsModulePath = Join-Path $ProjectRoot 'modules\RunningScoopApps.psm1'
Import-Module $RunningAppsModulePath -Force
# Load InstallationValidation and FileRemovalError modules
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force
$FileRemovalErrorPath = Join-Path $ProjectRoot 'modules\FileRemovalError.psm1'
Import-Module $FileRemovalErrorPath -Force

# Get patch paths
$PatchDir = Join-Path $ProjectRoot 'patch'
$OrigPath = Join-Path $PatchDir 'install_orig.ps1'
$PatchedPath = Join-Path $PatchDir 'install.ps1'

# Resolve paths to handle spaces correctly
try {
    $OrigPath = [System.IO.Path]::GetFullPath($OrigPath)
    $PatchedPath = [System.IO.Path]::GetFullPath($PatchedPath)
} catch {
    # If GetFullPath fails, use as-is (Test-Path will handle it)
}

if (-not (Test-Path $OrigPath)) {
    Write-Error "Stored installer not found at: $OrigPath"
    Write-Host "Please run script 18_Fetch-ScoopInstaller first!"
    Write-Host ""
    exit 4
}

if (-not (Test-Path $PatchedPath)) {
    Write-Error "Patched installer not found at: $PatchedPath"
    Write-Host "The patched install.ps1 file is required for installation."
    Write-Host ""
    exit 4
}

Write-Host "[*] Verifying remote installer against stored original..."
$remote = Invoke-RestMethod -Uri 'https://get.scoop.sh'

# Use hash-based comparison
$tempRemote = Join-Path $env:TEMP "install_remote_$(New-Guid).ps1"
try {
    Set-Content -Path $tempRemote -Value $remote -NoNewline
    Write-Host "[*] Comparing files..."
    Write-Host "    Remote installer (downloaded)"
    Write-Host "    $OrigPath"
    $remoteHash = (Get-FileHash -Path $tempRemote -Algorithm MD5).Hash
    $origHash = (Get-FileHash -Path $OrigPath -Algorithm MD5).Hash
    
    Remove-Item -Path $tempRemote -Force -ErrorAction SilentlyContinue
    
        if ($remoteHash -ne $origHash) {
            $installerUrl = 'https://get.scoop.sh'
            Write-Warning "Remote installer differs from stored install_orig.ps1. This may indicate an update. Review and re-fetch if needed. Expected hash: $origHash, Remote hash: $remoteHash. Download URL: $installerUrl"
            Write-Host ""
            exit 4
        }
} catch {
    if (Test-Path $tempRemote) {
        Remove-Item -Path $tempRemote -Force -ErrorAction SilentlyContinue
    }
    Write-Error "Failed to verify installer: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

Write-Host "[OK] Remote installer verified against stored original"
Write-Host ""

Write-Host "[*] Creating Scoop directory: $ScoopRoot"
New-Item -ItemType Directory -Force -Path $ScoopRoot | Out-Null
Write-Host ""

# Install Scoop from patched installer file
Write-Host "[*] Installing Scoop from patched installer..."
Write-Host ""

# Execute the patched install.ps1 file
& $PatchedPath

Write-Host ""
Write-Host "[OK] Scoop installed at: $ScoopRoot"
Write-Host ""

# Migrate config from installer location to portable root
$autoCfgPathProfile = Join-Path $ScoopRoot 'scoop\config.json'
$portableRootCfgPath = Join-Path $ScoopRoot 'config.json'

# Resolve paths to handle spaces correctly
try {
    $autoCfgPathProfile = [System.IO.Path]::GetFullPath($autoCfgPathProfile)
    $portableRootCfgPath = [System.IO.Path]::GetFullPath($portableRootCfgPath)
} catch {
    # If GetFullPath fails, use as-is (Test-Path will handle it)
}

if (Test-Path $autoCfgPathProfile) {
    if (-not (Test-Path $portableRootCfgPath)) {
        Write-Host "[*] Migrating config from installer location to portable root..."
        Move-Item $autoCfgPathProfile $portableRootCfgPath -Force
        Write-Host "[OK] Config migrated to: $portableRootCfgPath"
    } else {
        Write-Host "[*] Portable root config already exists, preserving it"
        Write-Host "[*] Removing installer-created config at: $autoCfgPathProfile"
        Remove-Item $autoCfgPathProfile -Force -ErrorAction SilentlyContinue
    }
    
    # Remove the scoop subfolder if it exists and is empty
    $autoCfgFolder = Split-Path $autoCfgPathProfile
    if (Test-Path $autoCfgFolder) {
        try {
            $items = Get-ChildItem -Path $autoCfgFolder -ErrorAction SilentlyContinue
            if ($null -eq $items -or $items.Count -eq 0) {
                Remove-Item $autoCfgFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore errors when checking/removing folder
        }
    }
}

if (Test-Path $portableRootCfgPath) {
    Write-Host "[*] Portable config.json available at: $portableRootCfgPath"
    Write-Host "[*] Scoop will use this portable config location (not ~/.config/scoop/config.json)"
} else {
    Write-Host "[*] Note: Config will be created automatically when Scoop runs"
    Write-Host "[*]       (process-level env vars ensure portable config location)"
}
Write-Host ""

# Configure VirusTotal API key from manager_config.json (if available)
try {
    $VirusTotalConfigModulePath = Join-Path $ProjectRoot 'modules\VirusTotalConfig.psm1'
    try {
        if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
            $VirusTotalConfigModulePath = Resolve-LiteralPathSafe -Path $VirusTotalConfigModulePath
        } else {
            $VirusTotalConfigModulePath = [System.IO.Path]::GetFullPath($VirusTotalConfigModulePath)
        }
    } catch { }

    if (Test-Path $VirusTotalConfigModulePath) {
        Import-Module $VirusTotalConfigModulePath -Force
        $vtConfig = Get-VirusTotalConfig -ProjectRoot $ProjectRoot

        if ($vtConfig -and $vtConfig.ApiKey) {
            $ScoopShim = Join-Path $ScoopRoot 'shims\scoop.cmd'
            try {
                if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
                    $ScoopShim = Resolve-LiteralPathSafe -Path $ScoopShim
                } else {
                    $ScoopShim = [System.IO.Path]::GetFullPath($ScoopShim)
                }
            } catch { }

            if (Test-Path $ScoopShim) {
                Write-Host "[*] Configuring VirusTotal API key via scoop config..."
                $configCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('config', 'virustotal_api_key', $vtConfig.ApiKey) -Stream:$true
                $configExitCode = $configCmd.ExitCode

                if ($configExitCode -eq $null -or $configExitCode -eq 0) {
                    Write-Host "[OK] VirusTotal API key configured from manager_config.json"
                } else {
                    Write-Warning "Failed to configure VirusTotal API key via scoop config (exit code: $configExitCode)."
                    Write-Host "[*] You can configure it manually with:"
                    Write-Host "       scoop config virustotal_api_key <API key>"
                }
                Write-Host ""
            }
        }
    }
} catch {
    Write-Warning "Error while applying VirusTotal configuration from manager_config.json: $($_.Exception.Message)"
    Write-Host "[*] You can configure the VirusTotal API key manually with:"
    Write-Host "       scoop config virustotal_api_key <API key>"
    Write-Host ""
}

# Apply lib file patches after installation
$PatchingModulePath = Join-Path $ProjectRoot 'modules\ScoopPatching.psm1'
# Resolve path to handle spaces correctly
try {
    if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
        $PatchingModulePath = Resolve-LiteralPathSafe -Path $PatchingModulePath
    } else {
        $PatchingModulePath = [System.IO.Path]::GetFullPath($PatchingModulePath)
    }
} catch {
    # If GetFullPath fails, use as-is
}

if (Test-Path $PatchingModulePath) {
    try {
        Import-Module $PatchingModulePath -Force -ErrorAction Stop
        # Verify function is available
        if (-not (Get-Command -Name 'Update-ScoopLibPatches' -ErrorAction SilentlyContinue)) {
            Write-Warning "Update-ScoopLibPatches function not found after importing module. Module path: $PatchingModulePath"
            Write-Host ""
            exit 4
        }
        Update-ScoopLibPatches -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
    } catch {
        Write-Warning "Failed to import or use ScoopPatching module: $($_.Exception.Message). Module path: $PatchingModulePath"
        Write-Host ""
        exit 4
    }
} else {
    Write-Warning "ScoopPatching module not found at: $PatchingModulePath"
    Write-Host ""
    exit 4
}
Write-Host ""

# Install core apps from config (core.apps) after Scoop core is installed.
$ScoopShim = Join-Path $ScoopRoot 'shims\scoop.cmd'
if (Test-Path $ScoopShim) {
    $CoreAppsModulePath = Join-Path $ProjectRoot 'modules\CoreApps.psm1'
    if (Test-Path -LiteralPath $CoreAppsModulePath) {
        Import-Module $CoreAppsModulePath -Force
        $coreApps = Get-CoreApps -ProjectRoot $ProjectRoot
        if (-not $coreApps -or $coreApps.Count -eq 0) {
            exit 4
        }

        # Load VirusTotal integration (required for install gating)
        $vtSettings = $null
        $VirusTotalInitPath = Join-Path $ProjectRoot 'modules\VirusTotalInit.psm1'
        if (Test-Path -LiteralPath $VirusTotalInitPath) {
            Import-Module $VirusTotalInitPath -Force -ErrorAction SilentlyContinue
        }
        try {
            $vtSettings = Initialize-VirusTotalManagedFlow -ProjectRoot $ProjectRoot -OperationLabel 'app installation'
        } catch {
            Write-Error $_.Exception.Message
            Write-Host ""
            exit 4
        }

        # Load persist links module (optional)
        $PersistLinksPath = Join-Path $ProjectRoot 'modules\PersistLinks.psm1'
        if (Test-Path -LiteralPath $PersistLinksPath) {
            Import-Module $PersistLinksPath -Force
        }

        # Install everything except Scoop itself (already installed).
        $appsToInstall = @($coreApps | Where-Object { $_ -and $_ -ne 'scoop' })
        if ($appsToInstall.Count -gt 0) {
            Write-SectionHeader -Title 'CORE APPS'

            foreach ($appName in $appsToInstall) {
                Write-SubsectionHeader -Title ("Processing: {0}" -f $appName)

                $appDir = Join-Path $ScoopRoot ("apps\{0}" -f $appName)
                if (Test-Path -LiteralPath $appDir) {
                    Write-Host "[OK] Already installed: $appName"
                    Write-Host ""
                    continue
                }

                # Central VirusTotal gate (Continue / Skip / Abort for Risky / Skipped / Error)
                $vtGate = Invoke-VirusTotalGateForApp -AppName $appName -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Install'
                if ($vtGate.Decision -eq 'Abort') {
                    Write-Warning "Aborting core app installation due to VirusTotal decision."
                    Write-Host ""
                    exit 4
                } elseif ($vtGate.Decision -eq 'Skip') {
                    Write-Host "[*] Skipping installation of $appName due to user decision."
                    Write-Host ""
                    continue
                }

                Write-Host "[*] Installing core app: $appName"
                [Console]::Out.Flush()
                $installCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('install', $appName) -Stream:$true
                $installExitCode = $installCmd.ExitCode
                [Console]::Out.Flush()

                if (Test-Path -LiteralPath $appDir) {
                    Write-Host ""
                    Write-Host "[OK] $appName installed"
                } else {
                    Write-Host ""
                    Write-Warning "Failed to install $appName (exit code: $installExitCode)."
                    Write-Host "[*] You can retry later with: scoop install $appName"
                }

                if (Test-Path -LiteralPath $appDir -and (Get-Command -Name Invoke-PersistLinks -ErrorAction SilentlyContinue)) {
                    Invoke-PersistLinks -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -AppName $appName
                }
                Write-Host ""
            }
        }
    } else {
        Write-Error "CoreApps module not found at: $CoreAppsModulePath"
        Write-Host ""
        exit 4
    }
}

# Show installed apps
Write-SectionHeader -Title 'INSTALLED APPS'

$ScoopShim = Join-Path $ScoopRoot 'shims\scoop.cmd'
if (Test-Path $ScoopShim) {
    # Note: `scoop list` may exit with code 1 when no apps are installed.
    $null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$true
    
} else {
    Write-Host "(Scoop shim not yet available)"
}

Write-Host ""

exit 0
