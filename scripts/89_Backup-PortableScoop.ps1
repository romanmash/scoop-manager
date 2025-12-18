<#
.SYNOPSIS
Creates a full backup archive of the portable_scoop folder

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (automatically sets up stealth environment)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot

# Load shared modules
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$BackupConfigPath = Join-Path $ProjectRoot 'modules\BackupConfig.psm1'
Import-Module $BackupConfigPath -Force
$BackupArchivePath = Join-Path $ProjectRoot 'modules\BackupArchive.psm1'
Import-Module $BackupArchivePath -Force
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'BACKUP PORTABLE SCOOP'

# Verify portable_scoop exists
Test-ScoopInstallation -ScoopRoot $ScoopRoot

# Create backup/full directory
$BackupDir = Join-Path $ProjectRoot 'backup\full'
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Write-Host "[*] Created backup directory: $BackupDir"
    Write-Host ""
}

# Generate timestamped filename
$stamp = Get-Timestamp
$archiveName = "backup_full_{0}.zip" -f $stamp
$archivePath = Join-Path $BackupDir $archiveName

Write-Host "[*] Source: $ScoopRoot"
Write-Host "[*] Archive: $archivePath"
Write-Host ""

# Check if archive already exists
if (Test-Path $archivePath) {
    Write-Error "Archive already exists: $archivePath"
    Write-Host ""
    exit 4
}

# Show compression configuration info
Show-BackupCompressionInfo -ProjectRoot $ProjectRoot

Write-SubsectionHeader -Title 'Creating Archive'

# Get compression level from config
$compressionLevel = Get-BackupCompression -ProjectRoot $ProjectRoot

try {
    # Create archive using shared module
    $result = New-BackupArchive -SourcePath $ScoopRoot -ArchivePath $archivePath -CompressionLevel $compressionLevel
    
    if ($result.FileCount -eq 0 -and $result.DirCount -eq 0) {
        exit 0
    }
    
    Write-Host "[*] Archived $($result.FileCount) files and $($result.DirCount) directories (including hidden items)"
    Write-Host ""
    
    # Get archive size
    $archiveSize = (Get-Item $archivePath).Length
    $archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
    
    Write-Host "[OK] Archive created successfully"
    Write-Host "[OK] Size: $archiveSizeMB MB"
    Write-Host "[OK] Location: $archivePath"
    Write-Host ""
} catch {
    Write-Error "Failed to create archive: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

Write-SectionHeader -Title '[OK] Backup complete!'

exit 0
