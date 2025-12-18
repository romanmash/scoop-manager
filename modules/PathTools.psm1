<#
.SYNOPSIS
Path utilities resilient to spaces and leading hyphens.

.DESCRIPTION
Provides helpers for resolving paths to literal, absolute paths without
accidentally treating segments as switches.
#>

function Resolve-LiteralPathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not $Path) { return $null }

    # Try simple full-path resolution first
    try {
        return [System.IO.Path]::GetFullPath($Path)
    } catch { }

    # Fallback to Resolve-Path with -LiteralPath (requires existence)
    try {
        if (Test-Path -LiteralPath $Path) {
            return (Resolve-Path -LiteralPath $Path).Path
        }
    } catch { }

    # Last resort: return the original string
    return $Path
}

Export-ModuleMember -Function @(
    'Resolve-LiteralPathSafe'
)
