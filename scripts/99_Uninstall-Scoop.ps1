<#
.SYNOPSIS
Completely removes Scoop incl. apps, data, and portable_scoop folder

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (automatically sets up stealth environment)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
# Skip shim validation for uninstall - shim may not exist if Scoop is already partially removed
$ctx = Initialize-ScriptEnvironment -SkipShimValidation -SkipLibPatch
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot

# Load RunningScoopApps module
$RunningAppsModulePath = Join-Path $ProjectRoot 'modules\RunningScoopApps.psm1'
Import-Module $RunningAppsModulePath -Force
# Load InstallationValidation and FileRemovalError modules
$InstallationValidationPath = Join-Path $ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force
$FileRemovalErrorPath = Join-Path $ProjectRoot 'modules\FileRemovalError.psm1'
Import-Module $FileRemovalErrorPath -Force
$FileRemovalModulePath = Join-Path $ProjectRoot 'modules\FileRemoval.psm1'
Import-Module $FileRemovalModulePath -Force

Write-SectionHeader -Title 'COMPLETE SCOOP REMOVAL'

# Check if Scoop folder exists (for uninstall, we check folder existence, not installation status)
# Even if Scoop appears broken, we should still try to remove the folder
$ScoopShim = $ctx.ScoopShim
if (-not (Test-Path $ScoopRoot)) {
    Write-Host "[*] Nothing to uninstall (folder does not exist)."
    Write-Host ""
    exit 0
}

Write-Host "This will completely remove Scoop installation at:"
Write-Host "  $ScoopRoot"
Write-Host ""
Write-Host "This includes:"
Write-Host "  - All installed apps"
Write-Host "  - All persist data"
Write-Host "  - All buckets"
Write-Host "  - Scoop itself"
Write-Host ""

Write-SubsectionHeader -Title 'Uninstalling Scoop'

Test-NoRunningApps -ScoopRoot $ScoopRoot
Write-Host ""

Write-SubsectionHeader -Title 'Removing portable_scoop Folder'

Write-Host "[*] Attempting to remove portable_scoop..."
$removed = Remove-DirectorySafe -Path $ScoopRoot -ShowHelp -ScoopRoot $ScoopRoot -ShowProgress
if (-not $removed) {
    Write-Host ""
    Write-Host "[*] Could not remove portable_scoop folder. Please close any open files or processes in the directory."
    Write-Host ""
    Write-FileRemovalErrorHelp -ScoopRoot $ScoopRoot
    exit 4
}
Write-Host "[OK] portable_scoop folder removed"
Write-Host ""

# Verify removal
if (Test-Path $ScoopRoot) {
    Write-Warning "portable_scoop folder still exists after removal attempt"
    Write-Host "[*] You may need to manually delete: $ScoopRoot"
    Write-Host ""
    exit 4
}

Write-SectionHeader -Title '[OK] Scoop completely uninstalled!'

exit 0
