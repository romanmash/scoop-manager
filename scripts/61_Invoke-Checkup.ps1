<#
.SYNOPSIS
Checks for potential problems

.CMD
scoop checkup
#>

$ErrorActionPreference = 'Stop'

# Load simple Scoop command wrapper (standard bootstrap pattern)
$ModulePath = Join-Path $PSScriptRoot '..\modules\ScoopCommand.psm1'
Import-Module $ModulePath -Force
$ScoopEnvModule = Join-Path $PSScriptRoot '..\modules\ScoopEnvironment.psm1'
Import-Module $ScoopEnvModule -Force

Invoke-ScoopCommandScript -Command "checkup" -InfoMessage "Running Scoop checkup..."

exit 0
