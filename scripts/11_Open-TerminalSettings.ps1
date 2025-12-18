<#
.SYNOPSIS
Opens Windows settings for the default terminal application

.CMD
-
#>

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "[*] Opening Windows Settings (For developers -> Terminal)..."
Write-Host ""
Write-Host "Set:"
Write-Host "  Default terminal application = Windows Console Host"
Write-Host ""
Write-Host "This makes Scoop Manager run in the classic console, where the window icon can be set."
Write-Host ""

try {
    Start-Process "ms-settings:developers"
} catch {
    Write-Warning "Failed to open settings automatically. Open Settings and search for: Default terminal application"
}

