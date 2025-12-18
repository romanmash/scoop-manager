<#
.SYNOPSIS
Console UI helpers

.DESCRIPTION
Centralizes the repeated console "section" and "subsection" header formatting used
throughout scripts (e.g., ===== blocks and ----- blocks) to reduce copy/paste.
#>

function New-ConsoleRule {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('=', '-', '*')]
        [string]$Char = '=',

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 200)]
        [int]$Count = 41
    )

    return (New-Object string ([char]$Char) , $Count)
}

function Write-SectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [int]$RuleWidth = 41,

        [Parameter(Mandatory = $false)]
        [switch]$NoTrailingBlankLine
    )

    $rule = New-ConsoleRule -Char '=' -Count $RuleWidth
    Write-Host $rule
    Write-Host ("  {0}" -f $Title)
    Write-Host $rule
    if (-not $NoTrailingBlankLine) {
        Write-Host ""
    }
}

function Write-SubsectionHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [int]$RuleWidth = 41,

        [Parameter(Mandatory = $false)]
        [switch]$NoTrailingBlankLine
    )

    $rule = New-ConsoleRule -Char '-' -Count $RuleWidth
    Write-Host $rule
    Write-Host ("  {0}" -f $Title)
    Write-Host $rule
    if (-not $NoTrailingBlankLine) {
        Write-Host ""
    }
}

Export-ModuleMember -Function @(
    'New-ConsoleRule',
    'Write-SectionHeader',
    'Write-SubsectionHeader'
)

