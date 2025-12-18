<#
.SYNOPSIS
Backup configuration

.DESCRIPTION
Provides functions for reading backup configuration from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\BackupConfig.psm1" -Force
$compression = Get-BackupCompression -ProjectRoot $ProjectRoot
Show-BackupCompressionInfo -ProjectRoot $ProjectRoot
#>

function Get-BackupCompression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    # Import ManagerConfig for base reading
    $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
    if (-not (Test-Path $ManagerConfigPath)) {
        Write-Error "ManagerConfig.psm1 module not found at: $ManagerConfigPath"
        throw "ManagerConfig.psm1 module not found"
    }
    Import-Module $ManagerConfigPath -Force
    
    # Default compression level
    $compressionLevel = "Optimal"
    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    
    if ($config -and $config.backup -and $config.backup.compression_level) {
        $requestedLevel = $config.backup.compression_level
        # Validate compression level
        $validLevels = @("NoCompression", "Fastest", "Optimal")
        if ($validLevels -contains $requestedLevel) {
            $compressionLevel = $requestedLevel
        } else {
            Write-Warning "Invalid compression level '$requestedLevel' in config, using default: Optimal. Valid values: NoCompression, Fastest, Optimal"
        }
    }
    
    return $compressionLevel
}

function Show-BackupCompressionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    $compression = Get-BackupCompression -ProjectRoot $ProjectRoot
    $configPath = Join-Path $ProjectRoot 'config\manager_config.json'
    
    Write-SubsectionHeader -Title 'Compression Configuration'
    Write-Host "[*] Current compression level: $compression"
    Write-Host ""
    Write-Host "Available compression levels:"
    Write-Host "  - NoCompression: Fastest, no compression"
    Write-Host "  - Fastest: Fast compression, moderate size reduction"
    Write-Host "  - Optimal: Best compression, slower but smaller archives (default)"
    Write-Host ""
    Write-Host "To change compression level, edit:"
    Write-Host "  $configPath"
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Get-BackupCompression',
    'Show-BackupCompressionInfo'
)
