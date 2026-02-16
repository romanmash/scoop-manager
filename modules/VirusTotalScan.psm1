<#
.SYNOPSIS
VirusTotal app check helpers

.DESCRIPTION
Provides helpers for running VirusTotal checks via `scoop virustotal` and
interpreting the results in a structured way. Uses Scoop's own integration,
no direct HTTP calls to VirusTotal.

.EXAMPLE
Import-Module "$PSScriptRoot\VirusTotalScan.psm1" -Force
$settings = Get-VirusTotalSettings -ProjectRoot $ProjectRoot
$result = Invoke-VirusTotalCheckForApp -AppName '7zip' -ScoopShim $ScoopShim -Settings $settings
if ($result.Status -eq 'Risky') {
    $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $result
}
#>

function Get-VirusTotalSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    # Import ManagerConfig for lookup toggle reading.
    $ManagerConfigPath = Join-Path $PSScriptRoot 'ManagerConfig.psm1'
    if (-not (Test-Path -LiteralPath $ManagerConfigPath)) {
        Write-Error "ManagerConfig.psm1 module not found at: $ManagerConfigPath"
        throw "ManagerConfig.psm1 module not found"
    }

    # Import VirusTotalConfig for API-key parsing (single source of truth).
    $VirusTotalConfigPath = Join-Path $PSScriptRoot 'VirusTotalConfig.psm1'
    if (-not (Test-Path -LiteralPath $VirusTotalConfigPath)) {
        Write-Error "VirusTotalConfig.psm1 module not found at: $VirusTotalConfigPath"
        throw "VirusTotalConfig.psm1 module not found"
    }

    Import-Module $ManagerConfigPath -Force
    Import-Module $VirusTotalConfigPath -Force

    $config = Get-ManagerConfigJson -ProjectRoot $ProjectRoot

    $enabledOnInstall = $false

    if ($config -and $config.virustotal) {
        $vtSection = $config.virustotal

        # Primary toggle: 'lookup' (explicit enable/disable for VirusTotal lookups).
        if ($vtSection.PSObject.Properties.Name -contains 'lookup') {
            $enabledOnInstall = [bool]$vtSection.lookup
        }
    }

    # Resolve API key via shared helper to avoid duplicate parsing logic.
    $apiKey = $null
    if ($enabledOnInstall) {
        $vtConfig = Get-VirusTotalConfig -ProjectRoot $ProjectRoot
        if ($vtConfig -and $vtConfig.ApiKey) {
            $apiKey = $vtConfig.ApiKey
        }
    }

    [pscustomobject]@{
        EnabledOnInstall = $enabledOnInstall
        ApiKey           = $apiKey
    }
}

