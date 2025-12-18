<#
.SYNOPSIS
Stealth configuration

.DESCRIPTION
Provides functions for reading stealth configuration from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\StealthConfig.psm1" -Force
$excludePaths = Get-StealthExcludePaths -ProjectRoot $ProjectRoot
#>

function Get-StealthExcludePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    # Import ManagerConfig for base reading
    $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
    if (-not (Test-Path -LiteralPath $ManagerConfigPath)) {
        Write-Error "ManagerConfig.psm1 module not found at: $ManagerConfigPath"
        throw "ManagerConfig.psm1 module not found"
    }
    Import-Module $ManagerConfigPath -Force
    
    # Default: empty array (no exclusions)
    $excludePaths = @()
    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    
    # Read exclude_paths from config if present
    if ($config -and $config.stealth -and $config.stealth.PSObject.Properties.Name -contains 'exclude_paths') {
        $excludePathsConfig = $config.stealth.exclude_paths
        if ($excludePathsConfig -and $excludePathsConfig -is [System.Array]) {
            # Filter out null, empty, or non-string values
            $excludePaths = $excludePathsConfig | Where-Object { $_ -and $_ -is [string] -and $_.Trim() -ne '' }
        }
    }
    
    return $excludePaths
}

Export-ModuleMember -Function @(
    'Get-StealthExcludePaths'
)
