<#
.SYNOPSIS
Detects and manages running Scoop-installed applications

.DESCRIPTION
This module provides functions to detect, display, and close running processes
that were installed via Scoop. Uses path-based filtering to ensure only
Scoop-installed apps are detected (not system-installed apps with the same name).

.EXAMPLE
$ctx = Initialize-ScoopEnvironment
$runningApps = Get-RunningScoopApps -ScoopRoot $ctx.ScoopRoot
Returns array of Process objects for all running Scoop apps

.EXAMPLE
Show-RunningScoopApps -RunningApps $runningApps
Displays formatted list of running apps

.EXAMPLE
Close-RunningScoopApps -RunningApps $runningApps
Closes all running Scoop apps (graceful first, then force)
#>

function Get-RunningScoopApps {
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    # Check if apps directory exists
    $appsDir = Join-Path $ScoopRoot 'apps'
    if (-not (Test-Path $appsDir)) {
        return $null
    }
    
    try {
        # Get all processes, filter by executable path
        # Path-based filtering ensures we only match Scoop-installed apps
        # Example: If "notepad" is running from both C:\Windows and the portable_scoop location,
        # we only match the one from Scoop by checking if Path starts with ScoopRoot
        $runningApps = Get-Process -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Path -and 
                $_.Path -like "$ScoopRoot*" 
            }
        
        if ($runningApps) {
            return $runningApps
        }
        return $null
    } catch {
        # If Get-Process fails, return null
        return $null
    }
}

function Show-RunningScoopApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [System.Diagnostics.Process[]]$RunningApps,
        
        [Parameter(Mandatory=$false)]
        [string]$ScoopRoot,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowSectionHeader = $true
    )
    
    # Show section header if requested
    if ($ShowSectionHeader) {
        Write-SubsectionHeader -Title 'Checking for Running Apps'
    }
    
    # Always show output - either list of running apps or "no apps detected" message
    if ($null -ne $RunningApps -and $RunningApps.Count -gt 0) {
        Write-Warning "The following Scoop apps are currently running:"
        $RunningApps | ForEach-Object { 
            Write-Host "  - $($_.ProcessName) (PID: $($_.Id))" 
        }
    } else {
        Write-Host "[*] No running Scoop apps detected."
    }
}

function Close-RunningScoopApps {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process[]]$RunningApps
    )
    
    if (-not $RunningApps -or $RunningApps.Count -eq 0) {
        return $true
    }
    
    $allClosed = $true
    $closedCount = 0
    $failedCount = 0
    
    foreach ($process in $RunningApps) {
        try {
            # Try graceful close first
            $graceful = $false
            if ($process.HasExited) {
                $closedCount++
                continue
            }
            
            # Try CloseMainWindow (graceful close)
            try {
                $graceful = $process.CloseMainWindow()
                if ($graceful) {
                    # Wait up to 2 seconds for graceful close
                    $process.WaitForExit(2000)
                }
            } catch {
                # Process might not have a main window, continue to force close
            }
            
            # Check if still running
            if (-not $process.HasExited) {
                # Force close
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 100  # Brief pause to ensure process termination
            }
            
            $closedCount++
        } catch {
            $failedCount++
            $allClosed = $false
            Write-Warning "Failed to close $($process.ProcessName) (PID: $($process.Id)): $($_.Exception.Message)"
        }
    }
    
    if ($closedCount -gt 0) {
        Write-Host "[OK] Closed $closedCount running app(s)"
    }
    if ($failedCount -gt 0) {
        Write-Warning "Failed to close $failedCount app(s)"
    }
    
    return $allClosed
}

function Test-NoRunningApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopRoot
    )
    
    $runningApps = Get-RunningScoopApps -ScoopRoot $ScoopRoot
    Show-RunningScoopApps -RunningApps $runningApps
    
    if ($runningApps) {
        Write-Host ""
        Write-Host "Please close these apps before continuing."
        Write-Host ""
        exit 4
    }
}

Export-ModuleMember -Function @(
    'Get-RunningScoopApps',
    'Show-RunningScoopApps',
    'Close-RunningScoopApps',
    'Test-NoRunningApps'
)
