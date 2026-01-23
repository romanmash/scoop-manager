<#
.SYNOPSIS
Bootstrap module that initializes common Scoop environment variables

.DESCRIPTION
One-stop module that loads all common initialization:
- Sets up stealth portable Scoop environment (process-level env vars)
- Resolves paths (ScriptDir, ProjectRoot, ScoopRoot)
- Gets Scoop shim path
- Optionally updates bucket metadata

This module sets global variables that other modules can use.
All scripts using this module automatically get stealth environment (process-level env vars only).

.PARAMETER ScriptPath
Path to the calling script. If not provided, automatically detected from call stack.

.PARAMETER UpdateBuckets
If true, runs 'scoop update' once to refresh Scoop core and bucket metadata (using patched, stealth-safe behavior).

.EXAMPLE
Import-Module "$PSScriptRoot\ScoopEnvironment.psm1" -Force
Initialize-ScoopEnvironment -UpdateBuckets
#>

# Ensure path helper is available everywhere (handles spaces/hyphens)
try {
    $pathTools = Join-Path $PSScriptRoot 'PathTools.psm1'
    if (Test-Path -LiteralPath $pathTools) {
        # Import globally so scripts can call Resolve-LiteralPathSafe directly.
        Import-Module $pathTools -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

# Ensure UTF-8 (no BOM) write helpers are available everywhere.
try {
    $textFileTools = Join-Path $PSScriptRoot 'TextFile.psm1'
    if (Test-Path -LiteralPath $textFileTools) {
        Import-Module $textFileTools -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

# Ensure console UI helpers are available everywhere.
try {
    $consoleUiTools = Join-Path $PSScriptRoot 'ConsoleUi.psm1'
    if (Test-Path -LiteralPath $consoleUiTools) {
        Import-Module $consoleUiTools -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

# Ensure external command runner is available everywhere (single stable .tmp log file).
try {
    $processRunner = Join-Path $PSScriptRoot 'ProcessRunner.psm1'
    if (Test-Path -LiteralPath $processRunner) {
        Import-Module $processRunner -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

function Get-ProjectRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath
    )
    
    $ScriptDir = Split-Path -Parent $ScriptPath
    $ProjectRoot = Split-Path -Parent $ScriptDir
    
    return $ProjectRoot
}

function Test-UserPathRegistryPollution {
    <#
    .SYNOPSIS
    Checks if any portable_scoop path exists in user-level PATH registry (stealth watchdog).

    .DESCRIPTION
    This watchdog function checks HKCU:\Environment\PATH to detect if ANY path containing
    "portable_scoop" has been written to the registry, which would indicate that stealth
    patching is not working properly. This deviates from the stealth methodology principle.

    The search is broad - it looks for the pattern "portable_scoop" anywhere in the
    registry PATH, regardless of the drive letter, parent directory, or subdirectory.
    This catches not just shims paths, but any portable_scoop-related paths that shouldn't
    be in the registry (e.g., portable_scoop\apps, portable_scoop\global, etc.).

    Paths can be excluded from detection by providing exclusion strings. If a path contains
    "portable_scoop" AND contains any exclusion string (case-insensitive), it will be ignored.

    .PARAMETER ExcludePaths
    Array of strings to exclude from detection. If a detected path contains any of these
    strings (case-insensitive), it will be ignored. For example, ["git", "python"] will
    ignore paths like ".../portable_scoop/git/whatever" but still detect ".../portable_scoop/shims".

    .OUTPUTS
    System.String[]. Array of matching paths found in registry, or empty array if none found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$ExcludePaths = @()
    )

    $result = @()

    try {
        # Read user-level PATH from registry
        # Note: HKCU:\Environment stores PATH as REG_EXPAND_SZ, but Get-ItemProperty returns it as a string
        $userPathItem = Get-ItemProperty -Path 'HKCU:\Environment' -Name 'PATH' -ErrorAction SilentlyContinue
        if (-not $userPathItem) {
            return @()
        }

        # Access the PATH property - it might be stored as 'PATH' or as a NoteProperty
        $userPath = $null
        if ($userPathItem.PSObject.Properties['PATH']) {
            $userPath = $userPathItem.PATH
        } elseif ($userPathItem.PSObject.Properties['Path']) {
            $userPath = $userPathItem.Path
        }

        if ([string]::IsNullOrEmpty($userPath)) {
            return @()
        }

        # Search for any PATH entry containing "portable_scoop" (case-insensitive)
        # This pattern matches regardless of drive letter, parent directory, or subdirectory
        $pathPattern = 'portable_scoop'
        $pathEntries = $userPath -split ';' | Where-Object { $_ -ne '' -and $_ -ne $null }

        foreach ($entry in $pathEntries) {
            # Normalize the entry (trim whitespace) and check if it contains the pattern (case-insensitive)
            $trimmedEntry = $entry.Trim()
            if ($trimmedEntry -and $trimmedEntry -imatch $pathPattern) {
                # Check if this path should be excluded
                $shouldExclude = $false
                if ($ExcludePaths -and $ExcludePaths.Count -gt 0) {
                    foreach ($excludeStr in $ExcludePaths) {
                        if ($excludeStr -and $trimmedEntry -imatch [Regex]::Escape($excludeStr)) {
                            $shouldExclude = $true
                            break
                        }
                    }
                }
                
                # Only add to result if not excluded
                if (-not $shouldExclude) {
                    $result += $trimmedEntry
                }
            }
        }
    } catch {
        # If we can't read the registry, assume no pollution (fail silently)
        # Registry access errors are non-critical for the watchdog
    }

    # Ensure we always return an array
    if ($null -eq $result) {
        return @()
    }
    return $result
}

function Set-StealthScoopEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$XDG_CONFIG_HOME = $null,
        
        [Parameter(Mandatory=$false)]
        [switch]$UpdatePath,
        
        [Parameter(Mandatory=$false)]
        [string]$ScriptPath = $null
    )
    
    $ShimsDir = Join-Path $ScoopRoot 'shims'
    
    # Set process-level environment variables only (no registry writes)
    $env:SCOOP = $ScoopRoot
    $env:SCOOP_CACHE = Join-Path $ScoopRoot 'cache'
    $env:SCOOP_GLOBAL = Join-Path $ScoopRoot 'global'
    
    # Set XDG_CONFIG_HOME - always use ScoopRoot unless explicitly provided
    if ($PSBoundParameters.ContainsKey('XDG_CONFIG_HOME') -and $XDG_CONFIG_HOME -and $XDG_CONFIG_HOME -ne '') {
        $env:XDG_CONFIG_HOME = $XDG_CONFIG_HOME
    } else {
        $env:XDG_CONFIG_HOME = $ScoopRoot
    }
    
    # Final safety check - ensure it's never empty
    if ([string]::IsNullOrEmpty($env:XDG_CONFIG_HOME)) {
        $env:XDG_CONFIG_HOME = $ScoopRoot
    }
    
    # Update PATH if requested (defaults to true if not specified)
    if (-not $PSBoundParameters.ContainsKey('UpdatePath') -or $UpdatePath) {
        # Add shims to PATH (idempotent - check if already present)
        if ($env:PATH -notmatch [Regex]::Escape($ShimsDir)) {
            $env:PATH = "$ShimsDir;$env:PATH"
        }

        # If Git is installed via Scoop, ensure its directories are on PATH for scripts that call `git` directly.
        # Scoop shims should normally cover this, but adding the real paths makes behaviour more robust.
        $gitRoot = Join-Path $ScoopRoot 'apps\git\current'
        if (Test-Path -LiteralPath $gitRoot) {
            $gitPaths = @(
                (Join-Path $gitRoot 'cmd'),
                (Join-Path $gitRoot 'bin'),
                (Join-Path $gitRoot 'usr\bin')
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

            foreach ($gitPath in $gitPaths) {
                if ($env:PATH -notmatch [Regex]::Escape($gitPath)) {
                    $env:PATH = "$gitPath;$env:PATH"
                }
            }
        }
    }
    
    return $ShimsDir
}

function Update-StealthScoopPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CorrectShimsPath
    )
    
    $correctShimsPathNormalized = $CorrectShimsPath.TrimEnd('\')
    $currentPath = $env:PATH
    $parts = @()
    if ($currentPath) { 
        $parts = $currentPath -split ';' | Where-Object { $_ -ne '' }
    }
    
    $shimsPattern = [regex]'[\\/]shims$'
    $correctPathFound = $false
    $removedPaths = @()
    $cleanedParts = @()
    
    foreach ($part in $parts) {
        $normalized = $part.TrimEnd('\')
        
        if ($shimsPattern.IsMatch($normalized)) {
            if ($normalized -ieq $correctShimsPathNormalized) {
                $correctPathFound = $true
                $cleanedParts += $part
            } else {
                $removedPaths += $normalized
            }
        } else {
            $cleanedParts += $part
        }
    }
    
    if (-not $correctPathFound) {
        $cleanedParts = @($CorrectShimsPath) + $cleanedParts
    }
    
    $env:PATH = ($cleanedParts -join ';').Trim(';')
    
    return [pscustomobject]@{
        RemovedPaths = $removedPaths
        PathAdded = -not $correctPathFound
        PathAlreadyCorrect = $correctPathFound -and $removedPaths.Count -eq 0
    }
}

function Enter-StealthScoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipShimValidation = $false
    )
    
    # Get project root (relative path calculation - ensures portability)
    $ProjectRoot = Get-ProjectRoot -ScriptPath $ScriptPath
    
    # Compute Scoop root path (relative to project root)
    # Note: We convert to absolute path only when needed (for external commands, env vars)
    # The base calculation is always relative, ensuring the project works from any location
    $ScoopRootPath = Join-Path $ProjectRoot '..\portable_scoop'
    $ScoopRoot = Resolve-Path $ScoopRootPath -ErrorAction SilentlyContinue
    if (-not $ScoopRoot) {
        # Fallback: convert relative path to absolute (needed for external commands)
        $ScoopRoot = [System.IO.Path]::GetFullPath($ScoopRootPath)
    }
    
    # Get Scoop shim - use scoop.cmd or scoop.ps1 directly
    $ScoopShim = Join-Path $ScoopRoot 'shims\scoop.cmd'
    if (-not (Test-Path $ScoopShim)) {
        $alt = Join-Path $ScoopRoot 'shims\scoop.ps1'
        if (Test-Path $alt) {
            $ScoopShim = $alt
        } else {
            $alt = Join-Path $ScoopRoot 'shims\scoop'
            if (Test-Path $alt) { 
                $ScoopShim = $alt 
            }
        }
    }
    # If neither shim exists and validation is not skipped, we still return the context
    # but scripts should check Test-Path $ScoopShim themselves if they need it
    # This allows scripts to handle missing Scoop gracefully
    
    $ShimsDir = Set-StealthScoopEnvironment -ScoopRoot $ScoopRoot -ScriptPath $ScriptPath
    
    return [pscustomobject]@{
        ProjectRoot = $ProjectRoot
        ScoopRoot = $ScoopRoot
        ConfigRoot = $ScoopRoot
        ShimsDir = $ShimsDir
        ScoopShim = $ScoopShim
    }
}

function Invoke-PortableScoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )
    
    $ctx = Enter-StealthScoop -ScriptPath $ScriptPath
    
    if (Test-Path $ctx.ScoopShim) {
        & $ctx.ScoopShim @Arguments
    } else {
        Write-Warning "Scoop is not installed at: $($ctx.ScoopRoot)"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
    }
}

