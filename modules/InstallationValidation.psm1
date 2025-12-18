<#
.SYNOPSIS
Scoop installation validation

.DESCRIPTION
Validates that Scoop installation exists at the specified path.

.EXAMPLE
Import-Module "$PSScriptRoot\InstallationValidation.psm1" -Force
Test-ScoopInstallation -ScoopRoot $ScoopRoot
#>

function Test-ScoopInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    if (-not (Test-Path $ScoopRoot)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        exit 4
    }
}

Export-ModuleMember -Function @(
    'Test-ScoopInstallation'
)
