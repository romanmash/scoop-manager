<#
.SYNOPSIS
Centralized helper for robust directory removal.

.DESCRIPTION
Provides a reusable function that removes directories aggressively:
- Tries simple Remove-Item first
- If that fails, normalizes attributes recursively and retries
- Falls back to .NET Directory.Delete, robocopy mirror, then cmd rmdir
Used by uninstall and update scripts to handle locked/readonly files consistently.

.EXAMPLE
Import-Module "$PSScriptRoot\FileRemoval.psm1" -Force
$ok = Remove-DirectorySafe -Path $ScoopRoot -ShowHelp -ScoopRoot $ScoopRoot
#>

try {
    $processRunner = Join-Path $PSScriptRoot 'ProcessRunner.psm1'
    if (Test-Path -LiteralPath $processRunner) {
        Import-Module $processRunner -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

function Remove-DirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$ShowHelp,

        [Parameter(Mandatory = $false)]
        [string]$ScoopRoot,

        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $maxRetries = 3
    $removed    = $false

    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            if ($i -gt 1) {
                Start-Sleep -Seconds 2
            }

            if ($ShowProgress) {
                Write-Host "[*] Attempting to remove: $Path (try $i of $maxRetries)"
            }

            # Try simple removal first
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $Path)) {
                    $removed = $true
                    if ($ShowProgress) { Write-Host "[OK] Removed via simple removal." }
                    break
                } else {
                    throw "Path still exists after simple removal"
                }
            } catch {
                # Aggressive PowerShell-native method: normalize attributes then remove
                try {
                    if (Test-Path -LiteralPath $Path) {
                        if ($ShowProgress) { Write-Host "[*] Normalizing attributes recursively..." }
                        Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Attributes = 'Normal' } catch { }
                        }

                        if ($ShowProgress) { Write-Host "[*] Force removing folder..." }
                        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
                    }

                    if (-not (Test-Path -LiteralPath $Path)) {
                        $removed = $true
                        if ($ShowProgress) { Write-Host "[OK] Removed after attribute normalization." }
                        break
                    } else {
                        throw "Path still exists after aggressive removal"
                    }
                } catch {
                    # Fallback: .NET Directory.Delete (can be more aggressive)
                    try {
                        if (Test-Path -LiteralPath $Path) {
                            if ($ShowProgress) { Write-Host "[*] Trying .NET Directory.Delete..." }
                            [System.IO.Directory]::Delete($Path, $true)
                        }
                        if (-not (Test-Path -LiteralPath $Path)) {
                            $removed = $true
                            if ($ShowProgress) { Write-Host "[OK] Removed via .NET Directory.Delete." }
                            break
                        }
                    } catch {
                        # Additional fallbacks
                        if (-not $removed -and (Test-Path -LiteralPath $Path)) {
                            if ($ShowProgress) { Write-Host "[*] .NET method failed, trying robocopy mirror..." }
                            if (Remove-WithRobocopyMirror -Path $Path -ShowProgress:$ShowProgress) {
                                $removed = $true
                                break
                            }
                        }
                        if (-not $removed -and (Test-Path -LiteralPath $Path)) {
                            if ($ShowProgress) { Write-Host "[*] Robocopy failed, trying cmd rmdir..." }
                            if (Remove-WithCmdRmdir -Path $Path -ShowProgress:$ShowProgress) {
                                $removed = $true
                                break
                            }
                        }
                        if (-not $removed -and $i -eq $maxRetries) { throw }
                    }
                }
            }
        } catch {
            if ($i -eq $maxRetries) {
                Write-Error "Failed to remove path: $Path. $($_.Exception.Message)"
            }
        }
    }

    if (-not $removed -and $ShowHelp -and $ScoopRoot) {
        $fileRemovalErrorPath = Join-Path $PSScriptRoot 'FileRemovalError.psm1'
        if (Test-Path $fileRemovalErrorPath) {
            try {
                Import-Module $fileRemovalErrorPath -Force -ErrorAction SilentlyContinue
                if (Get-Command Write-FileRemovalErrorHelp -ErrorAction SilentlyContinue) {
                    Write-FileRemovalErrorHelp -ScoopRoot $ScoopRoot
                }
            } catch { }
        }
    }

    return $removed
}

Export-ModuleMember -Function 'Remove-DirectorySafe'

function Remove-WithRobocopyMirror {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$ShowProgress
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $emptyDir = Join-Path $env:TEMP "scoop_empty_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $emptyDir -Force -ErrorAction Stop | Out-Null
        Assert-ExternalCommandRunner -Caller 'Remove-WithRobocopyMirror'
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $null = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath 'robocopy' -ArgumentList @($emptyDir, $Path, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/R:0', '/W:0') -Stream:$false -NoHostOutput
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        $ok = -not (Test-Path -LiteralPath $Path)
        if ($ok -and $ShowProgress) { Write-Host "[OK] Removed via robocopy mirror." }
        return $ok
    } catch {
        return $false
    } finally {
        if (Test-Path -LiteralPath $emptyDir) {
            Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-WithCmdRmdir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$ShowProgress
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        Assert-ExternalCommandRunner -Caller 'Remove-WithCmdRmdir'
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $null = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath 'cmd.exe' -ArgumentList @('/c', "rmdir /s /q `"$Path`"") -Stream:$false -NoHostOutput
        $ok = -not (Test-Path -LiteralPath $Path)
        if ($ok -and $ShowProgress) { Write-Host "[OK] Removed via cmd rmdir." }
        return $ok
    } catch {
        return $false
    }
}