function Show-StealthEnvironment {
    [CmdletBinding()]
    param()
    
    # Display standardized stealth environment block
    Write-Host "[*] Stealth environment active (process-level env vars):"
    Write-Host "[*] SCOOP = $env:SCOOP"
    Write-Host "[*] SCOOP_CACHE = $env:SCOOP_CACHE"
    Write-Host "[*] SCOOP_GLOBAL = $env:SCOOP_GLOBAL"
    Write-Host "[*] XDG_CONFIG_HOME = $env:XDG_CONFIG_HOME"
    
    $shimsPath = $null
    if ($env:PATH) {
        $pathParts = $env:PATH -split ';' | Where-Object { $_ -ne '' }
        foreach ($part in $pathParts) {
            if ($part -like '*shims*') {
                $shimsPath = $part
                break
            }
        }
    }
    
    if ($shimsPath) {
        Write-Host "[*] PATH includes: $shimsPath"
    } else {
        Write-Host "[*] PATH includes: (shims directory not found in PATH)"
    }

    # Best-effort visibility for Git when installed via Scoop.
    try {
        $gitCmdPath = Join-Path $env:SCOOP 'apps\git\current\cmd'
        if ($env:SCOOP -and (Test-Path -LiteralPath $gitCmdPath) -and ($env:PATH -match [Regex]::Escape($gitCmdPath))) {
            Write-Host "[*] PATH includes: $gitCmdPath"
        }
    } catch { }
    Write-Host ""
}