function Invoke-VirusTotalCheckForApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $false)]
        [string]$AppSpec,

        [Parameter(Mandatory = $true)]
        [string]$ScoopShim,

        [Parameter(Mandatory = $false)]
        [pscustomobject]$Settings,

        [ValidateSet('Install', 'Audit')]
        [string]$Mode = 'Install'
    )

    # Determine what we pass to 'scoop virustotal' (app or app@version or manifest path)
    if (-not $AppSpec) {
        $AppSpec = $AppName
    }

    # Global configuration gate: disable VirusTotal lookups when turned off or when no API key is available.
    $lookupEnabled = $false
    if ($Settings -and $Settings.PSObject.Properties.Name -contains 'EnabledOnInstall') {
        $lookupEnabled = [bool]$Settings.EnabledOnInstall
    }

    if (-not $Settings -or -not $lookupEnabled -or -not $Settings.ApiKey) {
        $message = if (-not $lookupEnabled) {
            'VirusTotal lookup is disabled by configuration.'
        } else {
            'VirusTotal API key not configured.'
        }

        if ($Mode -eq 'Audit') {
            Write-Warning "VirusTotal check skipped/unavailable for app '$AppSpec'. Treating as potentially unsafe."
            Write-Host "[*] Details: $message"
            Write-Host ""
        }

        return [pscustomobject]@{
            AppName      = $AppSpec
            Detections   = $null
            TotalEngines = $null
            HasReport    = $false
            Url          = $null
            ExitCode     = $null
            Status       = 'Skipped'
            Message      = $message
        }
    }

    if (-not (Test-Path $ScoopShim)) {
        return [pscustomobject]@{
            AppName      = $AppSpec
            Detections   = $null
            TotalEngines = $null
            HasReport    = $false
            Url          = $null
            ExitCode     = $null
            Status       = 'Error'
            Message      = "Scoop shim not found at $ScoopShim."
        }
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    Assert-ExternalCommandRunner -Caller 'Invoke-VirusTotalCheckForApp'

    # Decide what we pass to `scoop virustotal`.
    # Default: use the given spec (app or app@version or manifest path).
    $specForCommand = $AppSpec

    # For install-time checks of pinned versions (app@version), first generate a
    # version-specific manifest via `scoop download app@version` so we can pass
    # that manifest file directly to `scoop virustotal`. This mirrors Scoop's
    # own install/download pipeline and avoids relying on virustotal's internal
    # app@version handling.
    if ($Mode -eq 'Install' -and
        $AppSpec -like '*@*' -and
        -not (Test-Path -LiteralPath $AppSpec -ErrorAction SilentlyContinue)) {

        # Derive Scoop root from shim path: <root>\shims\scoop.cmd
        $scoopRoot = $null
        try {
            $shimDir = Split-Path -Parent $ScoopShim
            if ($shimDir) {
                $scoopRoot = Split-Path -Parent $shimDir
            }
        } catch {
            $scoopRoot = $null
        }

        # Extract bare app name (no bucket prefix, no @version)
        $appNameOnly = $null
        if ($AppSpec -match '^(?<bucket>[^/]+)/(?<name>[^@]+)@(?<version>.+)$') {
            $appNameOnly = $Matches['name']
        } elseif ($AppSpec -match '^(?<name>[^@]+)@(?<version>.+)$') {
            $appNameOnly = $Matches['name']
        } else {
            $appNameOnly = $AppName
        }

        $workspaceManifest = $null
        if ($scoopRoot -and $appNameOnly) {
            $workspaceManifest = Join-Path $scoopRoot ("workspace\{0}.json" -f $appNameOnly)
        }

        # Generate/update the pinned manifest and hashes in the workspace.
        $downloadCmd = @('download', $AppSpec, '--no-update-scoop')
        $downloadResult = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath $ScoopShim -ArgumentList $downloadCmd -Stream:$false -NoHostOutput
        $downloadExitCode = $downloadResult.ExitCode

        if ($downloadExitCode -eq 0 -and $workspaceManifest -and (Test-Path -LiteralPath $workspaceManifest)) {
            $specForCommand = $workspaceManifest
        } else {
            # Fall back to the original spec if download/manifest generation fails.
            $specForCommand = $AppSpec
        }
    }

    # Decide how to display the target in logs vs. what to pass
    # to `scoop virustotal`:
    # - If we ended up with a manifest path, display the logical app name
    #   (AppName/AppSpec) but pass the manifest path to Scoop.
    # - Otherwise, display and pass the same spec.
    if (Test-Path -LiteralPath $specForCommand -ErrorAction SilentlyContinue) {
        # Prefer the fully-qualified app spec (app@version) for display when available,
        # even if we are passing a manifest path to Scoop.
        if ($AppSpec -and $AppSpec -like '*@*') {
            $displaySpec = $AppSpec
        } elseif ($AppName) {
            $displaySpec = $AppName
        } else {
            $displaySpec = $AppSpec
        }
    } else {
        $displaySpec = $AppSpec
    }

    Write-Host "[*] VirusTotal check: $displaySpec"

    # Check only the requested app; dependency fan-out can cause misleading
    # first-match parsing and unnecessary API consumption/rate-limit pressure.
    $cmd = @('virustotal', $specForCommand, '--no-depends', '--no-update-scoop')

    $vtResult = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath $ScoopShim -ArgumentList $cmd -Stream:$false -NoHostOutput
    $exitCode = $vtResult.ExitCode
    $output = if ($vtResult.Output) { $vtResult.Output -split "\r?\n" } else { @() }

    $detections = $null
    $totalEngines = $null
    $url = $null
    $hasReport = $false
    $requestFailureMessage = $null

    foreach ($line in $output) {
        if (-not $requestFailureMessage -and $line -match 'VirusTotal request failed:\s*(.+)$') {
            $requestFailureMessage = $matches[1].Trim()
        }

        # Typical line: ...\7zip.json: 0/57, see https://www.virustotal.com/gui/file/...
        if ($line -match ':\s*(\d+)\/(\d+)\s*,\s*see\s+(https?://\S+)') {
            $currentDetections = [int]$matches[1]
            $currentTotalEngines = [int]$matches[2]
            $currentUrl = $matches[3]

            # Keep the worst result when Scoop emits multiple lines
            # (for example, multiple URLs in one manifest).
            if (-not $hasReport -or $currentDetections -gt $detections) {
                $detections = $currentDetections
                $totalEngines = $currentTotalEngines
                $url = $currentUrl
            }
            $hasReport = $true
            continue
        }
        # Fallback without URL
        if (-not $hasReport -and $line -match ':\s*(\d+)\/(\d+)') {
            $detections = [int]$matches[1]
            $totalEngines = [int]$matches[2]
            $hasReport = $true
            continue
        }
        if ($line -match ':\s*(\d+)\/(\d+)') {
            $currentDetections = [int]$matches[1]
            $currentTotalEngines = [int]$matches[2]
            if ($currentDetections -gt $detections) {
                $detections = $currentDetections
                $totalEngines = $currentTotalEngines
            }
            $hasReport = $true
        }
    }

    $status = 'Error'
    $message = ''

    if ($requestFailureMessage) {
        $status = 'Error'
        $message = "VirusTotal request failed: $requestFailureMessage"
    } elseif ($hasReport) {
        if ($detections -eq 0) {
            $status = 'Clean'
            $message = "VirusTotal: $detections/$totalEngines engines flagged."
        } elseif ($detections -gt 0) {
            $status = 'Risky'
            $message = "VirusTotal: $detections/$totalEngines engines flagged."
        }
    } else {
        # No parsed report; classify based on exit code and output
        if ($exitCode -eq 0) {
            $status = 'Skipped'
            $message = "VirusTotal completed successfully but returned no summary (no manifest/hash in Scoop output)."
        } else {
            $status = 'Error'
            $message = "VirusTotal check failed (exit code $exitCode)."
        }
    }

    # Surface key info for the user
    if ($status -eq 'Clean') {
        Write-Host "[*] Result: $detections/$totalEngines engines flagged"
        if ($url) {
            Write-Host "[*] Report: $url"
            Write-Host ""
        }
    } elseif ($status -eq 'Risky') {
        Write-Host "[*] Result: $detections/$totalEngines engines flagged"
        if ($url) {
            Write-Host "[*] Report: $url"
        }
        if ($Mode -eq 'Audit') {
            $warningTarget = if ($displaySpec) { $displaySpec } else { $AppSpec }
            Write-Warning "VirusTotal reported detections for app '$warningTarget'."
            Write-Host ""
        }
    } elseif ($status -eq 'Skipped') {
        if ($Mode -eq 'Audit') {
            Write-Warning "VirusTotal check skipped/unavailable for app '$AppSpec'. Treating as potentially unsafe."
            if ($message) {
                Write-Host "[*] Details: $message"
            }
            Write-Host ""
        } else {
            Write-Host "[*] VirusTotal check for $AppSpec skipped: no summary from 'scoop virustotal' (no manifest/hash available)."
        }
    } else {
        # Error status
        if ($Mode -eq 'Audit') {
            $warningTarget = if ($displaySpec) { $displaySpec } else { $AppSpec }
            $exitCodeText = if ($null -ne $exitCode -and "$exitCode" -ne '') { $exitCode } else { 'n/a' }
            Write-Warning "VirusTotal check failed for app '$warningTarget' (exit code $exitCodeText)."
            if ($message) {
                Write-Host "[*] Details: $message"
            }
            Write-Host ""
        } else {
            $exitCodeText = if ($null -ne $exitCode -and "$exitCode" -ne '') { $exitCode } else { 'n/a' }
            Write-Host "[*] VirusTotal check failed for app '$displaySpec' (exit code $exitCodeText)."
            if ($message) {
                Write-Host "[*] Details: $message"
            }
            Write-Host ""
            if ($output) {
                Write-Host "[*] Raw output from 'scoop virustotal':"
                $output | ForEach-Object { Write-Host "    $_" }
                Write-Host ""
            }
        }
    }

    [pscustomobject]@{
        AppName      = $AppSpec
        Detections   = $detections
        TotalEngines = $totalEngines
        HasReport    = $hasReport
        Url          = $url
        ExitCode     = $exitCode
        Status       = $status
        Message      = $message
    }
}

