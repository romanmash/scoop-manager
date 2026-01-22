<#
.SYNOPSIS
Fixes persist links for predefined Scoop apps

.CMD
-
#>

[CmdletBinding()]
param(
    [string[]]$AppName
)

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

# Ensure console UI helpers are available (for standalone runs outside the menu host).
if (-not (Get-Command -Name Write-SectionHeader -ErrorAction SilentlyContinue)) {
    $ConsoleUiPath = Join-Path $ProjectRoot 'modules\ConsoleUi.psm1'
    if (Test-Path -LiteralPath $ConsoleUiPath) {
        Import-Module $ConsoleUiPath -Force -ErrorAction SilentlyContinue
    }
}

# Check if Scoop is installed - required for resolving app installs
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load persist links module
$PersistLinksPath = Join-Path $ProjectRoot 'modules\PersistLinks.psm1'
if (-not (Test-Path -LiteralPath $PersistLinksPath)) {
    Write-Warning "PersistLinks module not found at: $PersistLinksPath"
    exit 4
}
Import-Module $PersistLinksPath -Force

# Verify config exists
$PersistLinksConfig = Join-Path $ProjectRoot 'config\persist_links.json'
if (-not (Test-Path -LiteralPath $PersistLinksConfig)) {
    Write-Host "[*] No persist_links.json found at: $PersistLinksConfig"
    Write-Host ""
    exit 0
}

Write-SectionHeader -Title 'FIX PERSIST LINKS'

Invoke-PersistLinks -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot -AppName $AppName

exit 0
