#requires -Version 7.0
[CmdletBinding()]
param(
    [Alias('SourceAgentDir')][string]$AgentDir = (Join-Path $env:USERPROFILE '.pi/agent'),
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.pi/profiles/compact'),
    [string]$PiWebConfigDir = (Join-Path $env:USERPROFILE '.config/pi-web'),
    [AllowEmptyString()][string]$ExternalSkillsRoot,
    [switch]$NoActivate,
    [switch]$BackupConflicts
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$AgentDir = [IO.Path]::GetFullPath($AgentDir)
$settingsPath = Join-Path $AgentDir 'settings.json'
$original = [IO.File]::ReadAllText($settingsPath)
$settings = $original | ConvertFrom-Json -AsHashtable
$marker = Join-Path $AgentDir 'codex-settings/native-profile.json'
$firstMigration = -not (Test-Path -LiteralPath $marker)
# Preserve model/auth/UI preferences. Only the former compact resource selection moves.
if ($firstMigration) {
$settings.defaultTools = @('read','powershell','edit','write')
$settings.packages = @()
$settings.extensions = @()
$connector = Join-Path $AgentDir 'npm/node_modules/pi-devin-connector/extensions/index.ts'
if (Test-Path -LiteralPath $connector) { $settings.extensions = @($connector) }
if ($settings.ContainsKey('defaultProvider') -and $settings.defaultProvider -eq 'devin' -and -not (Test-Path -LiteralPath $connector)) { throw 'Install the Devin provider before migrating this selected model.' }
$settings.enableSkillCommands = $true
$settings.defaultProjectTrust = 'ask'
$settings.enableInstallTelemetry = $false
}
$updated = $settings | ConvertTo-Json -Depth 100
# Installer handles managed AGENTS and directory conflicts; credentials are not touched.
$installArgs = @{ AgentDir=$AgentDir; Compact=$true; BackupConflicts=$BackupConflicts }
if ($PSBoundParameters.ContainsKey('ExternalSkillsRoot')) { $installArgs.ExternalSkillsRoot = $ExternalSkillsRoot }
& "$PSScriptRoot/install-pi.ps1" @installArgs
$beforeSemantic = ($original | ConvertFrom-Json -AsHashtable) | ConvertTo-Json -Depth 100 -Compress
$afterSemantic = $settings | ConvertTo-Json -Depth 100 -Compress
if ($beforeSemantic -cne $afterSemantic) {
    if ([IO.File]::ReadAllText($settingsPath) -cne $original) { throw 'Native pi settings changed concurrently; not overwritten.' }
    $backup = Join-Path $AgentDir ('codex-settings/native-backup-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $backup | Out-Null
    Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $backup 'settings.json')
    $stage = $settingsPath + '.' + [guid]::NewGuid() + '.tmp'
    [IO.File]::WriteAllText($stage, $updated, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($stage, $settingsPath, $true)
    Write-Output "Settings backup: $backup"
}
if ($firstMigration) {
    '{"schema":"pi-native-harness.v1","settingsMigrated":true}' | Set-Content -LiteralPath $marker -Encoding utf8NoBOM
}
if (-not $NoActivate -and (Test-Path -LiteralPath (Join-Path $ProfileDir 'bin/pi.cmd'))) {
    & "$PSScriptRoot/activate-pi-harness.ps1" -ProfileDir $ProfileDir -UserPath -Disable
    if (Test-Path -LiteralPath (Join-Path $PiWebConfigDir 'env')) {
        & "$PSScriptRoot/activate-pi-harness.ps1" -ProfileDir $ProfileDir -PiWebConfigDir $PiWebConfigDir -Disable
    }
}
Write-Output "PI_NATIVE_HARNESS_READY agentDir=$AgentDir"