function Invoke-VirusTotalPreInstallDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$CheckResult
    )

    $blockingStatuses = @('Risky', 'Skipped', 'Error')

    # For non-blocking statuses, default to install.
    if ($blockingStatuses -notcontains $CheckResult.Status) {
        return 'Install'
    }

    $appName = $CheckResult.AppName

    switch ($CheckResult.Status) {
        'Risky' {
            Write-Warning "VirusTotal reported detections for app '$appName'."
        }
        'Skipped' {
            Write-Warning "VirusTotal check was skipped/unavailable for app '$appName'. Treating as potentially unsafe."
        }
        'Error' {
            Write-Warning "VirusTotal check failed for app '$appName'. Treating as potentially unsafe."
        }
        default {
            Write-Warning "VirusTotal check returned status '$($CheckResult.Status)' for app '$appName'."
        }
    }

    if ($CheckResult.PSObject.Properties.Name -contains 'Message' -and $CheckResult.Message) {
        Write-Host "[*] Details: $($CheckResult.Message)"
    }

    # Use a single-line prompt that is also written via Write-Host so it appears in logs.
    # Read-Host is called without a prompt to avoid duplicate text and to keep the
    # log/console output consistent.
    $promptText = "Proceed with  [C]ontinue / [S]kip this app / [A]bort all: "

    while ($true) {
        Write-Host -NoNewline $promptText
        $answer = Read-Host
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Host ""
            continue
        }
        $choice = $answer.Trim().Substring(0,1).ToUpperInvariant()
        switch ($choice) {
            'C' {
                Write-Host "[*] Decision: Continue (C)"
                return 'Install'
            }
            'S' {
                Write-Host "[*] Decision: Skip (S)"
                return 'Skip'
            }
            'A' {
                Write-Host "[*] Decision: Abort (A)"
                return 'Abort'
            }
            default {
                Write-Host ""
                Write-Host "Please enter C (continue), S (skip), or A (abort)."
            }
        }
    }
}

