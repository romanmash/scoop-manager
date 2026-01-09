<#
.SYNOPSIS
Update configuration

.DESCRIPTION
Provides functions for reading update configuration from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\UpdateConfig.psm1" -Force
$updateSettings = Get-UpdateConfig -ProjectRoot $ProjectRoot
$updateSettings.RemoveOldVersions
$updateSettings.BackupPersistBeforeUpdate
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
    
    $settings = [pscustomobject]@{
        RemoveOldVersions = $true
        BackupPersistBeforeUpdate = $true
    }
    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    
    if ($config -and $config.updates -and ($config.updates.PSObject.Properties.Name -contains 'remove_old_versions')) {
        $settings.RemoveOldVersions = [bool]$config.updates.remove_old_versions
    }

    if ($config -and $config.updates -and ($config.updates.PSObject.Properties.Name -contains 'backup_persist_before_update')) {
        $settings.BackupPersistBeforeUpdate = [bool]$config.updates.backup_persist_before_update
    }
    
    return $settings
}

Export-ModuleMember -Function @(
    'Get-UpdateConfig'
)
