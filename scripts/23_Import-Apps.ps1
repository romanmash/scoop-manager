<#
.SYNOPSIS
Imports apps from internal JSON export

.CMD
-
#>

[CmdletBinding()]
param(
    [string]$File,
    [switch]$SuppressConfigMessage,
    [switch]$SuppressStealthMessage
)

$ErrorActionPreference = 'Stop'

# Path resolution (standard)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Load shared modules
$FindLatestPath = Join-Path $ProjectRoot 'modules\LatestExportFile.psm1'
Import-Module $FindLatestPath -Force
$JsonPath = Join-Path $ProjectRoot 'modules\JsonFile.psm1'
Import-Module $JsonPath -Force

# Load fresh installation check module
$TestFreshPath = Join-Path $ProjectRoot 'modules\FreshInstallation.psm1'
Import-Module $TestFreshPath -Force

# Pick default export file if none specified (prefer internal format)
if (-not $File) {
    $ConfigDir = Join-Path $ProjectRoot 'config\apps'
    try {
        $File = Find-LatestExportFile -ConfigDir $ConfigDir -Pattern "export_apps_*.json" -ErrorMessage "No export_apps_*.json found in: $ConfigDir`n        Run script 71_Export-Apps to create an export first.`n        Or use script 29_Import-Scoop for canonical Scoop exports."
    } catch {
        exit 4
    }
}

$File = (Resolve-Path $File).Path

# Load ScoopPathTools module for path replacement
$ScoopPathToolsPath = Join-Path $ProjectRoot 'modules\ScoopPathTools.psm1'
Import-Module $ScoopPathToolsPath -Force

# Load bootstrap module to get ScoopRoot
$BootstrapPath = Join-Path $ProjectRoot 'modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment -SuppressStealthMessage:$SuppressStealthMessage
$ScoopRoot = $ctx.ScoopRoot

# Verify it's the init_apps.json format (has buckets and apps arrays)
try {
    $json = Read-JsonFile -Path $File
    if (-not (Test-JsonFormat -JsonObject $json -RequiredProperties @('buckets', 'apps'))) {
        Write-Error "File does not match expected format (missing buckets or apps arrays)"
        Write-Host "Expected format: init_apps.json / export_apps_*.json"
        Write-Host "For canonical Scoop exports, use script 29_Import-Scoop"
        Write-Host ""
        exit 4
    }
} catch {
    Write-Error "Failed to parse JSON file: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

# Handle config key if it exists (Order of operations: parse -> replace paths in-memory -> import -> write config)
$configToWrite = $null
if ($json.PSObject.Properties.Name -contains 'config' -and $null -ne $json.config) {
    $config = $json.config
    
    # Extract old path prefix from config.root_path
    if ($config.root_path) {
        # Ensure root_path is a string (handle case where it might be an object)
        $oldRootPath = [string]$config.root_path
        $oldPrefix = Get-PathPrefix -Path $oldRootPath
        $newPrefix = Get-PathPrefix -Path $ScoopRoot
        
        # Ensure $ScoopRoot is a string (convert to string if it's an object)
        $newRootPath = [string]$ScoopRoot
        
        if ($oldPrefix -and $newPrefix -and $oldPrefix -ne $newPrefix) {
            # Replace all path references in config object (in-memory only)
            $config = Update-PathsInJsonObject -JsonObject $config -OldPrefix $oldPrefix -NewPrefix $newPrefix
            
            # Update root_path to new location (ensure it's a string)
            $config.root_path = $newRootPath
            
            # Store for writing after import succeeds
            $configToWrite = $config
        } elseif ($oldPrefix -and $newPrefix -and $oldPrefix -eq $newPrefix) {
            # Same prefix, but still update root_path to current location
            $config.root_path = $newRootPath
            $configToWrite = $config
        } else {
            # No old prefix found or invalid, just update root_path
            $config.root_path = $newRootPath
            $configToWrite = $config
        }
    } else {
        # No root_path, but config exists - keep as is
        # Ensure all path properties are strings (not objects)
        if ($config.PSObject.Properties.Name -contains 'root_path' -and $config.root_path) {
            $config.root_path = [string]$config.root_path
        }
        if ($config.PSObject.Properties.Name -contains 'global_path' -and $config.global_path) {
            $config.global_path = [string]$config.global_path
        }
        $configToWrite = $config
    }
}

# Create temporary JSON file without config key for 22_Install-InitApps
$tempJson = [pscustomobject]@{
    buckets = $json.buckets
    apps = $json.apps
}
$tempJsonPath = Join-Path $env:TEMP "import_apps_$(New-Guid).json"
try {
    Write-JsonFileUtf8NoBom -Path $tempJsonPath -Object $tempJson -Depth 3
} catch {
    Write-Error "Failed to create temporary JSON file: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

# Call script 22_Install-InitApps with the temporary file path
# Script 22_Install-InitApps handles all installation logic including buckets, apps, holds, and multi-version resets
# Capture exit code from called script
$exitCode = 0
try {
    & (Join-Path $ScriptDir '22_Install-InitApps.ps1') -ConfigPath $tempJsonPath
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq $null) { $exitCode = 0 }
} catch {
    $exitCode = 4
}

# Clean up temporary file
try {
    Remove-Item -Path $tempJsonPath -Force -ErrorAction SilentlyContinue
} catch {
    # Ignore cleanup errors
}

# If import succeeded and config exists, write config.json
if ($exitCode -eq 0 -and $null -ne $configToWrite) {
    Write-Host ""
    Write-Host "[*] Writing config.json..."
    [Console]::Out.Flush()
    
    $configPath = Join-Path $ScoopRoot 'config.json'
    # Resolve path to handle spaces correctly
    try {
        $configPath = [System.IO.Path]::GetFullPath($configPath)
    } catch {
        # If GetFullPath fails, use as-is (will work with Test-Path)
    }
    try {
        # Convert to JSON with error handling
        # Use Depth 3 to match export format (export uses Depth 3)
        Write-Host "[*] Converting config to JSON format..."
        [Console]::Out.Flush()
        
        $configJsonContent = $null
        try {
            # Use Depth 3 to match the export format and avoid hanging on complex objects
            $configJsonContent = $configToWrite | ConvertTo-Json -Depth 3 -ErrorAction Stop
        } catch {
            Write-Warning "Failed to convert config to JSON: $($_.Exception.Message)"
            Write-Host "[*] Trying with minimal depth..."
            [Console]::Out.Flush()
            try {
                $configJsonContent = $configToWrite | ConvertTo-Json -Depth 1 -ErrorAction Stop
            } catch {
                Write-Warning "Failed to convert config to JSON even with minimal depth: $($_.Exception.Message)"
                Write-Host "[*] Skipping config.json write"
                Write-Host ""
                [Console]::Out.Flush()
                exit $exitCode
            }
        }
        
        Write-Host "[*] Writing config.json to disk..."
        [Console]::Out.Flush()

        Write-TextFileUtf8NoBom -Path $configPath -Content $configJsonContent
        
        Write-Host "[OK] Restored config.json with updated paths"
        Write-Host ""
        [Console]::Out.Flush()
    } catch {
        Write-Warning "Failed to write config.json: $($_.Exception.Message)"
        Write-Host ""
        [Console]::Out.Flush()
    }
} elseif ($exitCode -eq 0 -and -not $SuppressConfigMessage) {
    Write-Host ""
    Write-Host "[*] No config.json to restore (config key not found in apps.json)"
    Write-Host ""
    [Console]::Out.Flush()
}

# Force output flush before exiting
[Console]::Out.Flush()

exit $exitCode
