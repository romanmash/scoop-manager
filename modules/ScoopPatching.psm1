<#
.SYNOPSIS
Module for patching Scoop's core library files to prevent registry writes.

.DESCRIPTION
This module provides functions to patch Scoop's core lib files (system.ps1, core.ps1,
decompress.ps1, manifest.ps1) to replace registry-writing behaviours with process-only
implementations and to add small behaviour fixes (e.g., manifest handling).

Patches are idempotent and automatically re-applied after Scoop updates. If a lib
file is already patched but the prepared patch file has changed (for example after
updating this project), the patch is updated in-place to the latest version.
#>

function Get-ScoopLibPath {
    <#
    .SYNOPSIS
    Gets the path to Scoop's lib/system.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot
    )

    $libPath = Join-Path $ScoopRoot 'apps\scoop\current\lib\system.ps1'
    if (-not (Test-Path $libPath)) {
        return $null
    }
    return $libPath
}

function Get-ScoopCorePath {
    <#
    .SYNOPSIS
    Gets the path to Scoop's lib/core.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot
    )

    $corePath = Join-Path $ScoopRoot 'apps\scoop\current\lib\core.ps1'
    if (-not (Test-Path $corePath)) {
        return $null
    }
    return $corePath
}

function Get-ScoopManifestPath {
    <#
    .SYNOPSIS
    Gets the path to Scoop's lib/manifest.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot
    )

    $manifestPath = Join-Path $ScoopRoot 'apps\scoop\current\lib\manifest.ps1'
    if (-not (Test-Path $manifestPath)) {
        return $null
    }
    return $manifestPath
}

function Get-ScoopUpdatePath {
    <#
    .SYNOPSIS
    Gets the path to Scoop's libexec/scoop-update.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot
    )

    $updatePath = Join-Path $ScoopRoot 'apps\scoop\current\libexec\scoop-update.ps1'
    if (-not (Test-Path $updatePath)) {
        return $null
    }
    return $updatePath
}

function Get-ScoopDecompressPath {
    <#
    .SYNOPSIS
    Gets the path to Scoop's lib/decompress.ps1 file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot
    )

    $decompressPath = Join-Path $ScoopRoot 'apps\scoop\current\lib\decompress.ps1'
    if (-not (Test-Path $decompressPath)) {
        return $null
    }
    return $decompressPath
}

