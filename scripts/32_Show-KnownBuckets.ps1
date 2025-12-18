<#
.SYNOPSIS
Shows all official/known buckets

.CMD
scoop bucket known
#>

$ErrorActionPreference = 'Stop'

# Load simple Scoop command wrapper (standard bootstrap pattern)
$ModulePath = Join-Path $PSScriptRoot '..\modules\ScoopCommand.psm1'
Import-Module $ModulePath -Force
$ScoopEnvModule = Join-Path $PSScriptRoot '..\modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

Invoke-ScoopCommandScript -Command "bucket known" -InfoMessage "Known buckets:"

exit 0
