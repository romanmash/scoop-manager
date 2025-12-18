<#
.SYNOPSIS
Downloads and validates Scoop installer

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$PatchDir = Join-Path $ProjectRoot 'patch'
$OrigPath = Join-Path $PatchDir 'install_orig.ps1'

Write-Host "[*] Ensuring patch folder exists..."
New-Item -ItemType Directory -Force -Path $PatchDir | Out-Null
Write-Host ""

$installerUrl = 'https://get.scoop.sh'
Write-Host "[*] Downloading Scoop installer from: $installerUrl"
Write-Host "[*] (You can also manually download from: $installerUrl)"
$remote = Invoke-RestMethod -Uri $installerUrl
Write-Host ""

# Use hash-based comparison for file verification
if (Test-Path $OrigPath) {
    # Save remote content to temp file for hash comparison
    $tempRemote = Join-Path $env:TEMP "install_remote_$(New-Guid).ps1"
    try {
        Set-Content -Path $tempRemote -Value $remote -NoNewline
        Write-Host "[*] Comparing files..."
        Write-Host "    Remote installer (downloaded)"
        Write-Host "    $OrigPath"
        $remoteHash = (Get-FileHash -Path $tempRemote -Algorithm MD5).Hash
        $localHash = (Get-FileHash -Path $OrigPath -Algorithm MD5).Hash
        
        Remove-Item -Path $tempRemote -Force -ErrorAction SilentlyContinue
        
        if ($remoteHash -eq $localHash) {
            Write-Host "[OK] Remote installer is identical to local install_orig.ps1. No change needed."
            Write-Host ""
            exit 0
        } else {
            Write-Warning "Remote installer differs from existing install_orig.ps1! Not overwriting. Please review manually if update is needed. Download URL: $installerUrl"
            Write-Host ""
            exit 2
        }
    } catch {
        if (Test-Path $tempRemote) {
            Remove-Item -Path $tempRemote -Force -ErrorAction SilentlyContinue
        }
        Write-Error "Failed to compare installer files: $($_.Exception.Message)"
        exit 2
    }
} else {
    # Save canonical text copy
    Set-Content -Path $OrigPath -Value $remote -NoNewline
    Write-Host "[OK] Saved installer to: $OrigPath"
    Write-Host "[*] Download URL: $installerUrl"
    Write-Host ""
    exit 0
}
