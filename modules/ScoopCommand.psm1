<#
.SYNOPSIS
Scoop command execution

.DESCRIPTION
Executes a single Scoop command. Caller must provide ScoopShim (environment
initialization is caller's responsibility).

.PARAMETER ScoopShim
Path to Scoop shim executable (required, caller must provide)

.PARAMETER Command
Scoop command to execute (e.g., "bucket list", "cache show", "checkup")

.PARAMETER CommandArgs
Optional arguments for the command (e.g., "*" for "cleanup *")

.PARAMETER InfoMessage
Optional informational message to display before running command

.EXAMPLE
Import-Module "$PSScriptRoot\ScoopCommand.psm1" -Force
Invoke-ScoopCommand -ScoopShim $ScoopShim -Command "bucket list" -InfoMessage "Installed buckets:"
#>

function Invoke-ScoopCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim,
        
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [Parameter(Mandatory=$false)]
        [string]$CommandArgs = "",
        
        [Parameter(Mandatory=$false)]
        [string]$InfoMessage = ""
    )
    
    # Display info message if provided
    if ($InfoMessage) {
        Write-Host "[*] $InfoMessage"
        Write-Host ""
    }
    
    # Build command arguments array
    $commandParts = $Command -split '\s+'
    $allArgs = @($commandParts)
    if ($CommandArgs) {
        $argParts = $CommandArgs -split '\s+'
        $allArgs += $argParts
    }
    
    # Execute command
    # Suppress error action for external commands as they may return non-zero exit codes even on success
    $originalErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    
    # Capture output to check if it contains objects
    # Use splatting (@allArgs) to properly pass array elements as separate arguments
    # For .ps1 files, this ensures "bucket list" is passed as two arguments, not one
    $output = & $ScoopShim @allArgs 2>&1
    
    # Format and display output
    if ($output) {
        # Check if output contains PSCustomObjects (like from 'scoop bucket list')
        $hasObjects = $output | Where-Object { $_ -is [PSCustomObject] -or ($_ -is [System.Management.Automation.PSObject] -and $_.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject') } | Select-Object -First 1
        if ($hasObjects) {
            # Format objects as table for better readability
            $output | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
        } else {
            # Output strings and other types directly
            $output | Out-Host
        }
    }
    
    $ErrorActionPreference = $originalErrorAction
    Write-Host ""
}

function Invoke-ScoopCommandScript {
    <#
    .SYNOPSIS
    Convenience wrapper for running Scoop commands from a script.

    .DESCRIPTION
    Initializes the Scoop environment (via ScriptBootstrap/ScoopEnvironment), validates that Scoop
    is installed, then delegates to Invoke-ScoopCommand. Supports single-command execution,
    with optional multi-command batch mode for simple workflows.

    .PARAMETER Command
    Scoop command to execute (e.g., "bucket list", "cache show", "checkup"). Required in single-command mode.

    .PARAMETER CommandArgs
    Optional arguments for the command (e.g., "*" for "cleanup *").

    .PARAMETER InfoMessage
    Optional informational message to display before running the command.

    .PARAMETER UpdateBuckets
    If set, runs Initialize-ScoopEnvironment with bucket update enabled.

    .PARAMETER MultipleCommands
    Optional array of command objects for sequential execution. Each entry may have keys:
    Command, Args, Message, UpdateBuckets.

    .PARAMETER SkipShimValidation
    Passes through to Initialize-ScriptEnvironment for scenarios where shim may not exist yet.

    .PARAMETER SuppressStealthMessage
    Passes through to Initialize-ScriptEnvironment to suppress the stealth banner.

    .EXAMPLE
    Invoke-ScoopCommandScript -Command "bucket known" -InfoMessage "Known buckets:"

    .EXAMPLE
    $cmds = @(
        @{ Command = "cache show"; Message = "Cache status before cleanup:" }
        @{ Command = "cache rm"; Args = "*"; Message = "Clearing cache..." }
        @{ Command = "cache show"; Message = "Cache status after cleanup:" }
    )
    Invoke-ScoopCommandScript -MultipleCommands $cmds
    #>
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Single')]
        [string]$Command,

        [Parameter(Mandatory = $false, ParameterSetName = 'Single')]
        [string]$CommandArgs = "",

        [Parameter(Mandatory = $false, ParameterSetName = 'Single')]
        [string]$InfoMessage = "",

        [Parameter(Mandatory = $false)]
        [switch]$UpdateBuckets = $false,

        [Parameter(Mandatory = $true, ParameterSetName = 'Multiple')]
        [array]$MultipleCommands,

        [Parameter(Mandatory = $false)]
        [switch]$SkipShimValidation = $false,

        [Parameter(Mandatory = $false)]
        [switch]$SuppressStealthMessage = $false
    )

    # Bootstrap via ScriptBootstrap if available; fallback to ScoopEnvironment
    $ctx = $null
    $bootstrapPath = Join-Path $PSScriptRoot 'ScriptBootstrap.psm1'
    $envModulePath = Join-Path $PSScriptRoot 'ScoopEnvironment.psm1'

    if (Test-Path $bootstrapPath) {
        Import-Module $bootstrapPath -Force
        $ctx = Initialize-ScriptEnvironment -UpdateBuckets:$UpdateBuckets -SkipShimValidation:$SkipShimValidation -SuppressStealthMessage:$SuppressStealthMessage
    } elseif (Test-Path $envModulePath) {
        Import-Module $envModulePath -Force
        $ctx = Initialize-ScoopEnvironment -UpdateBuckets:$UpdateBuckets -SkipShimValidation:$SkipShimValidation -SuppressStealthMessage:$SuppressStealthMessage
    } else {
        Write-Error "Invoke-ScoopCommandScript: Bootstrap modules not found (expected ScriptBootstrap.psm1 or ScoopEnvironment.psm1 under modules/)."
        return
    }

    if (-not $ctx) { return }

    $ScoopRoot = $ctx.ScoopRoot
    $ScoopShim = $ctx.ScoopShim

    if (-not (Test-ScoopInstalledFromEnv -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'Multiple') {
        foreach ($cmd in $MultipleCommands) {
            if (-not $cmd) { continue }
            $c = $cmd.Command
            if (-not $c) { continue }
            $a = $cmd.Args
            $m = if ($cmd.ContainsKey('Message')) { $cmd.Message } else { "" }
            $u = if ($cmd.ContainsKey('UpdateBuckets')) { [bool]$cmd.UpdateBuckets } else { $false }

            # Optionally update buckets per command if requested
            if ($u -and (Get-Command Initialize-ScoopEnvironment -ErrorAction SilentlyContinue)) {
                $ctx = Initialize-ScoopEnvironment -UpdateBuckets -SkipShimValidation:$SkipShimValidation -SuppressStealthMessage:$SuppressStealthMessage
                $ScoopRoot = $ctx.ScoopRoot
                $ScoopShim = $ctx.ScoopShim
                if (-not (Test-ScoopInstalledFromEnv -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure)) {
                    return
                }
            }

            Invoke-ScoopCommand -ScoopShim $ScoopShim -Command $c -CommandArgs $a -InfoMessage $m
        }
    } else {
        Invoke-ScoopCommand -ScoopShim $ScoopShim -Command $Command -CommandArgs $CommandArgs -InfoMessage $InfoMessage
    }
}

function Test-ScoopInstalledFromEnv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScoopRoot,

        [Parameter(Mandatory = $true)]
        [string]$ScoopShim,

        [Parameter(Mandatory = $false)]
        [switch]$ExitOnFailure = $false
    )

    # Prefer the implementation from ScoopEnvironment if available.
    if (Get-Command Test-ScoopInstalled -ErrorAction SilentlyContinue) {
        return Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ExitOnFailure:$ExitOnFailure
    }

    # Fallback: minimal inline implementation (mirrors ScoopEnvironment behavior).
    if (-not (Test-Path $ScoopRoot)) {
        Write-Warning "Scoop is not installed at: $ScoopRoot"
        Write-Host "Please run script 19 (Install-PortableScoop) first to install Scoop."
        Write-Host ""
        if ($ExitOnFailure) {
            exit 4
        }
        return $false
    }

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
    'Invoke-ScoopCommand'
    'Invoke-ScoopCommandScript'
)
