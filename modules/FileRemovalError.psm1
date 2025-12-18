<#
.SYNOPSIS
File removal error help messages

.DESCRIPTION
Provides standard error help messages for file removal failures.

.EXAMPLE
Import-Module "$PSScriptRoot\FileRemovalError.psm1" -Force
Write-FileRemovalErrorHelp -ScoopRoot $ScoopRoot
#>

function Write-FileRemovalErrorHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    Write-Host "Possible causes:"
    Write-Host "  - Files are in use by running applications"
    Write-Host "  - Insufficient permissions"
    Write-Host "  - Files are locked by Windows"
    Write-Host ""
    Write-Host "Solutions:"
    Write-Host "  1. Close all apps installed via Scoop"
    Write-Host "  2. Restart your PC and try again"
    Write-Host "  3. Manually delete: $ScoopRoot"
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Write-FileRemovalErrorHelp'
)
