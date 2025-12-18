<#
.SYNOPSIS
Persist folder backup operations

.DESCRIPTION
Provides functions for backing up the persist folder to ZIP archive.

.EXAMPLE
Import-Module "$PSScriptRoot\BackupPersist.psm1" -Force
$backupPath = Backup-PersistFolder -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -Timestamp $timestamp
#>

function Backup-PersistFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$Timestamp
    )
    
    # Load required modules
    $BackupArchivePath = Join-Path $PSScriptRoot 'BackupArchive.psm1'
    Import-Module $BackupArchivePath -Force
    $BackupConfigPath = Join-Path $PSScriptRoot 'BackupConfig.psm1'
    Import-Module $BackupConfigPath -Force
    
    $persistDir = Join-Path $ScoopRoot 'persist'
    
    if (-not (Test-Path $persistDir)) {
        return $null
    }
    
    # Create backup/persist directory
    $BackupDir = Join-Path $ProjectRoot 'backup\persist'
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    }
    
    # Generate timestamped filename
    $archiveName = "backup_persist_{0}.zip" -f $Timestamp
    $archivePath = Join-Path $BackupDir $archiveName
    
    # Get compression level from config
    $compressionLevel = Get-BackupCompression -ProjectRoot $ProjectRoot
    
    try {
        # Create archive using shared module
        $result = New-BackupArchive -SourcePath $persistDir -ArchivePath $archivePath -CompressionLevel $compressionLevel
        
        if ($result.FileCount -gt 0 -or $result.DirCount -gt 0) {
            return $archivePath
        }
        return $null
    } catch {
        Write-Warning "Failed to backup persist folder: $($_.Exception.Message)"
        return $null
    }
}

Export-ModuleMember -Function @(
    'Backup-PersistFolder'
)