function Invoke-VirusTotalGateForApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,

        [Parameter(Mandatory = $false)]
        [string]$AppSpec,

        [Parameter(Mandatory = $true)]
        [string]$ScoopShim,

        [Parameter(Mandatory = $false)]
        [pscustomobject]$Settings,

        [ValidateSet('Install', 'Audit')]
        [string]$Mode = 'Install'
    )

    $checkResult = Invoke-VirusTotalCheckForApp -AppName $AppName -AppSpec $AppSpec -ScoopShim $ScoopShim -Settings $Settings -Mode $Mode

    $decision = 'Install'
    $blockingStatuses = @('Risky', 'Skipped', 'Error')
    if ($Mode -eq 'Install' -and $blockingStatuses -contains $checkResult.Status) {
        $decision = Invoke-VirusTotalPreInstallDecision -CheckResult $checkResult
    }

    [pscustomobject]@{
        AppName    = $AppName
        AppSpec    = $AppSpec
        Status     = $checkResult.Status
        Message    = $checkResult.Message
        Decision   = $decision
        CheckResult = $checkResult
    }
}

Export-ModuleMember -Function @(
    'Get-VirusTotalSettings',
    'Invoke-VirusTotalCheckForApp',
    'Invoke-VirusTotalPreInstallDecision',
    'Invoke-VirusTotalGateForApp'
)
