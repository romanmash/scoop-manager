<#
.SYNOPSIS
Creates a backup archive of migration pack

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Check if Scoop is installed - required for backing up apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load shared modules
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$BackupConfigPath = Join-Path $ProjectRoot 'modules\BackupConfig.psm1'
Import-Module $BackupConfigPath -Force
$ExportAppsPath = Join-Path $ProjectRoot 'modules\ExportApps.psm1'
Import-Module $ExportAppsPath -Force
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'BACKUP MIGRATION PACK'

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

# Generate timestamp
$timestamp = Get-Timestamp

# Create backup/migration directory if it doesn't exist
$MigrationDir = Join-Path $ProjectRoot 'backup\migration'
if (-not (Test-Path $MigrationDir)) {
    New-Item -ItemType Directory -Force -Path $MigrationDir | Out-Null
}

# Generate archive filename
$archiveName = "backup_migration_{0}.zip" -f $timestamp
$archivePath = Join-Path $MigrationDir $archiveName

Write-SubsectionHeader -Title 'Creating Migration Pack'

# Export apps configuration (includes config in the export, but we'll separate it)
Write-Host "[*] Exporting apps configuration..."
$appsJsonPath = Export-AppsConfiguration -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -Timestamp $timestamp
if (-not $appsJsonPath) {
    Write-Error "Failed to export apps configuration"
    Write-Host ""
    exit 4
}

# Read the exported JSON and remove config key (we'll store config.json separately)
$appsJsonContent = Get-Content -Raw -Path $appsJsonPath | ConvertFrom-Json
if ($appsJsonContent.PSObject.Properties.Name -contains 'config') {
    $appsJsonContent.PSObject.Properties.Remove('config')
}

# Write apps.json without config
$tempAppsJson = Join-Path $env:TEMP "apps_$(New-Guid).json"
$appsJsonContentString = $appsJsonContent | ConvertTo-Json -Depth 3
Write-TextFileUtf8NoBom -Path $tempAppsJson -Content $appsJsonContentString

# Copy config.json separately (if it exists)
$configJsonPath = Join-Path $ScoopRoot 'config.json'
# Resolve path to handle spaces correctly
try {
    $configJsonPath = [System.IO.Path]::GetFullPath($configJsonPath)
} catch {
    # If GetFullPath fails, use as-is (Test-Path will handle it)
}
$tempConfigJson = $null
if (Test-Path $configJsonPath) {
    Write-Host "[*] Copying config.json..."
    $tempConfigJson = Join-Path $env:TEMP "config_$(New-Guid).json"
    Copy-Item -Path $configJsonPath -Destination $tempConfigJson -Force
}

# Check if persist folder exists
$persistDir = Join-Path $ScoopRoot 'persist'
$hasPersist = (Test-Path $persistDir) -and ((Get-ChildItem -Path $persistDir -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)

if (-not $hasPersist) {
    Write-Host "[*] No persist folder found, migration pack will contain apps.json only"
    Write-Host ""
}

# Get compression level from config
$compressionLevel = Get-BackupCompression -ProjectRoot $ProjectRoot

# Load compression classes
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# Map compression level string to CompressionLevel enum
$compressionEnum = switch ($compressionLevel) {
    "NoCompression" { [System.IO.Compression.CompressionLevel]::NoCompression }
    "Fastest" { [System.IO.Compression.CompressionLevel]::Fastest }
    "Optimal" { [System.IO.Compression.CompressionLevel]::Optimal }
    default { [System.IO.Compression.CompressionLevel]::Optimal }
}

# Remove existing archive if it exists
if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
}

Write-Host "[*] Creating zip archive..."
Write-Host "[*] Archive: $archiveName"
Write-Host ""

# Create zip archive
$zip = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)

try {
    $fileCount = 0
    $dirCount = 0
    
    # Add apps.json
    $appsJsonEntry = $zip.CreateEntry("apps.json", $compressionEnum)
    $appsJsonEntryStream = $appsJsonEntry.Open()
    try {
        $appsJsonFileStream = [System.IO.File]::OpenRead($tempAppsJson)
        try {
            $appsJsonFileStream.CopyTo($appsJsonEntryStream)
        } finally {
            $appsJsonFileStream.Close()
        }
    } finally {
        $appsJsonEntryStream.Close()
    }
    $fileCount++
    
    # Add config.json if it exists
    if ($tempConfigJson -and (Test-Path $tempConfigJson)) {
        $configJsonEntry = $zip.CreateEntry("config.json", $compressionEnum)
        $configJsonEntryStream = $configJsonEntry.Open()
        try {
            $configJsonFileStream = [System.IO.File]::OpenRead($tempConfigJson)
            try {
                $configJsonFileStream.CopyTo($configJsonEntryStream)
            } finally {
                $configJsonFileStream.Close()
            }
        } finally {
            $configJsonEntryStream.Close()
        }
        $fileCount++
    }
    
    # Add persist folder if it exists
    if ($hasPersist) {
        $persistParentDir = Split-Path -Parent $persistDir
        $persistParentDirLength = $persistParentDir.Length
        
        # Get all files and directories in persist folder
        $allFiles = Get-ChildItem -Path $persistDir -Recurse -Force -File -ErrorAction SilentlyContinue
        $allDirs = Get-ChildItem -Path $persistDir -Recurse -Force -Directory -ErrorAction SilentlyContinue
        
        if ($null -eq $allFiles) { $allFiles = @() }
        if ($null -eq $allDirs) { $allDirs = @() }
        
        # Add all directories first (including empty ones) to preserve structure
        foreach ($dir in $allDirs) {
            $relativePath = $dir.FullName.Substring($persistParentDirLength + 1)
            $entryName = ($relativePath -replace '\\', '/')
            $null = $zip.CreateEntry($entryName + '/', $compressionEnum)
            $dirCount++
        }
        
        # Add all files
        foreach ($file in $allFiles) {
            $relativePath = $file.FullName.Substring($persistParentDirLength + 1)
            $entryName = $relativePath -replace '\\', '/'
            
            $entry = $zip.CreateEntry($entryName, $compressionEnum)
            $entryStream = $entry.Open()
            
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                } finally {
                    $fileStream.Close()
                }
            } finally {
                $entryStream.Close()
            }
            
            $fileCount++
        }
    }
    
    Write-Host "[OK] Archive created: $archivePath"
    Write-Host "[OK] Files: $fileCount, Directories: $dirCount"
    Write-Host ""
} finally {
    $zip.Dispose()
}

# Clean up temporary files
try {
    Remove-Item -Path $tempAppsJson -Force -ErrorAction SilentlyContinue
    if ($tempConfigJson -and (Test-Path $tempConfigJson)) {
        Remove-Item -Path $tempConfigJson -Force -ErrorAction SilentlyContinue
    }
} catch {
    # Ignore cleanup errors
}

# Show compression info
Show-BackupCompressionInfo -ProjectRoot $ProjectRoot

$archiveSize = (Get-Item $archivePath).Length
$archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
Write-Host "[*] Archive size: $archiveSizeMB MB"
Write-Host "[*] Archive location: $archivePath"
Write-Host ""

Write-SectionHeader -Title '[OK] Migration pack backup complete!'

exit 0
