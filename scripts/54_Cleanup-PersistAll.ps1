<#
.SYNOPSIS
Purges all persist data (destructive)

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ctx.ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

Write-SectionHeader -Title 'PURGING ALL PERSIST DATA'

# Check if Scoop is installed - required for cleanup (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Remove the persist folder directly
# This is safer than uninstalling/reinstalling apps, as it preserves pin/current/hold states
$persistDir = Join-Path $ScoopRoot 'persist'
if (Test-Path $persistDir) {
    Write-Host "[*] Removing persist folder: $persistDir"
    try {
        Remove-Item -Path $persistDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Persist folder removed successfully."
    } catch {
        Write-Warning "Could not remove persist folder: $($_.Exception.Message)"
        Write-Host ""
        exit 4
    }
} else {
    Write-Host "[*] Persist folder does not exist: $persistDir"
    Write-Host "[*] Nothing to purge."
    Write-Host ""
}

Write-Warning "Run script 55_Reset-Apps.ps1 to recreate an empty persist folder and relink app data."
Write-Host ""

# Remove the workspace folder (contains temporary manifests and generated files)
Write-SubsectionHeader -Title 'Removing Workspace Folder'

$workspaceDir = Join-Path $ScoopRoot 'workspace'
if (Test-Path $workspaceDir) {
    try {
        Remove-Item -Path $workspaceDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed workspace folder."
        Write-Host ""
    } catch {
        Write-Warning "Could not remove workspace folder: $($_.Exception.Message)"
        Write-Host ""
    }
} else {
    Write-Host "[*] Workspace folder does not exist: $workspaceDir"
    Write-Host "[*] Nothing to remove."
    Write-Host ""
}

exit 0