function Initialize-ScoopEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ScriptPath = $null,
        
        [Parameter(Mandatory=$false)]
        [switch]$UpdateBuckets = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipShimValidation = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$SuppressStealthMessage = $false,

        [Parameter(Mandatory=$false)]
        [switch]$SkipLibPatch = $false
    )
    
    # Auto-detect calling script path if not provided
    if ($null -eq $ScriptPath -or $ScriptPath -eq '') {
        $callStack = Get-PSCallStack
        $ScriptPath = $null
        
        # Look through call stack for a script file (skip module files)
        for ($i = 1; $i -lt $callStack.Count; $i++) {
            $frame = $callStack[$i]
            if ($frame.ScriptName -and $frame.ScriptName -ne '' -and $frame.ScriptName -notlike '*.psm1') {
                $ScriptPath = $frame.ScriptName
                break
            }
        }
        
        # Fallback to MyInvocation if call stack didn't work
        if (-not $ScriptPath -or $ScriptPath -eq '') {
            if ($MyInvocation.PSCommandPath -and $MyInvocation.PSCommandPath -ne '' -and $MyInvocation.PSCommandPath -notlike '*.psm1') {
                $ScriptPath = $MyInvocation.PSCommandPath
            }
        }
        
        # Final validation
        if (-not $ScriptPath -or $ScriptPath -eq '') {
            Write-Error "Cannot determine script path. Please provide -ScriptPath parameter."
            Write-Host ""
            exit 4
        }
    }
    
    # Enter stealth Scoop environment (sets process-level env vars)
    # This ensures all scripts automatically get stealth mode
    $stealthEnv = Enter-StealthScoop -ScriptPath $ScriptPath -SkipShimValidation:$SkipShimValidation
    $ProjectRoot = $stealthEnv.ProjectRoot
    $ScoopRoot = $stealthEnv.ScoopRoot
    $ScoopShim = $stealthEnv.ScoopShim
    
    $ScriptDir = Split-Path -Parent $ScriptPath

    # Show stealth environment block (all scripts using Scoop commands must show this)
    # This ensures consistency and prevents future scripts from forgetting to add it
    # Use -SuppressStealthMessage to suppress when calling from parent scripts
    if (-not $SuppressStealthMessage) {
        Show-StealthEnvironment
    }

    # Optional emergency freeze of Scoop core updates:
    # If updates.freeze_scoop_core_updates = true in manager_config.json,
    # bump Scoop's LAST_UPDATE to now so is_scoop_outdated() returns false.
    # This is intentionally silent and centralized here.
    try {
        $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
        if ((Test-Path $ManagerConfigPath) -and (Test-Path $ScoopShim)) {
            Import-Module $ManagerConfigPath -Force
            $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot
            if ($config -and $config.updates -and ($config.updates.PSObject.Properties.Name -contains 'freeze_scoop_core_updates')) {
                if ([bool]$config.updates.freeze_scoop_core_updates) {
                    $nowIso = (Get-Date).ToString('o')
                    $null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('config', 'last_update', $nowIso) -Stream:$false -NoHostOutput
                }
            }
        }
    } catch {
        # Best-effort only; failures here are non-fatal.
    }

    # Ensure Scoop lib files are patched for stealth mode (idempotent, safe if not installed yet)
    # Skip when SkipLibPatch is set (e.g., uninstall scenarios where we must always proceed).
    if ((Test-Path $ScoopRoot) -and (-not $SkipLibPatch)) {
        $PatchingModulePath = Join-Path $ProjectRoot 'modules\ScoopPatching.psm1'
        if (Test-Path $PatchingModulePath) {
            try {
                Import-Module $PatchingModulePath -Force -ErrorAction Stop
                Update-ScoopLibPatches -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
            } catch {
                Write-Warning "Failed to apply Scoop lib patches: $($_.Exception.Message)"
            }
        }
    }
    
    # Stealth watchdog: Check if any portable_scoop path exists in user-level PATH registry
    # This centralized check runs for all scripts (except menu scripts) to detect stealth breaches
    # Skip check for menu scripts (01_, 09_, etc.) that don't execute Scoop commands
    if ($ScriptPath) {
        $scriptName = Split-Path -Leaf $ScriptPath
        $isMenuScript = $scriptName -match '^(01|09)_'
        
        if (-not $isMenuScript) {
            # Broad search for ANY path containing "portable_scoop" in registry
            # This catches shims, apps, global, or any other portable_scoop subdirectory
            try {
                # Load exclusion list from config if available
                $excludePaths = @()
                if ($ProjectRoot) {
                    try {
                        $StealthConfigPath = Join-Path $PSScriptRoot 'StealthConfig.psm1'
                        if (Test-Path $StealthConfigPath) {
                            Import-Module $StealthConfigPath -Force
                            $excludePaths = Get-StealthExcludePaths -ProjectRoot $ProjectRoot
                        }
                    } catch {
                        # If config loading fails, continue without exclusions (non-critical)
                        Write-Debug "Failed to load stealth config: $_"
                    }
                }
                
                $pollutedPaths = Test-UserPathRegistryPollution -ExcludePaths $excludePaths
                if ($pollutedPaths -and $pollutedPaths.Count -gt 0) {
                    Write-Warning "STEALTH BREACH: portable_scoop paths detected in user-level PATH registry"
                    Write-Host "This should NOT happen - portable_scoop is designed to operate entirely"
                    Write-Host "through process-level environment variables, without modifying your system registry."
                    Write-Host ""
                    Write-Host "Detected registry entries (not explicitly excluded):"
                    foreach ($path in $pollutedPaths) {
                        Write-Host "  - $path"
                    }
                    Write-Host ""
                    # Calculate absolute path to manager_config.json for the note
                    $configPath = 'config\manager_config.json'
                    if ($ProjectRoot) {
                        try {
                            $configPath = Join-Path $ProjectRoot 'config\manager_config.json'
                            $configPath = [System.IO.Path]::GetFullPath($configPath)
                        } catch {
                            # Fallback to relative path if calculation fails
                            $configPath = 'config\manager_config.json'
                        }
                    }
                    Write-Host "Note: Paths can be excluded from detection by adding strings to 'stealth.exclude_paths' in"
                    Write-Host "$configPath"
                    Write-Host ""
                    Write-Host "This indicates that the stealth patching mechanism is not functioning correctly."
                    Write-Host "The patching system should prevent Scoop from writing to the registry, but"
                    Write-Host "it appears to have failed. Please investigate and fix the patching mechanism."
                    Write-Host ""
                }
            } catch {
                # Log error but don't fail - watchdog should be non-blocking
                Write-Debug "Watchdog check failed: $_"
            }
        }
    }
    
    if ($UpdateBuckets) {
        # Check if shim exists before trying to update
        # Don't show warning here - let the script's own check handle it
        # This prevents duplicate warnings
        if (Test-Path $ScoopShim) {
            # Update Scoop and buckets (this may overwrite shims)
            Write-SectionHeader -Title 'UPDATING BUCKET METADATA'

            # Run scoop update (live-ish output) without emitting PowerShell NativeCommandError records into logs.
            $updateResult = Invoke-ScoopUpdate -ScoopShim $ScoopShim -ProjectRoot $ProjectRoot
            Write-Host ""

            # Patch Scoop core after update (Scoop may have overwritten lib/system.ps1)
            # This is expected behavior - we automatically patch to maintain stealth mode
            # Import patching module
            $PatchingModulePath = Join-Path $ProjectRoot 'modules\ScoopPatching.psm1'
            if (Test-Path $PatchingModulePath) {
                Import-Module $PatchingModulePath -Force -ErrorAction SilentlyContinue
                # Apply lib patches after update (Scoop may have overwritten lib files)
                Update-ScoopLibPatches -ScoopRoot $ScoopRoot -ProjectRoot $ProjectRoot
            }

            if ($updateResult.HadErrors) {
                Write-Host ""
                $shouldContinue = Confirm-ContinueWithStaleBuckets -PromptTitle "Bucket metadata update reported errors (network/git issue)."
                if (-not $shouldContinue) {
                    throw "Aborted: bucket metadata update failed and user chose not to continue with stale buckets."
                }
                Write-Host ""
                Write-Warning "Continuing with existing local bucket metadata (may be stale)."
                Write-Host ""
            }
        }
    }
    
    # Return object with all paths
    return [pscustomobject]@{
        ScriptDir = $ScriptDir
        ProjectRoot = $ProjectRoot
        ScoopRoot = $ScoopRoot
        ScoopShim = $ScoopShim
    }
}

