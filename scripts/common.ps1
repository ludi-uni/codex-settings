#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SettingsHome([string]$Path) {
    if (-not $Path) { $Path = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' } }
    return [IO.Path]::GetFullPath($Path)
}

function Assert-PlainAncestors([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse-point parent refused: $current" }
        }
        $current = Split-Path $current -Parent
    }
}

function Get-SkillFiles([string]$Path, [switch]$AllowRootJunction, [switch]$Installed) {
    $root = Get-Item -LiteralPath $Path -Force
    if (-not $root.PSIsContainer) { throw 'Skill must be a directory' }
    if (($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (-not $AllowRootJunction -or $root.LinkType -ne 'Junction')) { throw 'Skill root is an unexpected link' }
    $result = [ordered]@{}
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($root.FullName)
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Nested link refused: $($item.FullName)" }
            if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
            $relative = [IO.Path]::GetRelativePath($root.FullName, $item.FullName).Replace('\', '/')
            if ($Installed -and $relative -eq '.codex-settings.json') { continue }
            $result[$relative] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }
    return $result
}

function Assert-SameFiles($Left, $Right) {
    if ($Left.Count -ne $Right.Count) { throw 'Skill file inventory differs' }
    foreach ($name in $Left.Keys) {
        if (-not $Right.Contains($name) -or $Left[$name] -cne $Right[$name]) { throw "Skill content differs: $name" }
    }
}

function Invoke-SettingsGit([string[]]$Arguments) {
    $output = & git -C $script:SettingsRepo @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Git validation failed' }
    return $output
}

function Get-ManagedSkillNames { return @('visual-verification', 'subagent-management', 'project-management') }

function Get-ValidatedSource([string]$SkillName = 'visual-verification') {
    if ($SkillName -notin (Get-ManagedSkillNames)) { throw 'Unknown managed Skill' }
    $script:SettingsRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    Assert-PlainAncestors $script:SettingsRepo
    $top = Invoke-SettingsGit @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($top) -ne $script:SettingsRepo) { throw 'Scripts must be in repository root/scripts' }
    $commit = Invoke-SettingsGit @('rev-parse', 'HEAD')
    if (@(Invoke-SettingsGit @('status', '--porcelain', '--untracked-files=all')).Count) { throw 'Source repository has uncommitted changes; commit or resolve them first' }
    $skill = Join-Path $script:SettingsRepo "skills/$SkillName"
    Assert-PlainAncestors $skill
    $files = Get-SkillFiles $skill
    $tracked = @(Invoke-SettingsGit @('ls-files', '--', "skills/$SkillName"))
    if ($tracked.Count -ne $files.Count) { throw 'Skill contains untracked or ignored payload files' }
    foreach ($name in $files.Keys) {
        if ("skills/$SkillName/$name" -cnotin $tracked) { throw "Untracked Skill file: $name" }
        if ([IO.Path]::GetExtension($name) -notin @('.md', '.ps1', '.py', '.yaml')) { throw "Unsupported Skill file: $name" }
        $body = Get-Content -LiteralPath (Join-Path $skill $name) -Raw
        if ($body -match '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)') { throw "Possible secret in Skill file: $name" }
    }
    $required = @('SKILL.md')
    if ($SkillName -eq 'project-management') { $required += 'references/operations.md' }
    if ($SkillName -eq 'visual-verification') {
        $required += @('agents/openai.yaml', 'scripts/common.ps1', 'scripts/screenshot.ps1', 'scripts/record.ps1', 'scripts/extract-frames.ps1', 'scripts/contact-sheet.ps1', 'scripts/record-av.ps1', 'scripts/inspect-media.ps1', 'scripts/waveform.ps1', 'scripts/evaluate-sync.ps1', 'scripts/analyze-speech.ps1', 'scripts/backends/whisperx_backend.py', 'scripts/desktop-discover.ps1', 'scripts/desktop-inspect.ps1', 'scripts/desktop-record.ps1', 'scripts/desktop-screenshot.ps1', 'scripts/winapp-common.ps1')
    }
    foreach ($name in $required) {
        if (-not $files.Contains($name)) { throw "Required Skill file missing: $name" }
    }
    $entry = Get-Content (Join-Path $skill 'SKILL.md') -Raw
    if ($entry -notmatch ("(?s)^---\r?\nname: " + [regex]::Escape($SkillName) + '\r?\ndescription: [^\r\n]+\r?\n---')) { throw 'Invalid Skill frontmatter' }
    foreach ($relative in @(Invoke-SettingsGit @('ls-files', '--', '*.ps1'))) {
        $file = Get-Item -LiteralPath (Join-Path $script:SettingsRepo $relative)
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "PowerShell syntax invalid: $($file.FullName)" }
    }
    return [pscustomobject]@{ Name = $SkillName; Commit = $commit; Path = $skill; Files = $files; Repo = $script:SettingsRepo }
}

