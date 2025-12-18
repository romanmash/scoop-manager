<#
.SYNOPSIS
Closes all running Scoop-installed apps

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ScoopRoot = $ctx.ScoopRoot
$ScoopEnvModule = Join-Path $ctx.ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Load RunningScoopApps module
$RunningAppsModulePath = Join-Path $ctx.ProjectRoot 'modules\RunningScoopApps.psm1'
Import-Module $RunningAppsModulePath -Force

Write-SectionHeader -Title 'CLOSING RUNNING SCOOP APPS'

# Check if Scoop exists (non-fatal for this script - graceful exit)
$ScoopShim = $ctx.ScoopShim
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim)) {
    Write-Host "[*] Nothing to close."
    Write-Host ""
    exit 0
}

$runningApps = Get-RunningScoopApps -ScoopRoot $ScoopRoot
Show-RunningScoopApps -RunningApps $runningApps
Write-Host ""

if (-not $runningApps -or $runningApps.Count -eq 0) {
    exit 0
}

# Prompt for confirmation
Write-Host -NoNewline "Close all running Scoop apps? (yN): "
$key = [Console]::ReadKey($true)
$confirm = $key.KeyChar
Write-Host $confirm
Write-Host ""

if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "[*] Operation cancelled."
    Write-Host ""
    exit 0
}

Write-SubsectionHeader -Title 'Closing Apps'

# Close the apps
$success = Close-RunningScoopApps -RunningApps $runningApps
Write-Host ""

if ($success) {
    Write-Host "[OK] All running Scoop apps closed successfully"
} else {
    Write-Host "[*] Some apps may not have closed successfully"
}

Write-Host ""

exit 0
