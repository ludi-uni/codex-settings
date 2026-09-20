#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('pi-native-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $root | Out-Null
Set-Content "$root/settings.json" '{"defaultProvider":"fixture","defaultModel":"keep-model","theme":"dark","packages":["optional-package"]}'
Set-Content "$root/auth.json" 'AUTH_SENTINEL'
$authHash=(Get-FileHash "$root/auth.json").Hash
$migrate=Join-Path $PSScriptRoot '../scripts/migrate-pi-harness.ps1'
& $migrate -AgentDir $root -RiggingSkillsRoot '' -NoActivate
$settings=Get-Content "$root/settings.json" -Raw | ConvertFrom-Json
if($settings.defaultModel -ne 'keep-model' -or $settings.theme -ne 'dark') {throw 'User preferences changed'}
if($settings.packages.Count -ne 0 -or $settings.defaultTools.Count -ne 4) {throw 'Compact selection missing'}
if((Get-Item "$root/skills/pi-workflow").LinkType -ne 'Junction') {throw 'Skill not shared'}
if((Get-Content "$root/AGENTS.md" -Raw) -notmatch 'Progress rule') {throw 'Native AGENTS missing policy'}
$settingsHash=(Get-FileHash "$root/settings.json").Hash
& $migrate -AgentDir $root -RiggingSkillsRoot '' -NoActivate
if((Get-FileHash "$root/settings.json").Hash -ne $settingsHash) {throw 'Not idempotent'}
if((Get-FileHash "$root/auth.json").Hash -ne $authHash) {throw 'Auth changed'}
$custom=Get-Content "$root/settings.json" -Raw | ConvertFrom-Json -AsHashtable
$custom.packages=@('user-added-later')
$custom | ConvertTo-Json -Depth 5 | Set-Content "$root/settings.json"
& $migrate -AgentDir $root -RiggingSkillsRoot '' -NoActivate
if((Get-Content "$root/settings.json" -Raw | ConvertFrom-Json).packages[0] -ne 'user-added-later') {throw 'Reapply reset later user settings'}
if(-not (Get-ChildItem "$root/codex-settings/native-backup-*/settings.json")) {throw 'Backup missing'}
'PASS: official-layout instructions/skills, compact selection, model/UI/auth preservation, backup and idempotence'
