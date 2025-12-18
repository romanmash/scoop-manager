<#
.SYNOPSIS
Lists all installed apps

.CMD
scoop list
#>

$ErrorActionPreference = 'Stop'

# Standard bootstrap
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment -UpdateBuckets
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Check if Scoop is installed - required for listing apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load extended list module
$ModulePath = Join-Path $ProjectRoot 'modules\ExtendedAppList.psm1'
Import-Module $ModulePath -Force

# Load UpdatableApps module so held/pinned metadata is available to ExtendedAppList
$UpdatableAppsPath = Join-Path $ProjectRoot 'modules\UpdatableApps.psm1'
if (-not (Test-Path $UpdatableAppsPath)) {
    Write-Error "UpdatableApps module not found at: $UpdatableAppsPath"
    exit 4
}
Import-Module $UpdatableAppsPath -Force

Write-SectionHeader -Title 'LISTING INSTALLED APPS'
Write-SubsectionHeader -Title 'Currently Installed Apps'

# Use shared module to display extended list (status view – no update summary lines)
Show-ExtendedAppList -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim

exit 0
