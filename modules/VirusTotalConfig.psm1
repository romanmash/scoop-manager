<#
.SYNOPSIS
VirusTotal configuration

.DESCRIPTION
Provides helper for reading VirusTotal API key from manager_config.json.

.EXAMPLE
Import-Module "$PSScriptRoot\VirusTotalConfig.psm1" -Force
$vtConfig = Get-VirusTotalConfig -ProjectRoot $ProjectRoot
if ($vtConfig -and $vtConfig.ApiKey) {
    & $ScoopShim config virustotal_api_key $vtConfig.ApiKey
}
#>

function Get-VirusTotalConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    # Import ManagerConfig for base reading
    $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
    if (-not (Test-Path -LiteralPath $ManagerConfigPath)) {
        Write-Error "ManagerConfig.psm1 module not found at: $ManagerConfigPath"
        throw "ManagerConfig.psm1 module not found"
    }

    Import-Module $ManagerConfigPath -Force

    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
    if (-not $config -or -not $config.virustotal) {
        return $null
    }

    $vtSection = $config.virustotal

    $apiKey = $null
    if ($vtSection.PSObject.Properties.Name -contains 'api_key') {
        $rawKey = $vtSection.api_key
        if ($rawKey -and $rawKey -is [string]) {
            $trimmed = $rawKey.Trim()
            if ($trimmed.Length -gt 0 -and $trimmed -ne 'YOUR_API_KEY_HERE') {
                $apiKey = $trimmed
            }
        }
    }

    if (-not $apiKey) {
        return $null
    }

    [pscustomobject]@{
        ApiKey = $apiKey
    }
}

Export-ModuleMember -Function @(
    'Get-VirusTotalConfig'
)
