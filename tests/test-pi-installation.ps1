#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '../scripts/install-pi.ps1'
if (-not (Test-Path $installer)) { throw 'pi installer missing' }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('pi-install-' + [guid]::NewGuid())
$agent = Join-Path $fixture 'pi agent'
$codex = Join-Path $fixture 'codex'
New-Item -ItemType Directory $agent,$codex | Out-Null
Set-Content "$codex/AGENTS.md" "# Global Codex Operating Policy`n`n1. Preserve work.`n`n## Multi-agent routing`n`n- Codex only."
Set-Content "$agent/settings.json" '{"defaultModel":"preserve-me","custom":{"keep":true}}'
$settingsHash = (Get-FileHash "$agent/settings.json").Hash
& $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot ''
$first = (Get-FileHash "$agent/AGENTS.md").Hash
& $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot ''
if ((Get-FileHash "$agent/AGENTS.md").Hash -ne $first) { throw 'Not idempotent' }
if ((Get-FileHash "$agent/settings.json").Hash -ne $settingsHash) { throw 'Settings modified' }
if ((Get-Item "$agent/skills/visual-verification").LinkType -ne 'Junction') { throw 'Skill was copied' }
if ((Get-Content "$agent/AGENTS.md" -Raw) -match 'Codex only') { throw 'Codex routing leaked' }
Add-Content "$agent/AGENTS.md" 'user edit'
$edited = (Get-FileHash "$agent/AGENTS.md").Hash
$refused = $false
try { & $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot '' } catch { $refused = $true }
if (-not $refused -or (Get-FileHash "$agent/AGENTS.md").Hash -ne $edited) { throw 'Local edit not protected' }
& $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot '' -BackupConflicts
if (-not (Get-ChildItem "$agent/codex-settings/backup-*/AGENTS.md")) { throw 'Backup missing' }
Add-Content "$codex/AGENTS.md" 'unchanged excluded routing'
& $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot ''
if ((Get-FileHash "$agent/AGENTS.md").Hash -ne $first) { throw 'Excluded policy changed shared output' }
$conflictHome = Join-Path $fixture 'conflict'
New-Item -ItemType Directory "$conflictHome/extensions/codex-settings" -Force | Out-Null
Set-Content "$conflictHome/extensions/codex-settings/user.txt" 'preserve'
$refused = $false
try { & $installer -AgentDir $conflictHome -CodexHome $codex -ExternalSkillsRoot '' } catch { $refused = $true }
if (-not $refused -or (Test-Path "$conflictHome/skills/visual-verification")) { throw 'Conflict not detected before link writes' }
if ((Get-Content "$conflictHome/extensions/codex-settings/user.txt") -ne 'preserve') { throw 'Existing content changed' }
$held = [IO.File]::Open("$agent/codex-settings/install.lock", 'Open', 'ReadWrite', 'None')
try {
    $refused = $false
    try { & $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot '' } catch { $refused = $true }
    if (-not $refused) { throw 'Concurrent install not refused' }
} finally { $held.Dispose() }
$policyUpdated = (Get-Content "$codex/AGENTS.md" -Raw).Replace('Preserve work.', 'Preserve work and verify evidence.')
Set-Content "$codex/AGENTS.md" $policyUpdated
& $installer -AgentDir $agent -CodexHome $codex -ExternalSkillsRoot ''
if ((Get-Content "$agent/AGENTS.md" -Raw) -notmatch 'verify evidence') { throw 'Managed source update missing' }
if (@(Get-ChildItem "$agent/codex-settings/backup-*/AGENTS.md").Count -ne 2) { throw 'Managed update backup missing' }
Write-Output "PASS: install, idempotence, settings preservation, Junction, routing boundary, local edit refusal, backup, preflight conflict, lock. Fixture: $fixture"
