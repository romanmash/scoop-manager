<#
.SYNOPSIS
Uninstalls all user apps (keeps core apps and persist data)

.CMD
scoop list
scoop uninstall
#>

$ErrorActionPreference = 'Stop'

# Load bootstrap module
$BootstrapPath = Join-Path $PSScriptRoot '..\modules\ScriptBootstrap.psm1'
Import-Module $BootstrapPath -Force
$ctx = Initialize-ScriptEnvironment
$ProjectRoot = $ctx.ProjectRoot
$ScoopRoot = $ctx.ScoopRoot
$ScoopShim = $ctx.ScoopShim
$ScoopEnvModule = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

$coreAppsModule = Join-Path $ProjectRoot 'modules\CoreApps.psm1'
if (-not (Test-Path -LiteralPath $coreAppsModule)) {
    Write-Error "CoreApps module not found at: $coreAppsModule"
    Write-Host ""
    exit 4
}
Import-Module $coreAppsModule -Force
$coreApps = Get-CoreApps -ProjectRoot $ProjectRoot
if (-not $coreApps -or $coreApps.Count -eq 0) {
    exit 4
}

# Check if Scoop is installed (graceful exit if not - centralized check)
if (-not (Test-ScoopInstalled -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim)) {
    Write-Host "[*] Nothing to uninstall."
    Write-Host ""
    exit 0
}

# Load RunningScoopApps module
$RunningAppsModulePath = Join-Path $ProjectRoot 'modules\RunningScoopApps.psm1'
Import-Module $RunningAppsModulePath -Force

Write-Host "[*] Using Scoop shim: $ScoopShim"
Write-Host ""

Write-SectionHeader -Title 'UNINSTALLING APPS'

Test-NoRunningApps -ScoopRoot $ScoopRoot
Write-Host ""

# Load before/after module
$BeforeAfterPath = Join-Path $ProjectRoot 'modules\BeforeAfterState.psm1'
Import-Module $BeforeAfterPath -Force

# Show initial state
Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowBefore

# Get list of installed apps (excluding scoop itself)
try {
    $installedCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$false -NoHostOutput
    $installedRaw = if ($installedCmd.Output) { $installedCmd.Output -split "\r?\n" } else { @() }
    $installedText = $installedRaw -join "`n"
    
    # Check if there are no apps installed
    if ($installedText -match "There aren't any apps installed") {
        Write-Host "[*] No apps installed."
        Write-Host ""
        exit 0
    }
    
    # Parse app names from list output, exclude 'scoop' itself and header lines
    # Only match lines that look like table rows (have multiple columns separated by spaces)
    $apps = $installedRaw | 
            Select-String -Pattern '^\s*(\S+)\s+\S+\s+\S+' | 
            ForEach-Object { $_.Matches.Groups[1].Value } |
            Where-Object { 
                $coreApps -notcontains $_ -and
                $_ -ne 'Name' -and 
                $_ -ne 'Installed' -and 
                $_ -ne '----' -and
                $_ -notlike '*:*'
            }
    
    if (-not $apps -or $apps.Count -eq 0) {
        Write-Host "[*] No user apps to uninstall (only core apps remain: $($coreApps -join ', '))."
        Write-Host ""
        exit 0
    }
} catch {
    Write-Error "Failed to list apps: $($_.Exception.Message)"
    Write-Host ""
    exit 4
}

Write-Host ""
Write-SubsectionHeader -Title 'Apps to Uninstall'
$apps | ForEach-Object { Write-Host "  - $_" }
Write-Host ""
Write-Warning "Persist data will be kept (use script 54_Cleanup-PersistAll to purge)."
Write-Warning "Held apps will be automatically unheld."
Write-Host ""

Write-SubsectionHeader -Title 'Removing Apps'

# Try batch uninstall first (faster)
# Use splatting (@cmdArgs) to properly pass array elements as separate arguments
$cmdArgs = @('uninstall') + $apps
$null = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList $cmdArgs -Stream:$true

# Check if batch uninstall actually failed by checking which apps remain
# Don't rely on exceptions since Scoop may output errors even on success
try {
    $installedCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('list') -Stream:$false -NoHostOutput
    $installedRaw = if ($installedCmd.Output) { $installedCmd.Output -split "\r?\n" } else { @() }
    $installedText = $installedRaw -join "`n"
    
    # Check if there are no apps installed
    if ($installedText -match "There aren't any apps installed") {
        $stillInstalled = @()
    } else {
        # Parse currently installed apps (excluding scoop)
        $stillInstalled = $installedRaw | 
                Select-String -Pattern '^\s*(\S+)\s+\S+\s+\S+' | 
                ForEach-Object { $_.Matches.Groups[1].Value } |
                Where-Object { 
                    $coreApps -notcontains ([string]$_).ToLowerInvariant() -and
                    $_ -ne 'Name' -and 
                    $_ -ne 'Installed' -and 
                    $_ -ne '----' -and
                    $_ -ne 'There' -and
                    $_ -notlike '*:*'
                }
    }
} catch {
    # If we can't list, assume all apps still need uninstalling
    $stillInstalled = $apps
}

# If any apps remain, uninstall them one by one
if ($stillInstalled -and $stillInstalled.Count -gt 0) {
    Write-Host ""
    Write-Host "[*] Completing uninstall for remaining apps..."
    Write-Host ""
    
    foreach ($app in $stillInstalled) {
        Write-Host "[*] Uninstalling: $app"
        $uninstallCmd = Invoke-ExternalCommandLogged -ProjectRoot $ProjectRoot -FilePath $ScoopShim -ArgumentList @('uninstall', $app) -Stream:$false -NoHostOutput
        $output = $uninstallCmd.Output

        # Filter out "isn't installed" messages - these are not errors
        $filteredOutput = $output -split "`r?`n" | 
            Where-Object { 
                $_ -notmatch "isn't installed" -and 
                $_ -notmatch "not installed" -and
                $_.Trim() -ne ''
            }
        
        if ($filteredOutput) {
            Write-Host ($filteredOutput -join "`n")
        }
        Write-Host ""
    }
} else {
    Write-Host ""
}

# Verify all apps are removed before cleaning workspace
Write-SubsectionHeader -Title 'Verifying Removal'
$appsDir = Join-Path $ScoopRoot 'apps'
$remainingApps = @()
if (Test-Path $appsDir) {
    $remainingApps = Get-ChildItem -Path $appsDir -Directory | 
                     Where-Object { $coreApps -notcontains $_.Name.ToLowerInvariant() } |
                     Select-Object -ExpandProperty Name
}

if ($remainingApps.Count -eq 0) {
    Write-Host "[OK] All apps removed successfully"
    Write-Host ""
    
    # Clean up workspace folder (temporary installation metadata)
    $workspaceDir = Join-Path $ScoopRoot 'workspace'
    if (Test-Path $workspaceDir) {
        Write-SubsectionHeader -Title 'Cleaning Up Workspace Metadata'
        try {
            Remove-Item -Path $workspaceDir -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Workspace cleaned"
            Write-Host ""
        } catch {
            Write-Warning "Could not remove workspace: $($_.Exception.Message)"
            Write-Host ""
        }
    }
} else {
    Write-Warning "Some apps still remain, skipping workspace cleanup:"
    $remainingApps | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
}

# Show final state
try {
    Show-BeforeAfterState -ScoopRoot $ScoopRoot -ScoopShim $ScoopShim -ShowAfter
} catch {
    Write-Host "(Could not list apps; scoop core should remain)"
    Write-Host ""
}

exit 0
