<#
.SYNOPSIS
Creates a backup of persist folder and exports apps configuration

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

# Load shared modules
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$BackupConfigPath = Join-Path $ProjectRoot 'modules\BackupConfig.psm1'
Import-Module $BackupConfigPath -Force
$BackupPersistPath = Join-Path $ProjectRoot 'modules\BackupPersist.psm1'
Import-Module $BackupPersistPath -Force
$ExportAppsPath = Join-Path $ProjectRoot 'modules\ExportApps.psm1'
Import-Module $ExportAppsPath -Force
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'BACKUP PERSIST DATA AND APPS'

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

# Check if persist folder exists
$persistDir = Join-Path $ScoopRoot 'persist'
if (-not (Test-Path $persistDir)) {
    Write-Host "[*] No persist directory found at: $persistDir"
    Write-Host "[*] Will still export apps configuration."
    Write-Host ""
}

# Show compression configuration info
Show-BackupCompressionInfo -ProjectRoot $ProjectRoot

Write-SubsectionHeader -Title 'Creating Backup'

# Generate timestamp
$timestamp = Get-Timestamp

# Backup persist folder
$persistBackupPath = Backup-PersistFolder -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -Timestamp $timestamp
if ($persistBackupPath) {
    $archiveSize = (Get-Item $persistBackupPath).Length
    $archiveSizeMB = [math]::Round($archiveSize / 1MB, 2)
    Write-Host "[OK] Persist backup created: $persistBackupPath ($archiveSizeMB MB)"
} else {
    Write-Host "[*] No persist folder to backup"
}

# Export apps configuration
$appsExportPath = Export-AppsConfiguration -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -Timestamp $timestamp
if ($appsExportPath) {
    Write-Host "[OK] Apps export created: $appsExportPath"
} else {
    Write-Host "[*] No apps to export"
}

Write-Host ""

if (-not $persistBackupPath -and -not $appsExportPath) {
    Write-Error "Backup failed"
    Write-Host ""
    exit 4
}

Write-SectionHeader -Title '[OK] Backup complete!'

exit 0
