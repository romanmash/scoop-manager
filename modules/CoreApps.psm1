<#
.SYNOPSIS
Core apps configuration helper

.DESCRIPTION
Reads the list of core apps from config/manager_config.json (core.apps).
Core apps are:
- Allowed to exist in a "fresh" installation (scripts 22/23/26/29 gates)
- Preserved by script 91 (uninstall user apps)
- Installed by script 19 after Scoop core install
#>

function Get-CoreApps {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $managerConfigModule = Join-Path $ProjectRoot 'modules\ManagerConfig.psm1'
    if (-not (Test-Path -LiteralPath $managerConfigModule)) {
        Write-Error "Core apps config requires ManagerConfig module at: $managerConfigModule"
        return @()
    }

    Import-Module $managerConfigModule -Force
    $cfg = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    if (-not $cfg) {
        Write-Error "Core apps config requires config/manager_config.json (failed to load)."
        return @()
    }

    if (-not ($cfg.PSObject.Properties.Name -contains 'core') -or -not $cfg.core) {
        Write-Error "Core apps config requires 'core.apps' in config/manager_config.json."
        return @()
    }

    if (-not ($cfg.core.PSObject.Properties.Name -contains 'apps') -or -not $cfg.core.apps) {
        Write-Error "Core apps config requires 'core.apps' array in config/manager_config.json."
        return @()
    }

    $apps = @()
    foreach ($a in $cfg.core.apps) {
        if ($a -and ([string]$a).Trim().Length -gt 0) {
            $apps += ([string]$a).Trim().ToLowerInvariant()
        }
    }

    $apps = $apps | Sort-Object -Unique
    if ($apps.Count -eq 0) {
        Write-Error "Core apps config 'core.apps' is empty."
        return @()
    }

    if ($apps -notcontains 'scoop') {
        Write-Error "Core apps config must include 'scoop' in 'core.apps'."
        return @()
    }

    return $apps
}

Export-ModuleMember -Function @(
    'Get-CoreApps'
)

