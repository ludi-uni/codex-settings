#requires -Version 7.0
[CmdletBinding()]
param([string]$CodexHome)
. "$PSScriptRoot/common.ps1"
Install-Settings -CodexHome $CodexHome -Update
