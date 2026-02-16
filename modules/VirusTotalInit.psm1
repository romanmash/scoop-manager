<#
.SYNOPSIS
VirusTotal integration initialization helper

.DESCRIPTION
Centralizes best-effort initialization of VirusTotal integration to avoid
duplicated try/catch blocks across scripts. Returns VirusTotal settings
or $null when integration is unavailable.

.EXAMPLE
Import-Module "$ProjectRoot\modules\VirusTotalInit.psm1" -Force
$vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
if ($vtSettings) {
    $appName = 'your-app'
    $result = Invoke-VirusTotalCheckForApp -AppName $appName -ScoopShim $ScoopShim -Settings $vtSettings
}

.EXAMPLE
Import-Module "$ProjectRoot\modules\VirusTotalInit.psm1" -Force
$vtSettings = Initialize-VirusTotalManagedFlow -ProjectRoot $ProjectRoot -OperationLabel 'app installation'
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
        # Invoke-VirusTotalCheckForApp / Invoke-VirusTotalGateForApp directly.
        Import-Module $VirusTotalScanPath -Force -Global
        if (-not (Get-Command -Name Get-VirusTotalSettings -ErrorAction SilentlyContinue)) {
            throw "Get-VirusTotalSettings not available after importing VirusTotalScan module."
        }
        return Get-VirusTotalSettings -ProjectRoot $ProjectRoot
    } catch {
        Write-Warning "VirusTotal integration failed to initialize. Install/update/import flows may prompt per app or abort if the VirusTotal gate is unavailable. $($_.Exception.Message)"
        Write-Host ""
        return $null
    }
}

function Initialize-VirusTotalManagedFlow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$OperationLabel
    )

    $vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
    if (-not (Get-Command -Name Invoke-VirusTotalGateForApp -ErrorAction SilentlyContinue)) {
        throw "VirusTotal gate function is unavailable. Cannot continue with $OperationLabel."
    }

    if (-not $vtSettings) {
        Write-Warning "VirusTotal settings are unavailable for this run. Per-app VirusTotal prompts will be shown as Skipped/Error (treated as potentially unsafe)."
        Write-Host "[*] Check earlier VirusTotal initialization output to identify the root cause."
        Write-Host ""
    }

    return $vtSettings
}

Export-ModuleMember -Function @(
    'Initialize-VirusTotalIntegration',
    'Initialize-VirusTotalManagedFlow'
)
