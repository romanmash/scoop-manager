<#
.SYNOPSIS
Restores migration pack from backup archive

.CMD
-
#>

[CmdletBinding()]
param(
    [string]$File
)

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

# Check if Scoop is installed - required for restoring (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load shared modules
$FreshInstallationPath = Join-Path $ProjectRoot 'modules\FreshInstallation.psm1'
Import-Module $FreshInstallationPath -Force
$ScoopPathToolsPath = Join-Path $ProjectRoot 'modules\ScoopPathTools.psm1'
Import-Module $ScoopPathToolsPath -Force
$JsonPath = Join-Path $ProjectRoot 'modules\JsonFile.psm1'
Import-Module $JsonPath -Force
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'RESTORE MIGRATION PACK'

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

# Fresh Installation Check: Verify only "scoop" app is installed
Write-SubsectionHeader -Title 'Checking Installation State'

$isFresh = Test-FreshInstallation -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim
if (-not $isFresh) {
    Write-Warning "Apps are already installed!"
    Write-Host ""
    Write-Host "Migration pack restore requires a fresh Scoop installation."
    Write-Host "Please uninstall and reinstall Scoop first:"
    Write-Host ""
    Write-Host "  1. Run script 99_Uninstall-Scoop to completely remove Scoop"
    Write-Host "  2. Run script 19_Install-PortableScoop to install fresh Scoop"
    Write-Host "  3. Then run this script again"
    Write-Host ""
    exit 4
}

# Persist Folder Check: Verify persist folder doesn't exist or is empty
$persistDir = Join-Path $ScoopRoot 'persist'
if (Test-Path $persistDir) {
    $persistItems = Get-ChildItem -Path $persistDir -Force -ErrorAction SilentlyContinue
    if ($persistItems -and $persistItems.Count -gt 0) {
        Write-Warning "Persist folder exists and is not empty!"
        Write-Host ""
        Write-Host "Migration pack restore requires a fresh installation."
        Write-Host "Please run script 54_Cleanup-PersistAll to purge existing persist data first."
        Write-Host ""
        Write-Host "Persist folder location: $persistDir"
        Write-Host ""
        exit 4
    }
}

# Get migration pack file
if (-not $File) {
    $MigrationDir = Join-Path $ProjectRoot 'backup\migration'
    # Resolve path to handle spaces correctly
    try {
        $MigrationDir = [System.IO.Path]::GetFullPath($MigrationDir)
    } catch {
        # If GetFullPath fails, use as-is (will fail with clearer error below)
    }
    if (-not (Test-Path $MigrationDir)) {
        Write-Error "Migration directory not found: $MigrationDir"
        Write-Host "        Please run script 88_Backup-MigrationPack first to create a migration pack."
        Write-Host ""
        exit 4
    }
    
    $selectedArchive = Get-ChildItem -Path $MigrationDir -Filter "backup_migration_*.zip" | 
                       Sort-Object LastWriteTime -Descending | 
                       Select-Object -First 1
    
    if (-not $selectedArchive) {
        Write-Error "No migration pack archives found in: $MigrationDir"
        Write-Host "        Please run script 88_Backup-MigrationPack first to create a migration pack."
        Write-Host ""
        exit 4
    }
    
    $File = $selectedArchive.FullName
} else {
    $File = (Resolve-Path $File).Path
}

Write-SubsectionHeader -Title 'Migration Pack Information'

$archiveInfo = Get-Item $File
$archiveSize = $archiveInfo.Length
$archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
Write-Host "[*] Archive: $($archiveInfo.Name)"
Write-Host "[*] Size: $archiveSizeMB MB"
Write-Host "[*] Date: $($archiveInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host ""

