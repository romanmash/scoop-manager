<#
.SYNOPSIS
Opens Scoop wiki in default browser

.CMD
-
#>

$ErrorActionPreference = 'Stop'

$WikiUrl = "https://github.com/ScoopInstaller/Scoop/wiki"

Write-Host "[*] Opening Scoop wiki..."
Write-Host ""

try {
    # Open wiki URL in default browser
    Start-Process $WikiUrl
    Write-Host "[OK] Scoop wiki opened in default browser"
    Write-Host ""
    exit 0
} catch {
    Write-Error "Failed to open Scoop wiki: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}
