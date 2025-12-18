<#
.SYNOPSIS
Opens project documentation in default application

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$ReadmePath = Join-Path $ProjectRoot 'README.md'

# Resolve path to handle spaces/hyphens safely
try {
    $PathTools = Join-Path $ProjectRoot 'modules\PathTools.psm1'
    if (Test-Path -LiteralPath $PathTools) {
        Import-Module $PathTools -Force -ErrorAction SilentlyContinue
    }
    if (Get-Command -Name Resolve-LiteralPathSafe -ErrorAction SilentlyContinue) {
        $ReadmePath = Resolve-LiteralPathSafe -Path $ReadmePath
    } else {
        $ReadmePath = [System.IO.Path]::GetFullPath($ReadmePath)
    }
} catch { }

Write-Host "[*] Opening project documentation..."
Write-Host ""

if (-not (Test-Path $ReadmePath)) {
    Write-Error "README.md not found at: $ReadmePath"
    Write-Host ""
    exit 4
}

try {
    # Open README.md with default application
    Start-Process $ReadmePath
    Write-Host "[OK] README.md opened in default application"
    Write-Host ""
    exit 0
} catch {
    Write-Error "Failed to open README.md: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}
