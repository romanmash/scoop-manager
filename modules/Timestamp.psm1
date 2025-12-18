<#
.SYNOPSIS
Shared module for generating timestamp strings

.DESCRIPTION
Provides reusable function to generate timestamp strings in standard format
used for export file naming.

.PARAMETER Format
Optional format string (default: 'yyyy-MM-dd_HHmmss')

.EXAMPLE
Import-Module "$PSScriptRoot\Timestamp.psm1" -Force
$stamp = Get-Timestamp
# Returns: "2025-11-12_143022"
#>

function Get-Timestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Format = 'yyyy-MM-dd_HHmmss'
    )
    
    return Get-Date -Format $Format
}

Export-ModuleMember -Function @(
    'Get-Timestamp'
)
