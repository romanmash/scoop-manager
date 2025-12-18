<#
.SYNOPSIS
Opens a window for interactive Scoop session

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module (automatically sets up stealth environment)
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim

# Load InstallationValidation module
$InstallationValidationPath = Join-Path $ctx.ProjectRoot 'modules\InstallationValidation.psm1'
Import-Module $InstallationValidationPath -Force

Write-SectionHeader -Title 'OPENING INTERACTIVE SCOOP SESSION'

# Verify Scoop is installed
Test-ScoopInstallation -ScoopRoot $ScoopRoot

Write-Host "[*] Opening interactive Scoop session..."
Write-Host "[*] Scoop Root: $ScoopRoot"
Write-Host "[*] Scoop Shim: $ScoopShim"
Write-Host ""

try {
    # Create a temporary batch file for initialization
    $tempBatch = Join-Path $env:TEMP "scoop_interactive_$(Get-Random).cmd"
    
    # Create batch file content with environment setup and welcome message
    # Use regular scoop command
    $scoopCmd = "scoop"
    
    $batchContent = @"
@echo off
title Scoop Interactive Session
color 0A

REM Set environment variables for Scoop (from stealth process environment)
set "SCOOP=$($env:SCOOP)"
set "SCOOP_CACHE=$($env:SCOOP_CACHE)"
set "SCOOP_GLOBAL=$($env:SCOOP_GLOBAL)"
set "XDG_CONFIG_HOME=$($env:XDG_CONFIG_HOME)"
set "PATH=$($env:PATH)"

echo.
echo =========================================
echo   SCOOP INTERACTIVE SESSION
echo =========================================
echo.
echo You can now run Scoop commands interactively.
echo Use: $scoopCmd <command>
echo Example: $scoopCmd bucket list
echo Type "$scoopCmd help" for available commands.
echo Type "exit" to close this window.
echo.
echo NOTE: If you run "$scoopCmd update *" and Scoop itself gets updated,
echo       the file-based patches will be automatically re-applied when you
echo       run any Scoop Manager script next time.
echo.
echo -----------------------------------------
echo.

cd /d "%SCOOP%"

cmd /k
"@
    
    # Write batch file
    $batchContent | Set-Content -Path $tempBatch -Encoding ASCII
    
    # Use Start-Process to open a new window (default behavior creates new window)
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", "`"$tempBatch`"" -WorkingDirectory $ScoopRoot | Out-Null
    
    # Clean up temp batch file after a short delay (process has started)
    Start-Sleep -Milliseconds 500
    if (Test-Path $tempBatch) {
        Remove-Item -Path $tempBatch -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "[OK] Interactive Scoop session opened in new CMD window."
    Write-Host ""
    exit 0
} catch {
    Write-Error "Failed to open interactive session: $($_.Exception.Message)"
    Write-Host ""
    # Clean up temp batch file on error
    if (Test-Path $tempBatch) {
        Remove-Item -Path $tempBatch -Force -ErrorAction SilentlyContinue
    }
    exit 4
}
