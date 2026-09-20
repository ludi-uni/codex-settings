#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$migration = Join-Path $PSScriptRoot '../scripts/migrate-pi-harness.ps1'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath $migration)) { throw 'Harness migration script missing' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('pi-harness-' + [guid]::NewGuid())
$source = Join-Path $fixture 'source-agent'
$profile = Join-Path $fixture 'compact-profile'
$fakePackage = Join-Path $fixture 'pi-package'
New-Item -ItemType Directory -Path $source,$fakePackage | Out-Null
Set-Content -LiteralPath (Join-Path $fakePackage 'package.json') -Value '{"name":"@earendil-works/pi-coding-agent","version":"0.85.1"}' -NoNewline
$extraExtension = Join-Path $fixture 'extra-extension.ts'
Set-Content -LiteralPath $extraExtension -Value 'export default {}' -NoNewline
Set-Content -LiteralPath (Join-Path $source 'settings.json') -Value '{"defaultProvider":"example","defaultModel":"keep-me","defaultThinkingLevel":"medium","packages":["user"],"extensions":["user"]}' -NoNewline
Set-Content -LiteralPath (Join-Path $source 'auth.json') -Value 'AUTH_SENTINEL' -NoNewline
$authHash = (Get-FileHash -LiteralPath (Join-Path $source 'auth.json')).Hash
$sourceSettingsHash = (Get-FileHash -LiteralPath (Join-Path $source 'settings.json')).Hash

$nestedRefused = $false
try { & $migration -SourceAgentDir $source -ProfileDir (Join-Path $source 'nested-profile') -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $nestedRefused = $true }
if (-not $nestedRefused) { throw 'Profile nested below source was not refused' }
$profileParent = Join-Path $fixture 'profile-parent'
$sourceBelowProfile = Join-Path $profileParent 'source-agent'
New-Item -ItemType Directory -Path $sourceBelowProfile | Out-Null
Set-Content -LiteralPath (Join-Path $sourceBelowProfile 'settings.json') -Value '{}' -NoNewline
$nestedRefused = $false
try { & $migration -SourceAgentDir $sourceBelowProfile -ProfileDir $profileParent -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $nestedRefused = $true }
if (-not $nestedRefused) { throw 'Source nested below profile was not refused' }
$reparseProfile = Join-Path $fixture 'reparse-profile'
$reparseTarget = Join-Path $fixture 'reparse-target'
New-Item -ItemType Directory -Path $reparseProfile,$reparseTarget | Out-Null
New-Item -ItemType Junction -Path (Join-Path $reparseProfile '.codex-harness') -Target $reparseTarget | Out-Null
$reparseRefused = $false
try { & $migration -SourceAgentDir $source -ProfileDir $reparseProfile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $reparseRefused = $true }
if (-not $reparseRefused) { throw 'Reparse-point harness state directory was not refused' }
$aliasedSource = Join-Path $fixture 'aliased-source'
New-Item -ItemType Junction -Path $aliasedSource -Target $source | Out-Null
$aliasRefused = $false
try { & $migration -SourceAgentDir $aliasedSource -ProfileDir (Join-Path $fixture 'alias-profile') -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $aliasRefused = $true }
if (-not $aliasRefused) { throw 'Reparse-point source directory was not refused' }

