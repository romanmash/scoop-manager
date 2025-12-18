<#
.SYNOPSIS
Shared module for finding the latest export file

.DESCRIPTION
Provides reusable function for finding the latest export file matching a pattern
(e.g., export_apps_*.json or export_scoop_*.json).

.PARAMETER ConfigDir
Directory to search in (usually config/)

.PARAMETER Pattern
File pattern to match (e.g., "export_apps_*.json")

.PARAMETER ErrorMessage
Custom error message if file not found

.EXAMPLE
Import-Module "$PSScriptRoot\LatestExportFile.psm1" -Force
$file = Find-LatestExportFile -ConfigDir $ConfigDir -Pattern "export_apps_*.json"
#>

function Find-LatestExportFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigDir,
        
        [Parameter(Mandatory=$true)]
        [string]$Pattern,
        
        [Parameter(Mandatory=$false)]
        [string]$ErrorMessage = "No matching file found"
    )
    
    # Resolve path to handle spaces/hyphens safely (works even if the directory doesn't exist yet)
    try {
        if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
            $ConfigDir = Resolve-LiteralPathSafe -Path $ConfigDir
        } else {
            $ConfigDir = [System.IO.Path]::GetFullPath($ConfigDir)
        }
    } catch { }
    
    if (-not (Test-Path $ConfigDir)) {
        Write-Error "Config directory not found: $ConfigDir"
        throw "Config directory not found: $ConfigDir"
    }
    
    $latestFile = Get-ChildItem -Path $ConfigDir -Filter $Pattern | 
                  Sort-Object LastWriteTime -Descending | 
                  Select-Object -First 1
    
    if (-not $latestFile) {
        Write-Error $ErrorMessage
        throw $ErrorMessage
    }
    
    return $latestFile.FullName
}

Export-ModuleMember -Function @(
    'Find-LatestExportFile'
)