# Extract zip archive to temporary location
$tempExtractDir = Join-Path $env:TEMP "migration_restore_$(New-Guid)"
try {
    Write-Host "[*] Extracting archive to temporary location..."
    Expand-Archive -Path $File -DestinationPath $tempExtractDir -Force
    Write-Host "[OK] Archive extracted"
    Write-Host ""
} catch {
    Write-Error "Failed to extract archive: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

# Read apps.json from extracted location
$appsJsonPath = Join-Path $tempExtractDir 'apps.json'
# Resolve path to handle spaces correctly
try {
    $appsJsonPath = [System.IO.Path]::GetFullPath($appsJsonPath)
} catch {
    # If GetFullPath fails, use as-is (will fail with clearer error below)
}
if (-not (Test-Path $appsJsonPath)) {
    Write-Error "apps.json not found in migration pack"
    Write-Host ""
    # Cleanup
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 4
}

# Verify apps.json format
try {
    $json = Read-JsonFile -Path $appsJsonPath
    if (-not (Test-JsonFormat -JsonObject $json -RequiredProperties @('buckets', 'apps'))) {
        Write-Error "apps.json does not match expected format (missing buckets or apps arrays)"
        Write-Host ""
        # Cleanup
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 4
    }
} catch {
    Write-Error "Failed to parse apps.json: $($_.Exception.Message)"
    Write-Host ""
    # Cleanup
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 4
}

# Read config.json separately (if it exists in the archive)
$configJsonPath = Join-Path $tempExtractDir 'config.json'
# Resolve path to handle spaces correctly
try {
    $configJsonPath = [System.IO.Path]::GetFullPath($configJsonPath)
} catch {
    # If GetFullPath fails, use as-is (will fail with clearer error below)
}
$configToWrite = $null
$oldPrefix = $null
$newPrefix = $null

if (Test-Path $configJsonPath) {
    Write-Host "[*] Found config.json in migration pack"
    Write-Host ""
    try {
        $config = Read-JsonFile -Path $configJsonPath
        
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
            # No root_path, but config exists - keep as is but ensure paths are strings
            if ($config.PSObject.Properties.Name -contains 'root_path' -and $config.root_path) {
                $config.root_path = [string]$config.root_path
            }
            if ($config.PSObject.Properties.Name -contains 'global_path' -and $config.global_path) {
                $config.global_path = [string]$config.global_path
            }
            $configToWrite = $config
        }
    } catch {
        Write-Warning "Failed to read config.json: $($_.Exception.Message)"
        Write-Host "[*] Continuing without config.json restore"
        Write-Host ""
    }
} else {
    Write-Host "[*] No config.json found in migration pack (optional)"
    Write-Host ""
}

# Import apps from JSON file using existing 23_Import-Apps logic
Write-SubsectionHeader -Title 'Importing Apps and Config'

$ScriptDir = $PSScriptRoot
$exitCode = 0
try {
    & (Join-Path $ScriptDir '23_Import-Apps.ps1') -File $appsJsonPath -SuppressConfigMessage -SuppressStealthMessage
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq $null) { $exitCode = 0 }
} catch {
    Write-Error "Failed to import apps: $($_.Exception.Message)"
    $exitCode = 4
}

# Force output flush immediately after import completes
[Console]::Out.Flush()

if ($exitCode -ne 0) {
    Write-Host ""
    Write-Error "App import failed. Aborting migration pack restore."
    Write-Host ""
    # Cleanup
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit $exitCode
}

# Write config.json if it was extracted from the migration pack
if ($null -ne $configToWrite) {
    Write-Host ""
    Write-Host "[*] Writing config.json..."
    [Console]::Out.Flush()
    
    $targetConfigPath = Join-Path $ScoopRoot 'config.json'
    # Resolve path to handle spaces correctly
    try {
        $targetConfigPath = [System.IO.Path]::GetFullPath($targetConfigPath)
    } catch {
        # If GetFullPath fails, use as-is (will work with file operations)
    }
    try {
        # Convert to JSON with error handling
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
            }
        }
        
        if ($configJsonContent) {
            Write-Host "[*] Writing config.json to disk..."
            [Console]::Out.Flush()
            
            Write-TextFileUtf8NoBom -Path $targetConfigPath -Content $configJsonContent
            
            Write-Host "[OK] Restored config.json with updated paths"
            Write-Host ""
            [Console]::Out.Flush()
        }
    } catch {
        Write-Warning "Failed to write config.json: $($_.Exception.Message)"
        Write-Host ""
        [Console]::Out.Flush()
    }
}

