<#
.SYNOPSIS
Logging configuration

.DESCRIPTION
Provides functions for reading logging configuration from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\LoggingConfig.psm1" -Force
$loggingEnabled = Get-LoggingConfig -ProjectRoot $ProjectRoot
#>

function Get-LoggingConfig {
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
    
    # Default: logging enabled
    $loggingEnabled = $true
    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    
    if ($config -and $config.logging -and ($config.logging.PSObject.Properties.Name -contains 'enabled')) {
        $loggingEnabled = [bool]$config.logging.enabled
    }
    
    return $loggingEnabled
}

Export-ModuleMember -Function @(
    'Get-LoggingConfig'
)
