#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$repo/scripts/install.ps1")) { throw 'Missing install.ps1' }
$run = Join-Path ([IO.Path]::GetTempPath()) ('codex-settings-test-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $run 'repo'
$target = Join-Path $run 'codex'
New-Item -ItemType Directory $fixture -Force | Out-Null
foreach ($name in @('scripts', 'skills', '.gitignore', '.gitattributes')) { Copy-Item "$repo/$name" $fixture -Recurse }
function Git-Fixture { & git -C $fixture @args | Out-Null; if ($LASTEXITCODE) { throw 'Fixture git failed' } }
Git-Fixture init -b main
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m fixture
function Run-Script([string]$Name, [bool]$Success, [string[]]$Extra = @()) {
    $output = & pwsh -NoProfile -File "$fixture/scripts/$Name.ps1" -CodexHome $target @Extra 2>&1
    if (($LASTEXITCODE -eq 0) -ne $Success) { throw "Unexpected result from ${Name}: $output" }
}
New-Item -ItemType Directory "$target/skills" -Force | Out-Null
$legacyManifest = Join-Path $target 'skills/.agent-verification-lab-visual-verification.manifest.json'
[ordered]@{
    schema = 'agent-verification-lab.skill-install.v1'; owner = 'agent-verification-lab'
    skill = 'visual-verification'; mode = 'Junction'; source = 'C:\fixture\visual-verification'
    destination = (Join-Path $target 'skills/visual-verification')
} | ConvertTo-Json | Set-Content -LiteralPath $legacyManifest -Encoding utf8NoBOM
Run-Script install $true
Run-Script check $true
if (Test-Path -LiteralPath $legacyManifest) { throw 'Legacy Junction manifest was not reconciled' }
if (@(Get-ChildItem -LiteralPath "$target/codex-settings" -File -Filter 'legacy-manifest-visual-verification-*.json').Count -ne 1) { throw 'Legacy Junction manifest backup was not preserved' }
if (-not (Test-Path "$target/skills/project-management/SKILL.md")) { throw 'Project Management Skill was not installed' }
if (-not (Test-Path "$target/skills/subagent-management/SKILL.md")) { throw 'New Skill was not installed' }
foreach ($name in @('desktop-discover.ps1', 'desktop-inspect.ps1', 'desktop-record.ps1', 'desktop-screenshot.ps1', 'winapp-common.ps1')) {
    if (-not (Test-Path "$target/skills/visual-verification/scripts/$name")) { throw "WinApp desktop backend file was not installed: $name" }
}
$visualMarker = Join-Path $target 'skills/visual-verification/.codex-settings.json'
$markerHash = (Get-FileHash $visualMarker).Hash
$newEntry = Get-Content "$fixture/skills/subagent-management/SKILL.md" -Raw
Set-Content "$fixture/skills/subagent-management/SKILL.md" 'invalid'
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m invalid-second-skill
Run-Script update $false
if ((Get-FileHash $visualMarker).Hash -ne $markerHash) { throw 'Invalid second Skill changed first Skill' }
Set-Content "$fixture/skills/subagent-management/SKILL.md" $newEntry -NoNewline
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m restore-second-skill
Run-Script update $true
$markerHash = (Get-FileHash $visualMarker).Hash
$installedNew = "$target/skills/subagent-management/SKILL.md"
$installedEntry = Get-Content $installedNew -Raw
Add-Content $installedNew 'local edit'
Run-Script check $false
Run-Script update $false
if ((Get-FileHash $visualMarker).Hash -ne $markerHash) { throw 'Second Skill drift changed first Skill' }
Set-Content $installedNew $installedEntry -NoNewline
# Simulate a home deployed by the old single-Skill installer, preserving its v1 marker.
[IO.Directory]::Move("$target/skills/subagent-management", "$run/saved-subagent")
Run-Script update $true
Run-Script check $true
if (-not (Test-Path "$target/skills/subagent-management/SKILL.md")) { throw 'Legacy update did not add new Skill' }
# Inject one publication failure after the first Skill has already been switched.
. "$fixture/scripts/common.ps1"
$previousSkills = @{}
foreach ($name in @('visual-verification', 'subagent-management')) { $previousSkills[$name] = Get-SkillFiles "$target/skills/$name" }
$pmEntry = Get-Content "$fixture/skills/project-management/SKILL.md" -Raw
Set-Content "$fixture/skills/project-management/SKILL.md" 'invalid'
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m invalid-third-skill
Run-Script update $false
foreach ($name in $previousSkills.Keys) { Assert-SameFiles (Get-SkillFiles "$target/skills/$name") $previousSkills[$name] }
Set-Content "$fixture/skills/project-management/SKILL.md" $pmEntry -NoNewline
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m restore-third-skill
$installedPm = "$target/skills/project-management/SKILL.md"
$installedPmEntry = Get-Content $installedPm -Raw
Add-Content $installedPm 'local edit'
Run-Script update $false
Run-Script check $false
foreach ($name in $previousSkills.Keys) { Assert-SameFiles (Get-SkillFiles "$target/skills/$name") $previousSkills[$name] }
Set-Content $installedPm $installedPmEntry -NoNewline
[IO.Directory]::Move("$target/skills/project-management", "$run/saved-project-management")
Run-Script update $true
Run-Script check $true
if (-not (Test-Path "$target/skills/project-management/references/operations.md")) { throw 'Two-Skill upgrade missed PM reference' }
$beforeRollback = @{}
foreach ($name in Get-ManagedSkillNames) { $beforeRollback[$name] = Get-SkillFiles "$target/skills/$name" }
function Move-SettingsDirectory([string]$From, [string]$To) {
    if ((Split-Path $From -Leaf) -like "stage-$script:failureSkill-*") { throw 'Injected publication failure' }
    [IO.Directory]::Move($From, $To)
}
foreach ($script:failureSkill in @('subagent-management', 'project-management')) {
$failedAsExpected = $false
try { Install-Settings -CodexHome $target -Update } catch {
    if ($_ -notmatch 'Injected publication failure') { throw }
    $failedAsExpected = $true
}
if (-not $failedAsExpected) { throw 'Publication fault was not exercised' }
foreach ($name in Get-ManagedSkillNames) { Assert-SameFiles (Get-SkillFiles "$target/skills/$name") $beforeRollback[$name] }
}
Run-Script check $true
$installed = Join-Path $target 'skills/visual-verification/SKILL.md'
$before = (Get-FileHash $installed).Hash
$sourceEntry = Get-Content "$fixture/skills/visual-verification/SKILL.md" -Raw
Set-Content "$fixture/skills/visual-verification/SKILL.md" 'invalid frontmatter'
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m invalid
Run-Script update $false
if ((Get-FileHash $installed).Hash -ne $before) { throw 'Committed invalid source damaged installation' }
Set-Content "$fixture/skills/visual-verification/SKILL.md" $sourceEntry -NoNewline
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m restore
Run-Script update $true
$locked = [IO.FileStream]::new((Join-Path $target 'codex-settings/install.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
try { Run-Script update $false } finally { $locked.Dispose() }
if ((Get-FileHash $installed).Hash -ne $before) { throw 'Concurrent operation damaged installation' }
Set-Content "$fixture/skills/visual-verification/auth.json" '{}'
Run-Script update $false
[IO.File]::Delete("$fixture/skills/visual-verification/auth.json")
Add-Content "$fixture/skills/visual-verification/SKILL.md" 'dirty source'
Run-Script update $false
if ((Get-FileHash $installed).Hash -ne $before) { throw 'Invalid source damaged installation' }
Git-Fixture add .
Git-Fixture -c user.name=Test -c user.email=test@example.invalid commit -m update
Run-Script update $true
Run-Script check $true
Add-Content $installed 'local edit'
Run-Script check $false
$edited = (Get-FileHash $installed).Hash
Run-Script update $false
if ((Get-FileHash $installed).Hash -ne $edited) { throw 'Local edit lost' }
$target = Join-Path $run 'migration'
New-Item -ItemType Directory "$target/skills" -Force | Out-Null
New-Item -ItemType Junction "$target/skills/visual-verification" -Target "$fixture/skills/visual-verification" | Out-Null
Run-Script install $false
Run-Script install $true @('-AdoptExisting')
Run-Script check $true
if ((Get-Item "$target/skills/visual-verification").LinkType) { throw 'Install still links to source' }
if (-not (Test-Path "$fixture/skills/visual-verification/SKILL.md")) { throw 'Junction target lost' }
Write-Output "PASS: three Skills, legacy upgrades, cross-Skill preflight, second/third publication rollback, dirty/invalid source, ignored payload, lock, local drift, junction adoption. Evidence: $run"
