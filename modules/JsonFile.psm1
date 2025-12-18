<#
.SYNOPSIS
JSON file operations

.DESCRIPTION
Provides functions for reading JSON files and validating JSON format/structure.

.EXAMPLE
Import-Module "$PSScriptRoot\JsonFile.psm1" -Force
$config = Read-JsonFile -Path "config\apps\init_apps.json"

.EXAMPLE
$json = Read-JsonFile -Path $File
if (-not (Test-JsonFormat -JsonObject $json -RequiredProperties @('buckets', 'apps'))) {
    Write-Error "Invalid format"
    exit 4
}
#>

function Read-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    # Resolve path to handle spaces/hyphens safely (works even if the file doesn't exist yet)
    try {
        if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
            $Path = Resolve-LiteralPathSafe -Path $Path
        } else {
            $Path = [System.IO.Path]::GetFullPath($Path)
        }
    } catch { }
    
    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        throw "File not found: $Path"
    }
    
    try {
        $content = Get-Content -Raw -Path $Path
        return $content | ConvertFrom-Json
    } catch {
        Write-Error "Failed to parse JSON from: $Path"
        Write-Error "Error: $($_.Exception.Message)"
        throw
    }
}

function Test-JsonFormat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$JsonObject,
        
        [Parameter(Mandatory=$true)]
        [string[]]$RequiredProperties
    )
    
    if (-not $JsonObject) {
        return $false
    }
    
    $properties = $JsonObject.PSObject.Properties.Name
    
    foreach ($required in $RequiredProperties) {
        if ($properties -notcontains $required) {
            return $false
        }
    }
    
    return $true
}

Export-ModuleMember -Function @(
    'Read-JsonFile',
    'Test-JsonFormat'
)
