<#
.SYNOPSIS
Shared module for converting scoop bucket list output to objects

.DESCRIPTION
Converts scoop bucket list output to array of bucket name objects,
filtering out header rows and separator lines.

.PARAMETER ScoopShim
Path to Scoop shim executable

.EXAMPLE
Import-Module "$PSScriptRoot\ScoopBucketList.psm1" -Force
$buckets = ConvertFrom-ScoopBucketList -ScoopShim $ScoopShim
#>

function ConvertFrom-ScoopBucketList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScoopShim
    )
    
    $buckets = @()
    
    try {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        Assert-ExternalCommandRunner -Caller 'ConvertFrom-ScoopBucketList'

        $bucketCmd = Invoke-ExternalCommandLogged -ProjectRoot $projectRoot -FilePath $ScoopShim -ArgumentList @('bucket', 'list') -Stream:$false -NoHostOutput
        $bucketsRaw = if ($bucketCmd.Output) { $bucketCmd.Output -split "\r?\n" } else { @() }
        if ($bucketsRaw) {
            $bucketsRaw | Select-String -Pattern '^\s*(\S+)' | ForEach-Object {
                $name = $_.Matches.Groups[1].Value
                # Filter out header row and separator lines (dashes)
                if ($name -and $name -ne 'Name' -and $name -notmatch '^-+$') {
                    $buckets += [pscustomobject]@{ name = $name }
                }
            }
        }
    } catch {
        # Return empty array on error
    }
    
    return $buckets
}

Export-ModuleMember -Function @(
    'ConvertFrom-ScoopBucketList'
)
