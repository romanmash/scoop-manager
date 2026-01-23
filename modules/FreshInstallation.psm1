<#
.SYNOPSIS
Checks if Scoop installation is fresh (no non-core apps installed)

.DESCRIPTION
This module checks if any user apps are installed in Scoop. Returns a boolean
indicating whether the installation is fresh. This is used by import/install
scripts to ensure they only run on fresh installations.

.PARAMETER ScoopRoot
Path to Scoop root directory

.PARAMETER ScoopShim
Path to the Scoop shim executable (scoop.cmd or scoop)

.OUTPUTS
[bool] Returns $true if installation is fresh (no apps), $false if apps are found.

.EXAMPLE
$ctx = Initialize-ScoopEnvironment
Test-FreshInstallation -ScoopRoot $ctx.ScoopRoot -ScoopShim $ctx.ScoopShim

If apps are installed, displays warning and table, returns $false.
If no apps are installed (fresh installation), displays message and returns $true.
#>

function Test-FreshInstallation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,

        # Apps that are allowed to exist in a "fresh" installation.
        # If not provided, loaded from config/manager_config.json (core.apps).
        [Parameter(Mandatory=$false)]
        [string[]]$CoreApps = $null
    )

    if (-not $CoreApps -or $CoreApps.Count -eq 0) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $coreAppsModule = Join-Path $projectRoot 'modules\CoreApps.psm1'
        if (-not (Test-Path -LiteralPath $coreAppsModule)) {
            Write-Error "Core apps config module not found at: $coreAppsModule"
            return $false
        }
        Import-Module $coreAppsModule -Force
        $CoreApps = Get-CoreApps -ProjectRoot $projectRoot
        if (-not $CoreApps -or $CoreApps.Count -eq 0) {
            return $false
        }
    }

    # Check if Scoop is installed - required to check for apps
    # Use centralized function for consistent warning messages
    # Ensure Test-ScoopInstalled is available (from ScoopEnvironment module)
    if (-not (Get-Command Test-ScoopInstalled -ErrorAction SilentlyContinue)) {
        # Fallback if function not available - check directly
        if (-not (Test-Path $ScoopRoot)) {
            Write-Warning "Scoop is not installed at: $ScoopRoot"
            Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
            Write-Host ""
            return $false
        }
        if (-not (Test-Path $ScoopShim)) {
            Write-Warning "Scoop is not installed at: $ScoopRoot"
            Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
            Write-Host ""
            return $false
        }
    } else {
        if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim)) {
            return $false
        }
    }
    
    # Check for fresh installation using file system (more reliable than parsing scoop list)
    # Fresh installation means:
    # 1. Only core app folders exist in the "apps" folder
    # 2. Shims are not validated when additional core apps are allowed (e.g., git installs many shims).
    
    $appsDir = Join-Path $ScoopRoot 'apps'
    $shimsDir = Join-Path $ScoopRoot 'shims'
    
    $appsFound = $false
    
    try {
        # Check apps folder: should only contain "scoop" folder
        if (Test-Path $appsDir) {
            $appFolders = Get-ChildItem -Path $appsDir -Directory -ErrorAction SilentlyContinue | 
                          Where-Object { $CoreApps -notcontains $_.Name }
            
            if ($appFolders -and $appFolders.Count -gt 0) {
                $appsFound = $true
            }
        }
        
        # Shim validation is intentionally skipped when core apps beyond Scoop are allowed.
        # Git installs many shims (e.g., ssh, scp, bash) that are still part of core setup.
    } catch {
        # If file system check fails, fall back to scoop list (non-critical)
        try {
            $projectRoot = Split-Path -Parent $PSScriptRoot
            Assert-ExternalCommandRunner -Caller 'Test-FreshInstallation'

            $installedCmd = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$false -NoHostOutput
            $installedRaw = if ($installedCmd.Output) { $installedCmd.Output -split "\r?\n" } else { @() }
            $installedText = $installedRaw -join "`n"
            
            # Check if there are apps installed (excluding scoop itself)
            if ($installedText -notmatch "There aren't any apps installed") {
                # Parse app names from list output, exclude 'scoop' itself and header lines
            $apps = $installedRaw | 
                    Select-String -Pattern '^\s*(\S+)\s+\S+\s+\S+' | 
                    ForEach-Object { $_.Matches.Groups[1].Value } |
                    Where-Object { 
                            $CoreApps -notcontains ([string]$_).ToLowerInvariant() -and
                            $_ -ne 'Name' -and 
                            $_ -ne 'Installed' -and 
                            $_ -ne '----' -and
                            $_ -notlike '*:*'
                    }
                
                if ($apps -and $apps.Count -gt 0) {
                    $appsFound = $true
                }
            }
        } catch {
            # If both checks fail, treat as fresh installation (safer default)
            Write-Host "[*] Currently no non-core apps detected."
            return $true
        }
    }
    
    # If apps are found, show warning and return false
    if ($appsFound) {
        Write-Warning "Apps are already installed!"
        Write-Host ""
        Write-Host "Import/Install scripts are only intended for fresh installations."
        Write-Host "Please uninstall existing apps first:"
        Write-Host ""
        Write-Host "  1. Run script 91_Uninstall-Apps to remove all apps"
        Write-Host "  2. Optionally run script 54_Cleanup-PersistAll to remove persist data"
        Write-Host "  3. Then run this script again"
        Write-Host ""
        
        # Show extended app list table (wrapped in try-catch so errors don't prevent return)
        try {
            if (-not (Get-Command Show-ExtendedAppList -ErrorAction SilentlyContinue)) {
                $ModulePath = Join-Path $PSScriptRoot 'ExtendedAppList.psm1'
                if (Test-Path $ModulePath) {
                    Import-Module $ModulePath -Force
                }
            }
            
            # Show table if function is available (function already includes header)
            if (Get-Command Show-ExtendedAppList -ErrorAction SilentlyContinue) {
                Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim
                Write-Host ""
            }
        } catch {
            # If showing table fails, continue anyway - we still need to return
        }
        
        # Return false to indicate apps are found
        return $false
    } else {
        # No apps found - fresh installation
        Write-Host "[*] Currently no non-core apps detected."
        Write-Host ""
        return $true
    }
}

Export-ModuleMember -Function @(
    'Test-FreshInstallation'
)
