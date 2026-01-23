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
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
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
    $null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('config', $key, $val) -Stream:$true
} elseif ($choice -eq '2') {
    $key = Read-Host "Enter key to remove"
    $null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('config', 'rm', $key) -Stream:$true
} else {
    Write-Host "[*] Exit."
}
Write-Host ""

exit 0
