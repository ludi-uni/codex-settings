#requires -Version 7.0
[CmdletBinding()]
param([string]$AgentDir, [string]$PiPackageRoot)
$ErrorActionPreference = 'Stop'
if (-not $AgentDir) { $AgentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $env:USERPROFILE '.pi/agent' } }
if (-not $PiPackageRoot) {
    foreach ($command in @(Get-Command pi.cmd -All -ErrorAction Stop)) {
        $candidate = Join-Path (Split-Path $command.Source -Parent) 'node_modules/@earendil-works/pi-coding-agent'
        if (Test-Path "$candidate/package.json") { $PiPackageRoot = $candidate; break }
    }
}
if (-not (Test-Path "$PiPackageRoot/package.json")) { throw 'Pass -PiPackageRoot for this pi installation.' }
& node "$PSScriptRoot/check-pi.mjs" $PiPackageRoot ([IO.Path]::GetFullPath($AgentDir))
if ($LASTEXITCODE -ne 0) { throw 'pi resource/startup verification failed' }
