<#
.SYNOPSIS
Removes orphaned persist data

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (automatically sets up stealth environment)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ScoopRoot = $ctx.ScoopRoot

# Load InstallationValidation module
$InstallationValidationPath = Join-Path $ctx.ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

$persistDir = Join-Path $ScoopRoot 'persist'
$appsDir    = Join-Path $ScoopRoot 'apps'

if (-not (Test-Path $persistDir)) {
    Write-Host "[*] No persist directory found."
    Write-Host ""
    exit 0
}

$installed = @()
if (Test-Path $appsDir) {
    $installed = Get-ChildItem -Path $appsDir -Directory | Select-Object -ExpandProperty Name
}

$orphans = Get-ChildItem -Path $persistDir -Directory | Where-Object { $_.Name -notin $installed } | Select-Object -ExpandProperty FullName

if (-not $orphans -or $orphans.Count -eq 0) {
    Write-Host "[*] No orphaned persist folders found."
    Write-Host ""
    exit 0
}

Write-SectionHeader -Title 'REMOVING ORPHANED PERSIST FOLDERS'

foreach ($o in $orphans) {
    Write-Host ("  - {0}" -f (Split-Path $o -Leaf))
}
Write-Host ""

foreach ($o in $orphans) {
    try {
        Remove-Item -LiteralPath $o -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $o"
    } catch {
        Write-Warning "Failed to remove ${o}: $($_.Exception.Message)"
    }
}
Write-Host ""
Write-Host "[OK] Orphaned persist cleanup complete."
Write-Host ""

exit 0
