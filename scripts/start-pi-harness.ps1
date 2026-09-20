#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.pi/profiles/compact'),
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$PiArgs
)
$ErrorActionPreference = 'Stop'
& node "$PSScriptRoot/pi-harness.mjs" --profile $ProfileDir @PiArgs
if ($LASTEXITCODE -ne 0) { throw "pi harness exited with code $LASTEXITCODE" }
