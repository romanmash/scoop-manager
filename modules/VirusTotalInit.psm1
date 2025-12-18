<#
.SYNOPSIS
VirusTotal integration initialization helper

.DESCRIPTION
Centralizes best-effort initialization of VirusTotal integration to avoid
duplicated try/catch blocks across scripts. Returns VirusTotal settings
or $null when integration is unavailable/disabled.

.EXAMPLE
Import-Module "$ProjectRoot\modules\VirusTotalInit.psm1" -Force
$vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
if ($vtSettings) {
    $result = Invoke-VirusTotalCheckForApp -AppName '7zip' -ScoopShim $ScoopShim -Settings $vtSettings
}
#>

function Initialize-VirusTotalIntegration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $VirusTotalScanPath = Join-Path $ProjectRoot 'modules\VirusTotalScan.psm1'
    if (-not (Test-Path -LiteralPath $VirusTotalScanPath)) {
        return $null
    }

    try {
        # Import into global scope so scripts that import VirusTotalInit can call
        # Invoke-VirusTotalCheckForApp / Invoke-VirusTotalPreInstallDecision directly.
        Import-Module $VirusTotalScanPath -Force -Global
        if (-not (Get-Command -Name Get-VirusTotalSettings -ErrorAction SilentlyContinue)) {
            throw "Get-VirusTotalSettings not available after importing VirusTotalScan module."
        }
        return Get-VirusTotalSettings -ProjectRoot $ProjectRoot
    } catch {
        Write-Warning "VirusTotal integration failed to initialize; checks will be skipped. $($_.Exception.Message)"
        Write-Host ""
        return $null
    }
}

Export-ModuleMember -Function @(
    'Initialize-VirusTotalIntegration'
)
