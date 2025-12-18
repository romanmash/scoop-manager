<#
.SYNOPSIS
Edits Scoop configuration (set or remove values)

.CMD
scoop config
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

# Check if Scoop is installed - required for editing config (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

Write-SectionHeader -Title 'CONFIGURATION EDITOR'
Write-Host "1) Set value"
Write-Host "2) Remove value"
Write-Host "x) Exit"
$choice = Read-Host "Select"
if ($choice -eq '1') {
    $key = Read-Host "Enter key (e.g., proxy, aria2-enabled)"
    $val = Read-Host "Enter value"
    # Suppress error action for config command as it may return non-zero exit code
    $ErrorActionPreference = 'Continue'
    & $ScoopShim config $key $val 2>&1 | Out-Host
    $ErrorActionPreference = 'Stop'
} elseif ($choice -eq '2') {
    $key = Read-Host "Enter key to remove"
    # Suppress error action for config command as it may return non-zero exit code
    $ErrorActionPreference = 'Continue'
    & $ScoopShim config rm $key 2>&1 | Out-Host
    $ErrorActionPreference = 'Stop'
} else {
    Write-Host "[*] Exit."
}
Write-Host ""

exit 0
