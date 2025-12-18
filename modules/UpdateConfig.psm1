<#
.SYNOPSIS
Update configuration

.DESCRIPTION
Provides functions for reading update configuration from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\UpdateConfig.psm1" -Force
$removeOldVersions = Get-UpdateConfig -ProjectRoot $ProjectRoot
#>

function Get-UpdateConfig {
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
    
    # Default: remove old versions
    $removeOldVersions = $true
    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    
    if ($config -and $config.updates -and ($config.updates.PSObject.Properties.Name -contains 'remove_old_versions')) {
        $removeOldVersions = [bool]$config.updates.remove_old_versions
    }
    
    return $removeOldVersions
}

Export-ModuleMember -Function @(
    'Get-UpdateConfig'
)
