<#
.SYNOPSIS
Standard bootstrap helper for scripts.

.DESCRIPTION
Detects the calling script path, resolves the project root, loads ScoopEnvironment,
and returns the initialized context. This eliminates duplicated bootstrap code in scripts.

.PARAMETER UpdateBuckets
If set, runs Initialize-ScoopEnvironment with bucket update enabled.

.PARAMETER SkipShimValidation
If set, skips shim validation during initialization (useful for install scripts before shim exists).

.PARAMETER SuppressStealthMessage
Suppresses the stealth environment banner.

.OUTPUTS
PSCustomObject with ProjectRoot, ScoopRoot, ScoopShim, and related properties from Initialize-ScoopEnvironment.
#>

try {
    $textFileTools = Join-Path $PSScriptRoot 'TextFile.psm1'
    if (Test-Path -LiteralPath $textFileTools) {
        Import-Module $textFileTools -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

try {
    $consoleUiTools = Join-Path $PSScriptRoot 'ConsoleUi.psm1'
    if (Test-Path -LiteralPath $consoleUiTools) {
        Import-Module $consoleUiTools -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

try {
    $processRunner = Join-Path $PSScriptRoot 'ProcessRunner.psm1'
    if (Test-Path -LiteralPath $processRunner) {
        Import-Module $processRunner -Force -Global -ErrorAction SilentlyContinue | Out-Null
    }
} catch { }

function Set-ConsoleWindowIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IconPath
    )

    if (-not (Test-Path -LiteralPath $IconPath)) {
        return
    }

    if (-not ('ConsoleIconHelper' -as [type])) {
        $typeDefinition = @"
using System;
using System.Runtime.InteropServices;

public static class ConsoleIconHelper
{
    [DllImport("kernel32.dll", ExactSpelling = true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr LoadImage(IntPtr hinst, string lpszName, uint uType, int cxDesired, int cyDesired, uint fuLoad);

    public const int WM_SETICON = 0x0080;
    public const int ICON_SMALL = 0;
    public const int ICON_BIG = 1;
    public const uint IMAGE_ICON = 1;
    public const uint LR_LOADFROMFILE = 0x00000010;

    public static void SetIcon(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return;

        IntPtr hWnd = GetConsoleWindow();
        if (hWnd == IntPtr.Zero)
            return;

        IntPtr hIcon = LoadImage(IntPtr.Zero, path, IMAGE_ICON, 0, 0, LR_LOADFROMFILE);
        if (hIcon == IntPtr.Zero)
            return;

        SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_SMALL, hIcon);
        SendMessage(hWnd, WM_SETICON, (IntPtr)ICON_BIG,   hIcon);
    }
}
"@

        try {
            Add-Type -TypeDefinition $typeDefinition -ErrorAction Stop
        } catch {
            return
        }
    }

    try {
        [ConsoleIconHelper]::SetIcon($IconPath)
    } catch {
        # Non-fatal: if setting the icon fails, continue without throwing.
    }
}

function Initialize-ScriptEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$UpdateBuckets = $false,

        [Parameter(Mandatory = $false)]
        [switch]$SkipShimValidation = $false,

        [Parameter(Mandatory = $false)]
        [switch]$SuppressStealthMessage = $false,

        [Parameter(Mandatory = $false)]
        [switch]$SkipLibPatch = $false
    )

    # Determine script path (avoid module paths)
    $ScriptPath = $null
    if ($MyInvocation.ScriptName) {
        $ScriptPath = $MyInvocation.ScriptName
    } elseif ($MyInvocation.MyCommand.Path) {
        $ScriptPath = $MyInvocation.MyCommand.Path
    }
    if (-not $ScriptPath) {
        $callStack = Get-PSCallStack
        foreach ($frame in $callStack) {
            if ($frame.ScriptName -and $frame.ScriptName -notlike '*.psm1') {
                $ScriptPath = $frame.ScriptName
                break
            }
        }
    }
    if (-not $ScriptPath) {
        Write-Error "Initialize-ScriptEnvironment: Cannot determine script path."
        return $null
    }

    $ScriptDir = Split-Path -Parent $ScriptPath
    $ProjectRoot = Split-Path -Parent $ScriptDir

    # Load ScoopEnvironment.psm1 from modules folder
    $envModulePath = Join-Path $ProjectRoot 'modules\ScoopEnvironment.psm1'
    if (-not (Test-Path $envModulePath)) {
        Write-Error "Initialize-ScriptEnvironment: ScoopEnvironment.psm1 not found at: $envModulePath"
        return $null
    }

    Import-Module $envModulePath -Force

    $ctx = Initialize-ScoopEnvironment -UpdateBuckets:$UpdateBuckets -SkipShimValidation:$SkipShimValidation -SuppressStealthMessage:$SuppressStealthMessage -ScriptPath $ScriptPath -SkipLibPatch:$SkipLibPatch

    if ($ctx -and -not $script:ConsoleIconInitialized) {
        $iconPath = Join-Path $ProjectRoot 'docs\assets\logo.ico'
        if (Test-Path -LiteralPath $iconPath) {
            $script:ConsoleIconInitialized = $true
            Set-ConsoleWindowIcon -IconPath $iconPath
        }
    }

    return $ctx
}

Export-ModuleMember -Function @(
    'Initialize-ScriptEnvironment',
    'Set-ConsoleWindowIcon'
)