function Update-ScoopLibPatches {
    <#
    .SYNOPSIS
    Updates Scoop's lib files by comparing with _orig files and copying patched versions.

    .DESCRIPTION
    Compares files in apps/scoop/current/lib/ with patch/current/lib/*_orig.ps1 files using MD5 hash comparison.
    - If the installed lib file looks patched (first line contains a PATCHED marker), its hash is compared to the
      current patch file. If hashes differ, the patch is updated in-place to the latest version.
    - If the installed lib file hash matches the original *_orig.ps1 file, the corresponding patched file from
      patch/current/lib/ is copied over.
    - Any other mismatches (file contents that are neither original nor recognised patched form) are reported and
      cause a non-zero exit so the situation can be reviewed manually.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    Write-Host "[*] Updating Scoop lib patches..."

    # Define files to patch
    $filesToPatch = @(
        @{ Name = 'system.ps1';     BaseName = 'system';     GetPath = { Get-ScoopLibPath      -ScoopRoot $ScoopRoot } },
        @{ Name = 'core.ps1';       BaseName = 'core';       GetPath = { Get-ScoopCorePath     -ScoopRoot $ScoopRoot } },
        @{ Name = 'decompress.ps1'; BaseName = 'decompress'; GetPath = { Get-ScoopDecompressPath -ScoopRoot $ScoopRoot } },
        @{ Name = 'manifest.ps1';   BaseName = 'manifest';   GetPath = { Get-ScoopManifestPath -ScoopRoot $ScoopRoot } }
    )

    $mismatches = @()

    foreach ($fileInfo in $filesToPatch) {
        $fileName     = $fileInfo.Name
        $baseName     = $fileInfo.BaseName
        $installedPath = & $fileInfo.GetPath

        if (-not $installedPath -or -not (Test-Path $installedPath)) {
            # During initial installation, lib files might not exist yet - this is expected.
            # Only show warning if Scoop appears to be installed.
            $scoopAppPath = Join-Path $ScoopRoot 'apps\scoop'
            if (Test-Path $scoopAppPath) {
                Write-Warning "Scoop lib/$fileName not found at: $installedPath. Skipping patch for $fileName (file not found)."
            }
            continue
        }

        # Get paths to _orig and patched files (use baseName to avoid double .ps1 extension)
        $origPath    = Join-Path $ProjectRoot "patch\current\lib\${baseName}_orig.ps1"
        $patchedPath = Join-Path $ProjectRoot "patch\current\lib\$fileName"

        # Resolve paths to handle spaces
        try {
            $origPath    = [System.IO.Path]::GetFullPath($origPath)
            $patchedPath = [System.IO.Path]::GetFullPath($patchedPath)
        } catch {
            # If GetFullPath fails, use as-is
        }

        if (-not (Test-Path $origPath)) {
            Write-Warning "Original file not found: $origPath. Skipping patch for $fileName."
            continue
        }
        if (-not (Test-Path $patchedPath)) {
            Write-Warning "Patched file not found: $patchedPath. Skipping patch for $fileName."
            continue
        }

        # If file looks patched, compare its hash with the current patched file.
        # If hashes differ, assume an older patch and update to the latest patch file.
        try {
            $firstLine = Get-Content -Path $installedPath -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine -and ($firstLine -match 'patched')) {
                $installedPatchedHash = (Get-FileHash -Path $installedPath -Algorithm MD5).Hash
                $patchFileHash        = (Get-FileHash -Path $patchedPath -Algorithm MD5).Hash

                if ($installedPatchedHash -eq $patchFileHash) {
                    Write-Host "[*] lib/$fileName is already patched with latest patch file, skipping"
                    continue
                } else {
                    Write-Host "[*] lib/$fileName is patched but differs from current patch file, updating patch..."
                    Copy-Item -Path $patchedPath -Destination $installedPath -Force
                    Write-Host "[OK] Updated patch for lib/$fileName"
                    continue
                }
            }
        } catch {
            # If we can't read or hash the file, fall through to original comparison logic.
        }

        # Compare hashes with original (only for files that are not already patched)
        try {
            Write-Host "[*] Comparing files for lib/$fileName..."
            Write-Host "    $installedPath"
            Write-Host "    $origPath"

            $installedHash = (Get-FileHash -Path $installedPath -Algorithm MD5).Hash
            $origHash      = (Get-FileHash -Path $origPath      -Algorithm MD5).Hash

            if ($installedHash -eq $origHash) {
                # Files match original - copy patched version.
                Copy-Item -Path $patchedPath -Destination $installedPath -Force
                Write-Host "[OK] Patched lib/$fileName"
            } else {
                # Files don't match original and aren't recognised as current patch.
                $mismatches += @{
                    File          = $fileName
                    InstalledPath = $installedPath
                    InstalledHash = $installedHash
                    OrigPath      = $origPath
                    OrigHash      = $origHash
                }
            }
        } catch {
            Write-Warning "Failed to compare or patch $fileName : $($_.Exception.Message)"
            $mismatches += @{
                File  = $fileName
                Error = $_.Exception.Message
            }
        }
    }

    # If there are mismatches or errors, show warnings and exit
    if ($mismatches.Count -gt 0) {
        Write-Host ""
        Write-Warning "Scoop lib patch validation failed."
        foreach ($mismatch in $mismatches) {
            if ($mismatch.Error) {
                Write-Host "  - $($mismatch.File): $($mismatch.Error)"
            } else {
                Write-Host "  - $($mismatch.File) - Installed hash: $($mismatch.InstalledHash), Expected (orig) hash: $($mismatch.OrigHash), File: $($mismatch.InstalledPath)"
            }
        }
        Write-Host ""
        Write-Warning "Possible causes:"
        Write-Host "  - Scoop core lib files have been updated, but *_orig.ps1 references were not refreshed."
        Write-Host "  - Patched lib files in portable_scoop no longer match the prepared patches in install_scoop."
        Write-Host "  - Patched files in patch/current/lib/*.ps1 were changed without updating originals and the installed files."
        Write-Host ""
        exit 4
    }

    Write-Host "[OK] All Scoop lib patches applied successfully"
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Get-ScoopLibPath'
    'Get-ScoopCorePath'
    'Get-ScoopUpdatePath'
    'Get-ScoopDecompressPath'
    'Get-ScoopManifestPath'
    'Update-ScoopLibPatches'
)