Write-Host ""
Write-SectionHeader -Title 'Apps Import Complete' -NoTrailingBlankLine
Write-Host "[OK] Apps imported successfully"
Write-Host ""
Write-Host "Continuing with persist folder restoration..."
Write-Host ""

# Force output flush again
[Console]::Out.Flush()

# Restore Persist Folder
$extractedPersistDir = Join-Path $tempExtractDir 'persist'
if (Test-Path $extractedPersistDir) {
    Write-SubsectionHeader -Title 'Restoring Persist Folder'
    
    Write-Host "[*] Extracting persist folder..."
    Write-Host "[*] This may take a while depending on the size of persist data..."
    Write-Host ""
    
    # Force output flush
    [Console]::Out.Flush()
    
    # Use replace approach - delete existing persist folder, then copy new one
    # This ensures a clean restore without merging old and new data
    if (Test-Path $persistDir) {
        Write-Host "[*] Removing existing persist folder..."
        Write-Host ""
        try {
            Remove-Item -Path $persistDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Error "Failed to remove existing persist folder: $($_.Exception.Message)"
            Write-Host ""
            # Cleanup
            Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            exit 4
        }
    }
    
    # Create fresh directory and copy from archive
    Write-Host "[*] Copying persist folder from migration pack..."
    Write-Host "[*] Press Ctrl+C to cancel (may take a moment to respond)..."
    Write-Host ""
    
    try {
        New-Item -ItemType Directory -Force -Path $persistDir | Out-Null
        Copy-Item -Path "$extractedPersistDir\*" -Destination $persistDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Error "Failed to copy persist folder: $($_.Exception.Message)"
        Write-Host ""
        # Cleanup
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 4
    }
    
    Write-Host "[OK] Persist folder extracted"
    Write-Host ""
    
    # Path Replacement in Persist Files (Option A: replace during restore)
    # Validate prefixes are not null or empty before proceeding
    if (-not [string]::IsNullOrEmpty($oldPrefix) -and -not [string]::IsNullOrEmpty($newPrefix) -and $oldPrefix -ne $newPrefix) {
        Write-SubsectionHeader -Title 'Updating Paths in Persist Files'
        Write-Warning "The following path replacements will be performed. Please review them manually after restoration."
        Write-Host ""
        
        Write-Host "[*] Scanning persist folder for files to update..."
        Write-Host "[*] This may take a while if there are many files..."
        Write-Host ""
        
        $filesProcessed = 0
        $filesChanged = 0
        $filesSkipped = 0
        
        # Scan ALL files in persist folder (don't rely on file extensions)
        $allFiles = Get-ChildItem -Path $persistDir -Recurse -Force -File -ErrorAction SilentlyContinue
        
        if ($null -eq $allFiles) { $allFiles = @() }
        
        Write-Host "[*] Found $($allFiles.Count) file(s) to process"
        Write-Host "[*] Processing files..."
        Write-Host ""
        
        $totalFiles = $allFiles.Count
        $currentFile = 0
        
        foreach ($file in $allFiles) {
            $currentFile++
            if ($totalFiles -gt 10 -and ($currentFile % 10 -eq 0 -or $currentFile -eq $totalFiles)) {
                Write-Host "[*] Processing file $currentFile of $totalFiles..."
            }
            
            # Validate file object and paths
            if ($null -eq $file -or $null -eq $file.FullName -or $null -eq $persistDir) {
                $filesSkipped++
                continue
            }
            
            try {
                $relativePath = $file.FullName.Substring($persistDir.Length + 1)
            } catch {
                # If Substring fails, skip this file
                $filesSkipped++
                continue
            }
            
            try {
                # Optional optimization: Check first 1-2 KB for null bytes (binary detection)
                $fileStream = $null
                $isBinary = $false
                try {
                    $fileStream = [System.IO.File]::OpenRead($file.FullName)
                    $buffer = New-Object byte[] 2048
                    $bytesRead = $fileStream.Read($buffer, 0, 2048)
                    
                    # Check for null bytes (binary marker)
                    for ($i = 0; $i -lt $bytesRead; $i++) {
                        if ($buffer[$i] -eq 0) {
                            $isBinary = $true
                            break
                        }
                    }
                } catch {
                    # If we can't read the file stream, skip it
                    $filesSkipped++
                    continue
                } finally {
                    if ($fileStream) {
                        $fileStream.Close()
                    }
                }
                
                if ($isBinary) {
                    $filesSkipped++
                    continue
                }
                
                # Limit file size to prevent hanging on huge files (skip files > 10MB)
                $fileInfo = Get-Item -Path $file.FullName -ErrorAction Stop
                if ($fileInfo.Length -gt 10MB) {
                    $filesSkipped++
                    continue
                }
                
                # Try to read as text
                $content = $null
                try {
                    $content = Get-Content -Raw -Path $file.FullName -ErrorAction Stop
                    # Ensure content is a string (Get-Content -Raw should return string, but be defensive)
                    if ($null -eq $content) {
                        $content = ""
                    }
                } catch {
                    # Skip files that can't be read (locked, permissions, etc.)
                    $filesSkipped++
                    continue
                }
                
                # Check if file contains portable_scoop and content is not null/empty
                if ($null -ne $content -and $content -ne "" -and ($content -match '\\portable_scoop' -or $content -match '\\\\portable_scoop')) {
                    # Validate prefixes before calling Update-PathsInText
                    if ([string]::IsNullOrEmpty($oldPrefix) -or [string]::IsNullOrEmpty($newPrefix)) {
                        $filesSkipped++
                        continue
                    }
                    
                    # Replace paths
                    try {
                        $newContent = Update-PathsInText -Content $content -OldPrefix $oldPrefix -NewPrefix $newPrefix
                        
                        # Only write if content changed and newContent is not null
                        if ($null -ne $newContent -and $newContent -ne $content) {
                            Write-TextFileUtf8NoBom -Path $file.FullName -Content $newContent
                            $filesChanged++
                            
                            # Display path replacement
                            Write-Host "[PATH] File: $relativePath"
                            Write-Host "       Old: $oldPrefix\portable_scoop"
                            Write-Host "       New: $newPrefix\portable_scoop"
                            Write-Host ""
                        }
                    } catch {
                        # Skip files that fail path replacement
                        $filesSkipped++
                        Write-Warning "Failed to update paths in file: $relativePath - $($_.Exception.Message)"
                        continue
                    }
                }
                
                $filesProcessed++
            } catch {
                # Skip files that fail for any reason
                $filesSkipped++
                # Don't show warning for every skipped file to avoid spam
            }
        }
        
        Write-Host "[OK] Path replacement complete"
        Write-Host "[*] Files processed: $filesProcessed"
        Write-Host "[*] Files changed: $filesChanged"
        Write-Host "[*] Files skipped: $filesSkipped"
        Write-Host ""
    } else {
        Write-Host "[*] No path replacement needed (same prefix or no config found)"
        Write-Host ""
    }
} else {
    Write-Host "[*] No persist folder in migration pack"
    Write-Host ""
}

# Clean up temporary extraction location
try {
    Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Failed to clean up temporary directory: $tempExtractDir"
    Write-Host ""
}

Write-SectionHeader -Title '[OK] Migration pack restore complete!'

exit 0
