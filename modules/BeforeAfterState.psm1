<#
.SYNOPSIS
Shared module for displaying before/after app state

.DESCRIPTION
Provides reusable function to display "Current Apps (Before)" and "Current Apps (After)"
sections using the extended app list format.

.PARAMETER ScoopRoot
Path to Scoop root directory

.PARAMETER ScoopShim
Path to Scoop shim executable

.PARAMETER ShowBefore
If true, shows "Current Apps (Before)" section

.PARAMETER ShowAfter
If true, shows "Current Apps (After)" section

.EXAMPLE
Import-Module "$PSScriptRoot\BeforeAfterState.psm1" -Force
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowBefore
# ... do work ...
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter
#>

function Show-BeforeAfterState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowBefore = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowAfter = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowUpdates = $false,
        
        # Defensive: absorb unexpected default params like -LiteralPath from shell defaults
        [Parameter(Mandatory=$false)]
        [object]$LiteralPath = $null
    )
    
    # Load extended list module as a normal module (no dot-sourcing)
    $ModulePath = Join-Path $PSScriptRoot 'ExtendedAppList.psm1'
    try {
        if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
            $ModulePath = Resolve-LiteralPathSafe -Path $ModulePath
        } else {
            $ModulePath = [System.IO.Path]::GetFullPath($ModulePath)
        }
    } catch { }
    if (-not (Test-Path $ModulePath)) {
        Write-Error "ExtendedAppList.psm1 module not found at: $ModulePath"
        return
    }
    try {
        Import-Module $ModulePath -Force
    } catch {
        Write-Error "Failed to load ExtendedAppList.psm1: $($_.Exception.Message)"
        return
    }
    
    if ($ShowBefore) {
        Write-SubsectionHeader -Title 'Current Apps (Before)'
        Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowUpdates:$ShowUpdates
    }
    
    if ($ShowAfter) {
        Write-SubsectionHeader -Title 'Current Apps (After)'
        Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowUpdates:$ShowUpdates
    }
}

Export-ModuleMember -Function @(
    'Show-BeforeAfterState'
)
