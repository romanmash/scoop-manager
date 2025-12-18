<#
.SYNOPSIS
Displays startup execution policy and language mode diagnostics

.CMD
-
#>

$ErrorActionPreference = 'Stop'

# Path resolution
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Console UI helpers (section/subsection headers), best-effort
try {
    $ConsoleUiPath = Join-Path $ProjectRoot 'modules\ConsoleUi.psm1'
    if (Test-Path -LiteralPath $ConsoleUiPath) {
        Import-Module $ConsoleUiPath -Force -ErrorAction SilentlyContinue
    }
} catch { }

function Show-SectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    if (Get-Command Write-SectionHeader -ErrorAction SilentlyContinue) {
        Write-SectionHeader -Title $Title
    } else {
        Write-Host ""
        Write-Host ("=" * 80)
        Write-Host ("  {0}" -f $Title)
        Write-Host ("=" * 80)
        Write-Host ""
    }
}

function Show-SubsectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    if (Get-Command Write-SubsectionHeader -ErrorAction SilentlyContinue) {
        Write-SubsectionHeader -Title $Title
    } else {
        Write-Host ""
        Write-Host ("-- {0}" -f $Title)
        Write-Host ""
    }
}

Show-SectionHeader -Title 'STARTUP POLICY DIAGNOSTICS'

Show-SubsectionHeader -Title 'Execution Policy'
Write-Host "[*] Execution policy (per scope):"
Write-Host ""
try {
    Get-ExecutionPolicy -List | Format-Table -AutoSize
} catch {
    Write-Warning "Get-ExecutionPolicy -List failed: $($_.Exception.Message)"
}

Show-SubsectionHeader -Title 'Language Mode'
$languageMode = $ExecutionContext.SessionState.LanguageMode
Write-Host "[*] Language mode: $languageMode"
if ($languageMode -ne 'FullLanguage') {
    Write-Warning "PowerShell is running in $languageMode. Some scripts, Add-Type, or .NET/COM usage may be blocked by corporate policy."
}
Write-Host ""

Show-SubsectionHeader -Title 'Console Host'
Write-Host "[*] Host name: $($host.Name)"
Write-Host "[*] If you want the Scoop icon and classic behavior, use Windows Console Host."
Write-Host "[*] Run script 11 (Open-TerminalSettings) from the menu to set 'Default terminal application' to Windows Console Host."
Write-Host ""

Show-SubsectionHeader -Title 'Interpretation'
Write-Host "[*] If MachinePolicy or UserPolicy are not 'Undefined', execution policy is controlled by Group Policy."
Write-Host "[*] Scoop Manager cannot relax corporate execution policy; use this report when talking to your IT/security team if scripts are blocked."

exit 0