& $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -WhatIf
if (Test-Path -LiteralPath $profile) { throw 'WhatIf wrote a profile' }
& $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -ExtraExtension $extraExtension,$extraExtension
if ((Get-FileHash -LiteralPath (Join-Path $source 'auth.json')).Hash -ne $authHash) { throw 'Source auth changed' }
if ((Get-FileHash -LiteralPath (Join-Path $source 'settings.json')).Hash -ne $sourceSettingsHash) { throw 'Source settings changed' }
if (Test-Path -LiteralPath (Join-Path $profile 'auth.json')) { throw 'Auth was copied to profile' }
$settings = Get-Content -LiteralPath (Join-Path $profile 'settings.json') -Raw | ConvertFrom-Json -AsHashtable
if ($settings.defaultModel -ne 'keep-me' -or $settings.lastChangelogVersion -ne '0.85.1' -or $settings.packages.Count -ne 0 -or $settings.extensions.Count -ne 1 -or $settings.defaultTools -join ',' -ne 'read,powershell,edit,write') { throw 'Profile settings are not compact or preserved correctly' }
if ((Get-Item -LiteralPath (Join-Path $profile 'skills/pi-workflow')).LinkType -ne 'Junction') { throw 'Workflow skill was not linked' }
if ((Get-Content -LiteralPath (Join-Path $profile 'bin/pi.cmd') -Raw) -notmatch 'pi-harness\.mjs.*--profile') { throw 'Profile pi.cmd shim missing launcher contract' }
if (-not (Test-Path -LiteralPath (Join-Path $profile '.codex-harness/manifest.json'))) { throw 'Manifest missing' }
$manifest = Get-Content -LiteralPath (Join-Path $profile '.codex-harness/manifest.json') -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.schema -ne 'codex-settings.pi-harness.v1' -or $manifest.files['settings.json'] -ne (Get-FileHash -LiteralPath (Join-Path $profile 'settings.json')).Hash) { throw 'Manifest integrity failed' }
$manifestTime = (Get-Item -LiteralPath (Join-Path $profile '.codex-harness/manifest.json')).LastWriteTimeUtc
$firstSettings = (Get-FileHash -LiteralPath (Join-Path $profile 'settings.json')).Hash
& $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -ExtraExtension $extraExtension,$extraExtension
if ((Get-FileHash -LiteralPath (Join-Path $profile 'settings.json')).Hash -ne $firstSettings) { throw 'Idempotent rerun changed settings' }
if ((Get-Item -LiteralPath (Join-Path $profile '.codex-harness/manifest.json')).LastWriteTimeUtc -ne $manifestTime) { throw 'No-op rerun replaced manifest' }
Add-Content -LiteralPath (Join-Path $profile 'settings.json') -Value 'user edit'
$refused = $false
try { & $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -ExtraExtension $extraExtension,$extraExtension } catch { $refused = $true }
if (-not $refused) { throw 'Edited managed settings were not refused' }
& $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -ExtraExtension $extraExtension,$extraExtension -BackupConflicts
if (-not (Get-ChildItem -LiteralPath (Join-Path $profile '.codex-harness') -Directory -Filter 'backup-*' | Get-ChildItem -Recurse -Filter settings.json)) { throw 'Edited settings backup missing' }
$refused = $false
try { & $migration -SourceAgentDir $source -ProfileDir $source -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $refused = $true }
if (-not $refused) { throw 'Source/profile overlap was not refused' }
Set-Content -LiteralPath (Join-Path $profile '.codex-harness/manifest.json') -Value '{"schema":"wrong"}' -NoNewline
$refused = $false
try { & $migration -SourceAgentDir $source -ProfileDir $profile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' } catch { $refused = $true }
if (-not $refused) { throw 'Invalid manifest was not refused' }
$rollbackProfile = Join-Path $fixture 'rollback-profile'
New-Item -ItemType Directory -Path $rollbackProfile | Out-Null
Set-Content -LiteralPath (Join-Path $rollbackProfile 'AGENTS.md') -Value 'preserve existing instructions' -NoNewline
function global:New-Item {
    [CmdletBinding()]
    param([string]$Path, [string]$ItemType, [string]$Target, [switch]$Force)
    if ($ItemType -eq 'Junction' -and $Path -like '*extensions\control') { throw 'Injected final Junction failure' }
    Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}
try {
    $failed = $false
    try { & $migration -SourceAgentDir $source -ProfileDir $rollbackProfile -PiPackageRoot $fakePackage -RiggingSkillsRoot '' -BackupConflicts } catch { $failed = $true }
    if (-not $failed) { throw 'Injected Junction failure did not stop publication' }
} finally { Remove-Item -LiteralPath Function:\New-Item }
if ((Get-Content -LiteralPath (Join-Path $rollbackProfile 'AGENTS.md') -Raw) -ne 'preserve existing instructions') { throw 'Rollback did not restore overwritten AGENTS.md' }
if (Test-Path -LiteralPath (Join-Path $rollbackProfile 'skills/pi-workflow')) { throw 'Rollback left a created Junction' }
if (-not (Test-Path -LiteralPath (Join-Path $repo 'pi/harness/skills/pi-workflow/SKILL.md'))) { throw 'Rollback touched a Junction target' }
Write-Output "PASS: nested overlap, state/source reparse refusal, harness preview, isolation, auth/settings preservation, links, manifest integrity/no-op, idempotence, conflict backup, invalid-manifest refusal, and injected rollback. Fixture: $fixture"

# Formal promotion puts the compact shim ahead of native pi on PATH.
$nativeBin = Join-Path $fixture 'native-bin'
$nativePackage = Join-Path $nativeBin 'node_modules/@earendil-works/pi-coding-agent'
New-Item -ItemType Directory -Path $nativePackage -Force | Out-Null
Set-Content -LiteralPath (Join-Path $nativeBin 'pi.cmd') -Value '@echo native fixture'
Set-Content -LiteralPath (Join-Path $nativePackage 'package.json') -Value '{"name":"@earendil-works/pi-coding-agent","version":"0.85.1"}'
$oldPath = $env:PATH
try {
    $env:PATH = (Join-Path $profile 'bin') + ';' + $nativeBin + ';' + $oldPath
    $shadowProfile = Join-Path $fixture 'shadow-profile'
    & $migration -SourceAgentDir $source -ProfileDir $shadowProfile -RiggingSkillsRoot ''
    $harness = Get-Content -LiteralPath (Join-Path $shadowProfile 'harness.json') -Raw | ConvertFrom-Json
    if ($harness.piPackageRoot -ne $nativePackage) { throw 'Compact shim shadowed native package discovery' }
} finally { $env:PATH = $oldPath }
'PASS: package discovery after compact shim PATH promotion'