function Invoke-ScoopUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,

        [Parameter(Mandatory=$false)]
        [string]$ProjectRoot = $null,

        # Stream output while the process runs (best-effort "live-ish" progress).
        [Parameter(Mandatory=$false)]
        [bool]$Stream = $true
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
    }

    Assert-ExternalCommandRunner -Caller 'Invoke-ScoopUpdate'

    $cmdResult = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('update') -Stream:$Stream

    # Generic detection: non-zero exit code or generic git error markers.
    $hadErrors = $false
    if ($cmdResult.ExitCode -ne 0) {
        $hadErrors = $true
    } elseif (-not [string]::IsNullOrWhiteSpace($cmdResult.Output)) {
        if ($cmdResult.Output -match '(?im)^\s*(fatal:|error:)\s') {
            $hadErrors = $true
        }
    }

    return [pscustomobject]@{
        ExitCode  = $cmdResult.ExitCode
        Output    = $cmdResult.Output
        HadErrors = $hadErrors
        LogPath   = $cmdResult.LogPath
    }
}

function Confirm-ContinueWithStaleBuckets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PromptTitle
    )

    Write-Warning $PromptTitle
    Write-Host "Continue using existing local bucket metadata? (y/N): " -NoNewline
    $answer = Read-Host
    if ($answer -match '^(?i)y(?:es)?$') {
        return $true
    }
    return $false
}

