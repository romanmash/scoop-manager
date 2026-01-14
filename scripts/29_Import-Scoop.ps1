<#
.SYNOPSIS
Imports apps from canonical Scoop JSON export

.CMD
scoop import
#>

[CmdletBinding()]
param(
    [string]$File
)

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Load bootstrap module
$BootstrapPath = Join-Path $ProjectRoot 'modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Load shared modules
$FindLatestPath = Join-Path $ProjectRoot 'modules\LatestExportFile.psm1'
Import-Module $FindLatestPath -Force
$BeforeAfterPath = Join-Path $ProjectRoot 'modules\BeforeAfterState.psm1'
Import-Module $BeforeAfterPath -Force

# Load fresh installation check module
$TestFreshPath = Join-Path $ProjectRoot 'modules\FreshInstallation.psm1'
Import-Module $TestFreshPath -Force

# Load VirusTotal integration (best-effort)
$vtSettings = $null
$VirusTotalInitPath = Join-Path $ProjectRoot 'modules\VirusTotalInit.psm1'
if (Test-Path -LiteralPath $VirusTotalInitPath) {
    Import-Module $VirusTotalInitPath -Force -ErrorAction SilentlyContinue
    if (Get-Command -Name Initialize-VirusTotalIntegration -ErrorAction SilentlyContinue) {
        $vtSettings = Initialize-VirusTotalIntegration -ProjectRoot $ProjectRoot
    }
}

# Load persist links module (optional)
$PersistLinksPath = Join-Path $ProjectRoot 'modules\PersistLinks.psm1'
if (Test-Path -LiteralPath $PersistLinksPath) {
    Import-Module $PersistLinksPath -Force
}

Write-SectionHeader -Title 'IMPORTING (CANONICAL FORMAT)'

# Pick default export file if none specified
if (-not $File) {
    $ConfigDir = Join-Path $ProjectRoot 'config\scoop'
    try {
        $File = Find-LatestExportFile -ConfigDir $ConfigDir -Pattern "export_scoop_*.json" -ErrorMessage "No export_scoop_*.json found in: $ConfigDir`n        Run script 79_Export-Scoop to create a canonical export first."
    } catch {
        exit 4
    }
}

$File = (Resolve-Path $File).Path

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host "[*] Importing from: $File"
Write-Host ""

# Check if Scoop is installed - required for importing apps (centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
    exit 4
}

# Check if installation is fresh (no apps installed except scoop)
$isFresh = Test-FreshInstallation -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim
if (-not $isFresh) {
    # Apps are already installed - exit with code 4
    exit 4
}

Write-SubsectionHeader -Title 'Running Import'

# Optional VirusTotal pre-import checks (hash-only, per app) when enabled
if ($vtSettings -and $vtSettings.EnabledOnInstall) {
    try {
        $json = Get-Content -Raw -Path $File | ConvertFrom-Json
        if ($json.apps) {
            $appsToCheck = @()
            foreach ($entry in $json.apps) {
                if ($entry -is [string] -and $entry.Trim().Length -gt 0) {
                    $appsToCheck += $entry.Trim()
                }
            }
            $appsToCheck = $appsToCheck | Sort-Object -Unique

            if ($appsToCheck.Count -gt 0) {
                Write-Host "[*] Running VirusTotal checks for apps in import file..."
                Write-Host ""

                foreach ($app in $appsToCheck) {
                    $vtCheck = Invoke-VirusTotalCheckForApp -AppName $app -ScoopShim $ScoopShim -Settings $vtSettings -Mode 'Install'
                    if ($vtCheck.Status -eq 'Risky') {
                        $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $vtCheck
                        if ($decision -eq 'Abort') {
                            Write-Warning "Aborting canonical import due to VirusTotal detections."
                            Write-Host ""
                            exit 4
                        } elseif ($decision -eq 'Skip') {
                            # For now we don't manipulate the import list; warn and continue.
                            Write-Warning "Skipping app '$app' for VirusTotal purposes, but canonical scoop import will still include it."
                            Write-Host "[*] To fully skip this app, remove it manually from the export before importing."
                            Write-Host ""
                        }
                    } elseif ($vtCheck.Status -eq 'Error') {
                        Write-Warning "VirusTotal check encountered an error for app '$app'. Continuing import."
                        Write-Host ""
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to parse canonical export JSON for VirusTotal checks: $($_.Exception.Message)"
        Write-Host ""
    }
}

Write-Host "[*] Running: scoop import"
# Suppress error action for import command as it may return non-zero exit code
$ErrorActionPreference = 'Continue'
& $ScoopShim import $File 2>&1 | Out-Host
$ErrorActionPreference = 'Stop'
Write-Host ""

Write-SectionHeader -Title '[OK] Import completed!'

if (Get-Command -Name Invoke-PersistLinks -ErrorAction SilentlyContinue) {
    Invoke-PersistLinks -ProjectRoot $ProjectRoot -ScoopRoot $ScoopRoot
}

# Show final state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter

exit 0
