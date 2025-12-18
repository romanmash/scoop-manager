<#
.SYNOPSIS
Restores persist folder from backup archive

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

# Load InstallationValidation module
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'RESTORE PERSIST DATA'

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

# Check persist folder
$persistDir = Join-Path $ScoopRoot 'persist'

if (Test-Path $persistDir) {
    # Check if persist folder is not empty
    $persistItems = Get-ChildItem -Path $persistDir -Force -ErrorAction SilentlyContinue
    if ($persistItems -and $persistItems.Count -gt 0) {
        Write-Warning "Persist folder is not empty!"
        Write-Host ""
        Write-Host "The persist folder contains data that would be overwritten."
        Write-Host "Please run script 54_Cleanup-PersistAll to purge existing persist data first."
        Write-Host ""
        Write-Host "Persist folder location: $persistDir"
        Write-Host ""
        exit 4
    } else {
        # Persist folder is empty - remove it so we can extract to parent
        Write-Host "[*] Persist folder is empty, removing it..."
        Remove-Item -Path $persistDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ""
    }
}

# Get backup directory
$BackupDir = Join-Path $ProjectRoot 'backup\persist'

if (-not (Test-Path $BackupDir)) {
    Write-Error "Backup directory not found: $BackupDir"
    Write-Host "        Please run script 81_Backup-Persist first to create a backup."
    Write-Host ""
    exit 4
}

# Find latest backup archive
$selectedArchive = Get-ChildItem -Path $BackupDir -Filter "backup_persist_*.zip" | 
                   Sort-Object LastWriteTime -Descending | 
                   Select-Object -First 1

if (-not $selectedArchive) {
    Write-Error "No backup archives found in: $BackupDir"
    Write-Host "        Please run script 81_Backup-Persist first to create a backup."
    Write-Host ""
    exit 4
}

Write-SubsectionHeader -Title 'Restoring Persist Data'

$archiveSize = $selectedArchive.Length
$archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
Write-Host "[*] Latest archive: $($selectedArchive.Name)"
Write-Host "[*] Size: $archiveSizeMB MB"
Write-Host "[*] Date: $($selectedArchive.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "[*] Extracting to: $ScoopRoot (archive contains persist folder)"
Write-Host ""

# Extract archive to parent folder (ScoopRoot) - archive contains "persist" folder
try {
    Write-Host "[*] Extracting archive..."
    
    # Use Expand-Archive cmdlet (PowerShell native, handles overwrite with -Force)
    # Extract to ScoopRoot parent - archive contains "persist" folder which will be created
    Expand-Archive -Path $selectedArchive.FullName -DestinationPath $ScoopRoot -Force
    
    Write-Host "[OK] Archive extracted successfully"
    Write-Host ""
    
    # Count extracted items
    $extractedItems = Get-ChildItem -Path $persistDir -Recurse -Force -ErrorAction SilentlyContinue
    $fileCount = ($extractedItems | Where-Object { -not $_.PSIsContainer }).Count
    $dirCount = ($extractedItems | Where-Object { $_.PSIsContainer }).Count
    
    Write-Host "[OK] Restored $fileCount files and $dirCount directories"
    Write-Host ""
} catch {
    Write-Error "Failed to extract archive: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

Write-SectionHeader -Title '[OK] Restore complete!'

exit 0