function Test-ScoopShimAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$false)]
        [string]$ScoopRoot = $null
    )
    
    if (-not (Test-Path $ScoopShim)) {
        # Get ScoopRoot from shim path if not provided
        if (-not $ScoopRoot) {
            $ScoopRoot = Split-Path -Parent (Split-Path -Parent $ScoopShim)
        }
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        return $false
    }
    
    return $true
}

function Test-ScoopInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$false)]
        [switch]$ExitOnFailure = $false
    )
    
    # Check if Scoop root exists
    if (-not (Test-Path $ScoopRoot)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        if ($ExitOnFailure) {
            exit 4
        }
        return $false
    }
    
    # Check if shim exists
    if (-not (Test-Path $ScoopShim)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        if ($ExitOnFailure) {
            exit 4
        }
        return $false
    }
    
    return $true
}

Export-ModuleMember -Function @(
    'Initialize-ScoopEnvironment'
    'Show-StealthEnvironment'
    'Get-ProjectRoot'
    'Enter-StealthScoop'
    'Invoke-PortableScoop'
    'Set-StealthScoopEnvironment'
    'Update-StealthScoopPath'
    'Invoke-ScoopUpdate'
    'Confirm-ContinueWithStaleBuckets'
    'Test-ScoopShimAvailable'
    'Test-ScoopInstalled'
)
