<#
.SYNOPSIS
Shared module for patching install.json files to point to bucket manifests instead of workspace

.DESCRIPTION
After Scoop installs a version, it may create install.json pointing to workspace.
This module patches install.json to point to bucket manifests instead, ensuring apps remain updateable.

.PARAMETER ScoopRoot
Path to Scoop root directory

.PARAMETER AppName
Name of the app

.PARAMETER Version
Version of the app to patch

.EXAMPLE
Import-Module "$PSScriptRoot\InstallJson.psm1" -Force
Update-InstallJsonToBucket -ScoopRoot $ScoopRoot -AppName "rclone" -Version "1.68.0"
#>

function Update-InstallJsonToBucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$AppName,
        
        [Parameter(Mandatory=$true)]
        [string]$Version
    )
    
    # Find bucket manifest for this app
    $bucketsDir = Join-Path $ScoopRoot 'buckets'
    $bucketManifestPath = $null
    $bucketName = $null
    
    if (Test-Path $bucketsDir) {
        $buckets = Get-ChildItem -Path $bucketsDir -Directory
        foreach ($bucket in $buckets) {
            $manifestPath = Join-Path $bucket.FullName "bucket\$AppName.json"
            if (Test-Path $manifestPath) {
                $bucketManifestPath = $manifestPath
                $bucketName = $bucket.Name
                break
            }
        }
    }
    
    if (-not $bucketManifestPath) {
        Write-Verbose "No bucket manifest found for $AppName, skipping install.json patch"
        return $false
    }
    
    # Paths for install.json files
    $appVersionDir = Join-Path $ScoopRoot "apps\$AppName\$Version"
    $currentDir = Join-Path $ScoopRoot "apps\$AppName\current"
    $versionInstallJson = Join-Path $appVersionDir "install.json"
    $currentInstallJson = Join-Path $currentDir "install.json"
    
    $patched = $false
    
    # Patch version-specific install.json
    if (Test-Path $versionInstallJson) {
        $installData = Get-Content -Raw -Path $versionInstallJson | ConvertFrom-Json
        $needsPatch = $false
        
        # Check if it points to workspace
        if ($installData.url -and $installData.url -match '[\\/]workspace[\\/]') {
            $needsPatch = $true
        }
        # Check if it uses "bucket" format instead of "url" format
        elseif ($installData.bucket -and -not $installData.url) {
            $needsPatch = $true
        }
        
        if ($needsPatch) {
            # Create new hashtable with correct format
            $newInstallData = @{
                url = $bucketManifestPath
                architecture = if ($installData.architecture) { $installData.architecture } else { "64bit" }
            }
            
            # Preserve other fields (like "hold" if present)
            foreach ($prop in $installData.PSObject.Properties) {
                if ($prop.Name -ne 'bucket' -and $prop.Name -ne 'url' -and $prop.Name -ne 'architecture') {
                    $newInstallData[$prop.Name] = $prop.Value
                }
            }
            
            # Convert back to JSON and save
            Write-JsonFileUtf8NoBom -Path $versionInstallJson -Object $newInstallData -Depth 10 -Compress
            
            Write-Verbose "Patched ${AppName}@${Version} install.json to point to bucket"
            $patched = $true
        }
    }
    
    # Patch current install.json if this version is current
    # Check if current symlink points to this version
    $isCurrentVersion = $false
    if (Test-Path $currentDir) {
        $currentLink = Get-Item $currentDir -Force -ErrorAction SilentlyContinue
        if ($currentLink -and $currentLink.LinkType -eq 'SymbolicLink') {
            $target = $currentLink.Target
            if ($target) {
                $currentVersionDir = Split-Path -Leaf $target
                if ($currentVersionDir -eq $Version) {
                    $isCurrentVersion = $true
                }
            }
        }
        # Try alternative method if symlink resolution failed
        if (-not $isCurrentVersion) {
            $resolvedPath = (Get-Item $currentDir -ErrorAction SilentlyContinue).Target
            if ($resolvedPath) {
                $currentVersionDir = Split-Path -Leaf $resolvedPath
                if ($currentVersionDir -eq $Version) {
                    $isCurrentVersion = $true
                }
            }
        }
    }
    
    if ($isCurrentVersion -and (Test-Path $currentInstallJson)) {
        $currentInstallData = Get-Content -Raw -Path $currentInstallJson | ConvertFrom-Json
        $needsPatch = $false
        
        # Check if it points to workspace
        if ($currentInstallData.url -and $currentInstallData.url -match '[\\/]workspace[\\/]') {
            $needsPatch = $true
        }
        # Check if it uses "bucket" format instead of "url" format
        elseif ($currentInstallData.bucket -and -not $currentInstallData.url) {
            $needsPatch = $true
        }
        
        if ($needsPatch) {
            # Create new hashtable with correct format
            $newInstallData = @{
                url = $bucketManifestPath
                architecture = if ($currentInstallData.architecture) { $currentInstallData.architecture } else { "64bit" }
            }
            
            # Preserve other fields (like "hold" if present)
            foreach ($prop in $currentInstallData.PSObject.Properties) {
                if ($prop.Name -ne 'bucket' -and $prop.Name -ne 'url' -and $prop.Name -ne 'architecture') {
                    $newInstallData[$prop.Name] = $prop.Value
                }
            }
            
            # Convert back to JSON and save
            Write-JsonFileUtf8NoBom -Path $currentInstallJson -Object $newInstallData -Depth 10 -Compress
            
            Write-Verbose "Patched $AppName current install.json to point to bucket"
            $patched = $true
        }
    }
    
    # Clean up workspace manifest if it exists
    $workspaceManifest = Join-Path $ScoopRoot "workspace\$AppName.json"
    if (Test-Path $workspaceManifest) {
        Remove-Item -Path $workspaceManifest -Force -ErrorAction SilentlyContinue
        Write-Verbose "Removed workspace manifest for $AppName"
    }
    
    return $patched
}

Export-ModuleMember -Function @(
    'Update-InstallJsonToBucket'
)
