<#
.SYNOPSIS
Base manager configuration reading

.DESCRIPTION
Provides base function for reading manager_config.json, with optional local overrides
from manager_config.local.json (intended for machine-specific values and secrets).
Specific config concerns (logging, backup, updates) are handled by dedicated modules.

.PARAMETER ProjectRoot
Root directory of the project (where config folder is located)

.EXAMPLE
Import-Module "$PSScriptRoot\ManagerConfig.psm1" -Force
$config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
#>

function Get-ManagerConfigJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot
    )
    
    function Test-IsJsonObject {
        param([Parameter(Mandatory=$true)]$Value)
        return ($null -ne $Value -and $Value.GetType().Name -eq 'PSCustomObject')
    }

    function Copy-JsonValue {
        param([Parameter(Mandatory=$true)]$Value)

        if ($null -eq $Value) { return $null }

        if (Test-IsJsonObject -Value $Value) {
            $copy = [pscustomobject]@{}
            foreach ($prop in $Value.PSObject.Properties) {
                $propValue = Copy-JsonValue -Value $prop.Value
                Add-Member -InputObject $copy -MemberType NoteProperty -Name $prop.Name -Value $propValue -Force
            }
            return $copy
        }

        if ($Value -is [object[]]) {
            return @($Value)
        }

        return $Value
    }

    function Merge-ManagerConfigObjects {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]$Base,
            [Parameter(Mandatory=$true)]$Override
        )

        if ($null -eq $Base) { return (Copy-JsonValue -Value $Override) }
        if ($null -eq $Override) { return (Copy-JsonValue -Value $Base) }

        if (-not (Test-IsJsonObject -Value $Base) -or -not (Test-IsJsonObject -Value $Override)) {
            return (Copy-JsonValue -Value $Override)
        }

        $result = Copy-JsonValue -Value $Base
        foreach ($prop in $Override.PSObject.Properties) {
            $overrideValue = $prop.Value
            $hasBaseProp = $result.PSObject.Properties.Name -contains $prop.Name
            if ($hasBaseProp) {
                $baseValue = $result.$($prop.Name)
                if ((Test-IsJsonObject -Value $baseValue) -and (Test-IsJsonObject -Value $overrideValue)) {
                    $merged = Merge-ManagerConfigObjects -Base $baseValue -Override $overrideValue
                    $result.$($prop.Name) = $merged
                    continue
                }
            }
            $result.$($prop.Name) = (Copy-JsonValue -Value $overrideValue)
        }

        return $result
    }

    $configPath = Join-Path $ProjectRoot 'config\manager_config.json'
    $localConfigPath = Join-Path $ProjectRoot 'config\manager_config.local.json'
    
    # Resolve paths robustly; prefer PathTools when available, but fall back to GetFullPath.
    try {
        if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
            $configPath = Resolve-LiteralPathSafe -Path $configPath
            $localConfigPath = Resolve-LiteralPathSafe -Path $localConfigPath
        } else {
            $configPath = [System.IO.Path]::GetFullPath($configPath)
            $localConfigPath = [System.IO.Path]::GetFullPath($localConfigPath)
        }
    } catch { }

    $baseConfig = $null
    if (Test-Path $configPath) {
        $content = Get-Content -Raw -Path $configPath
        $baseConfig = $content | ConvertFrom-Json
    }

    $localConfig = $null
    if (Test-Path $localConfigPath) {
        $localContent = Get-Content -Raw -Path $localConfigPath
        $localConfig = $localContent | ConvertFrom-Json
    }

    if ($baseConfig -and $localConfig) {
        return Merge-ManagerConfigObjects -Base $baseConfig -Override $localConfig
    }

    if ($localConfig) { return $localConfig }
    if ($baseConfig) { return $baseConfig }
    return $null
}

function Get-ManagerVersionLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $cfg = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    $ver = $null
    try { $ver = [string]$cfg.manager.version } catch { }
    if (-not $ver) { return $null }

    $ver = $ver.Trim()
    if (-not $ver) { return $null }

    if ($ver.StartsWith('v')) { return $ver }
    return "v$ver"
}

function Get-ExportsAddVersionToUnlockedApps {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $cfg = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    try {
        if ($cfg -and $cfg.exports -and ($cfg.exports.add_version_to_unlocked_apps -eq $true)) {
            return $true
        }
    } catch { }

    return $false
}

Export-ModuleMember -Function @(
    'Get-ManagerConfigJson',
    'Get-ManagerVersionLabel',
    'Get-ExportsAddVersionToUnlockedApps'
)
