#requires -Version 7.0
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PiArgs)
$ErrorActionPreference='Stop'
# Convenience entry point; normal `pi` now launches the same official CLI.
& node "$PSScriptRoot/pi-harness.mjs" @PiArgs
if($LASTEXITCODE) { throw "pi exited with code $LASTEXITCODE" }
