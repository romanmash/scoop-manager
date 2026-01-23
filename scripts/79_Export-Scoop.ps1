<#
.SYNOPSIS
Exports canonical Scoop JSON for manual import

.CMD
scoop export
scoop list
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Check if Scoop is installed - required for exporting (centralized check)
$ScoopRoot = $ctx.ScoopRoot
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Load shared modules
$TimestampPath = Join-Path $ProjectRoot 'modules\Timestamp.psm1'
Import-Module $TimestampPath -Force
$EnsureConfigPath = Join-Path $ProjectRoot 'modules\ConfigDirectory.psm1'
Import-Module $EnsureConfigPath -Force

# Output folder + timestamped filenames
$OutDir = New-ConfigDirectory -ProjectRoot $ProjectRoot -Subdirectory "scoop"
$stamp = Get-Timestamp
$exportJson = Join-Path $OutDir ("export_scoop_{0}.json" -f $stamp)

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host "[*] Exporting to: $OutDir"
Write-Host ""

Write-SectionHeader -Title 'EXPORTING (CANONICAL FORMAT)'

# Show what's being exported
Write-SubsectionHeader -Title 'Current Apps'

$null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$true

Write-Host ""

Write-SubsectionHeader -Title 'Running Export'
$exportCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('export') -Stream:$false -NoHostOutput
Write-TextFileUtf8NoBom -Path $exportJson -Content $exportCmd.Output
Write-Host "[OK] Wrote: $exportJson"
Write-Host ""

Write-SectionHeader -Title '[OK] Export complete!'
Write-Host "To import this file:"
Write-Host "  Method 1: scoop import $exportJson"
Write-Host "  Method 2: Run script 29_Import-Scoop"
Write-Host ""

exit 0
