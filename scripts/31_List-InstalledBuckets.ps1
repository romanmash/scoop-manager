<#
.SYNOPSIS
Lists all installed buckets

.CMD
scoop bucket list
#>

$ErrorActionPreference = 'Stop'

# Load simple Scoop command wrapper (standard bootstrap pattern)
$ModulePath = Join-Path $PSScriptRoot '..\modules\ScoopCommand.psm1'
Import-Module $ModulePath -Force
$ScoopEnvModule = Join-Path $PSScriptRoot '..\modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

# Use native scoop bucket list command via shared wrapper
Invoke-ScoopCommandScript -Command "bucket list" -InfoMessage "Installed buckets:"

exit 0