function Read-Installed([string]$Path, [string]$SkillName = 'visual-verification') {
    Assert-PlainAncestors $Path
    $marker = Join-Path $Path '.codex-settings.json'
    $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json -AsHashtable
    if ($SkillName -notin (Get-ManagedSkillNames) -or $state.schema -ne "codex-settings.$SkillName.v1" -or $state.source_commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid installation metadata' }
    $actual = Get-SkillFiles $Path -Installed
    Assert-SameFiles $actual $state.files
    return $state
}

function Move-SettingsDirectory([string]$From, [string]$To) {
    [IO.Directory]::Move($From, $To)
}

function Install-Settings([string]$CodexHome, [switch]$AdoptExisting, [switch]$Update) {
    $sources = @(Get-ManagedSkillNames | ForEach-Object { Get-ValidatedSource $_ })
    if (@($sources.Commit | Select-Object -Unique).Count -ne 1) { throw 'Source commit changed during validation' }
    $targetHome = Get-SettingsHome $CodexHome
    $skills = Join-Path $targetHome 'skills'
    $storage = Join-Path $targetHome 'codex-settings'
    Assert-PlainAncestors $skills
    Assert-PlainAncestors $storage
    New-Item -ItemType Directory -Path $storage -Force | Out-Null
    $lock = [IO.FileStream]::new((Join-Path $storage 'install.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
    try {
        $legacyManifest = Join-Path $skills '.agent-verification-lab-visual-verification.manifest.json'
        $legacyManifestBackup = $null
        $legacyManifestMoved = $false
        if (Test-Path -LiteralPath $legacyManifest) {
            Assert-PlainAncestors $legacyManifest
            $legacyItem = Get-Item -LiteralPath $legacyManifest -Force
            if ($legacyItem.PSIsContainer -or ($legacyItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Legacy visual-verification manifest must be a plain file' }
            try {
                $legacyState = Get-Content -LiteralPath $legacyManifest -Raw | ConvertFrom-Json
                $legacyDestination = [IO.Path]::GetFullPath([string]$legacyState.destination)
            } catch { throw 'Legacy visual-verification manifest is invalid' }
            $expectedDestination = [IO.Path]::GetFullPath((Join-Path $skills 'visual-verification'))
            if ($legacyState.schema -ne 'agent-verification-lab.skill-install.v1' -or $legacyState.owner -ne 'agent-verification-lab' -or $legacyState.skill -ne 'visual-verification' -or $legacyState.mode -ne 'Junction' -or $legacyDestination -ne $expectedDestination) {
                throw 'Unrecognized legacy visual-verification manifest; refusing to move it'
            }
            $legacyManifestBackup = Join-Path $storage ("legacy-manifest-visual-verification-$([guid]::NewGuid().ToString('N')).json")
        }
        $plans = @()
        $managedCount = 0
        # Validate every destination before staging or changing any installed Skill.
        foreach ($source in $sources) {
            $destination = Join-Path $skills $source.Name
            $exists = Test-Path -LiteralPath $destination
            $oldFiles = $null; $oldMarker = $null; $oldLink = $null
            if ($exists) {
                $oldLink = (Get-Item -LiteralPath $destination -Force).LinkTarget
                if (Test-Path -LiteralPath (Join-Path $destination '.codex-settings.json')) {
                    $old = Read-Installed $destination $source.Name
                    $oldMarker = (Get-FileHash (Join-Path $destination '.codex-settings.json')).Hash
                    $oldFiles = $old.files
                    $managedCount++
                } else {
                    if (-not $AdoptExisting -or $Update) { throw "Unmanaged Skill '$($source.Name)'; install requires -AdoptExisting and identical content" }
                    $oldFiles = Get-SkillFiles $destination -AllowRootJunction
                    Assert-SameFiles $oldFiles $source.Files
                }
            }
            $id = [guid]::NewGuid().ToString('N')
            $plans += [pscustomobject]@{
                Source = $source; Destination = $destination; Exists = $exists
                OldFiles = $oldFiles; OldMarker = $oldMarker; OldLink = $oldLink
                Stage = Join-Path $storage "stage-$($source.Name)-$id"
                Backup = Join-Path $storage "backup-$($source.Name)-$id"
                MovedOld = $false; MovedNew = $false
            }
        }
        if ($Update -and $managedCount -eq 0) { throw 'No managed installation; run install.ps1 first' }
        # An update may add a newly managed Skill to an existing managed home.
        foreach ($plan in $plans) {
            $source = $plan.Source
            Copy-Item -LiteralPath $source.Path -Destination $plan.Stage -Recurse
            Assert-SameFiles (Get-SkillFiles $plan.Stage) $source.Files
            $metadata = [ordered]@{
                schema = "codex-settings.$($source.Name).v1"; source_repo = $source.Repo
                source_commit = $source.Commit; installed_utc = [DateTime]::UtcNow.ToString('o')
                backup_path = $(if ($plan.Exists) { $plan.Backup } else { $null }); files = $source.Files
            }
            $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $plan.Stage '.codex-settings.json') -Encoding utf8NoBOM
            [void](Read-Installed $plan.Stage $source.Name)
        }
        foreach ($plan in $plans) {
            $source = $plan.Source
            $fresh = Get-ValidatedSource $source.Name
            if ($fresh.Commit -ne $source.Commit) { throw 'Source commit changed during staging' }
            Assert-SameFiles $fresh.Files $source.Files
            if ($plan.Exists) {
                if ((Get-Item -LiteralPath $plan.Destination -Force).LinkTarget -ne $plan.OldLink) { throw 'Destination link changed during staging' }
                Assert-SameFiles (Get-SkillFiles $plan.Destination -AllowRootJunction -Installed:($null -ne $plan.OldMarker)) $plan.OldFiles
                if ($plan.OldMarker -and (Get-FileHash (Join-Path $plan.Destination '.codex-settings.json')).Hash -ne $plan.OldMarker) { throw 'Metadata changed during staging' }
            } elseif (Test-Path -LiteralPath $plan.Destination) { throw 'Destination appeared during staging' }
            foreach ($path in @($plan.Stage, $plan.Backup)) {
                if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path)) -ne [IO.Path]::GetFullPath($storage)) { throw 'Transaction path escaped storage' }
            }
        }
        New-Item -ItemType Directory -Path $skills -Force | Out-Null
        # Same-volume directory renames; never traverse a junction target.
        try {
            if ($legacyManifestBackup) {
                [IO.File]::Move($legacyManifest, $legacyManifestBackup)
                $legacyManifestMoved = $true
            }
            foreach ($plan in $plans) {
                if ($plan.Exists) { Move-SettingsDirectory $plan.Destination $plan.Backup; $plan.MovedOld = $true }
                Move-SettingsDirectory $plan.Stage $plan.Destination; $plan.MovedNew = $true
                [void](Read-Installed $plan.Destination $plan.Source.Name)
            }
        } catch {
            $publishError = $_
            $recoveryErrors = @()
            for ($index = $plans.Count - 1; $index -ge 0; $index--) {
                $plan = $plans[$index]
                try {
                    if ($plan.MovedNew) { Move-SettingsDirectory $plan.Destination $plan.Stage }
                    if ($plan.MovedOld) { Move-SettingsDirectory $plan.Backup $plan.Destination }
                } catch { $recoveryErrors += "$($plan.Source.Name): $($_.Exception.Message); backup=$($plan.Backup)" }
            }
            if ($legacyManifestMoved) {
                try { [IO.File]::Move($legacyManifestBackup, $legacyManifest) }
                catch { $recoveryErrors += "legacy visual-verification manifest: $($_.Exception.Message); backup=$legacyManifestBackup" }
            }
            if ($recoveryErrors.Count) { throw "Publication failed: $publishError. Manual recovery required: $($recoveryErrors -join '; ')" }
            throw $publishError
        }
        foreach ($plan in $plans) {
            Write-Output "SKILL=$($plan.Source.Name)"
            Write-Output "SOURCE_COMMIT=$($plan.Source.Commit)"
            Write-Output "DESTINATION=$($plan.Destination)"
            if ($plan.Exists) { Write-Output "BACKUP=$($plan.Backup)" }
        }
        if ($legacyManifestMoved) { Write-Output "LEGACY_MANIFEST_BACKUP=$legacyManifestBackup" }
        Write-Output 'RESULT=INSTALLED'
    } finally { $lock.Dispose() }
}
