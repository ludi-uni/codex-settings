#requires -Version 7.0
[CmdletBinding()]
param([string]$CodexHome, [switch]$AdoptExisting)
. "$PSScriptRoot/common.ps1"
Install-Settings -CodexHome $CodexHome -AdoptExisting:$AdoptExisting
