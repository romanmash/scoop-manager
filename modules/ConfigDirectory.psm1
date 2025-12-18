<#
.SYNOPSIS
Shared module for creating/ensuring config directory exists

.DESCRIPTION
Creates the config directory (and optional subdirectory) if it doesn't exist. 
Returns the path to the config directory or subdirectory.

.PARAMETER ProjectRoot
Root directory of the project

.PARAMETER Subdirectory
Optional subdirectory name (e.g., "apps" or "scoop")

.EXAMPLE
Import-Module "$PSScriptRoot\ConfigDirectory.psm1" -Force
$ConfigDir = New-ConfigDirectory -ProjectRoot $ProjectRoot
$AppsDir = New-ConfigDirectory -ProjectRoot $ProjectRoot -Subdirectory "apps"
#>

function New-ConfigDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$Subdirectory
    )
    
    $ConfigDir = Join-Path $ProjectRoot 'config'
    
    # Resolve path to handle spaces correctly (ensures proper path expansion)
    try {
        $ConfigDir = [System.IO.Path]::GetFullPath($ConfigDir)
    } catch {
        # If GetFullPath fails, use as-is (New-Item will handle it)
    }
    
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    }
    
    if ($Subdirectory) {
        $SubDir = Join-Path $ConfigDir $Subdirectory
        # Resolve subdirectory path as well
        try {
            $SubDir = [System.IO.Path]::GetFullPath($SubDir)
        } catch {
            # If GetFullPath fails, use as-is (New-Item will handle it)
        }
        if (-not (Test-Path $SubDir)) {
            New-Item -ItemType Directory -Force -Path $SubDir | Out-Null
        }
        return $SubDir
    }
    
    return $ConfigDir
}

Export-ModuleMember -Function @(
    'New-ConfigDirectory'
)
