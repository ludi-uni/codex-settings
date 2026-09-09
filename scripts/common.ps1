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

function Get-ValidatedSource {
    $script:SettingsRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    Assert-PlainAncestors $script:SettingsRepo
    $top = Invoke-SettingsGit @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($top) -ne $script:SettingsRepo) { throw 'Scripts must be in repository root/scripts' }
    $commit = Invoke-SettingsGit @('rev-parse', 'HEAD')
    if (@(Invoke-SettingsGit @('status', '--porcelain', '--untracked-files=all')).Count) { throw 'Source repository has uncommitted changes; commit or resolve them first' }
    $skill = Join-Path $script:SettingsRepo 'skills/visual-verification'
    Assert-PlainAncestors $skill
    $files = Get-SkillFiles $skill
    $tracked = @(Invoke-SettingsGit @('ls-files', '--', 'skills/visual-verification'))
    if ($tracked.Count -ne $files.Count) { throw 'Skill contains untracked or ignored payload files' }
    foreach ($name in $files.Keys) {
        if ("skills/visual-verification/$name" -cnotin $tracked) { throw "Untracked Skill file: $name" }
        if ([IO.Path]::GetExtension($name) -notin @('.md', '.ps1', '.py', '.yaml')) { throw "Unsupported Skill file: $name" }
        $body = Get-Content -LiteralPath (Join-Path $skill $name) -Raw
        if ($body -match '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)') { throw "Possible secret in Skill file: $name" }
    }
    foreach ($name in @('SKILL.md', 'agents/openai.yaml', 'scripts/common.ps1', 'scripts/screenshot.ps1', 'scripts/record.ps1', 'scripts/extract-frames.ps1', 'scripts/contact-sheet.ps1', 'scripts/record-av.ps1', 'scripts/inspect-media.ps1', 'scripts/waveform.ps1', 'scripts/evaluate-sync.ps1', 'scripts/analyze-speech.ps1', 'scripts/backends/whisperx_backend.py')) {
        if (-not $files.Contains($name)) { throw "Required Skill file missing: $name" }
    }
    $entry = Get-Content (Join-Path $skill 'SKILL.md') -Raw
    if ($entry -notmatch '(?s)^---\r?\nname: visual-verification\r?\ndescription: [^\r\n]+\r?\n---') { throw 'Invalid Skill frontmatter' }
    foreach ($relative in @(Invoke-SettingsGit @('ls-files', '--', '*.ps1'))) {
        $file = Get-Item -LiteralPath (Join-Path $script:SettingsRepo $relative)
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "PowerShell syntax invalid: $($file.FullName)" }
    }
    return [pscustomobject]@{ Commit = $commit; Path = $skill; Files = $files; Repo = $script:SettingsRepo }
}

function Read-Installed([string]$Path) {
    Assert-PlainAncestors $Path
    $marker = Join-Path $Path '.codex-settings.json'
    $state = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json -AsHashtable
    if ($state.schema -ne 'codex-settings.visual-verification.v1' -or $state.source_commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid installation metadata' }
    $actual = Get-SkillFiles $Path -Installed
    Assert-SameFiles $actual $state.files
    return $state
}

function Install-Settings([string]$CodexHome, [switch]$AdoptExisting, [switch]$Update) {
    $source = Get-ValidatedSource
    $targetHome = Get-SettingsHome $CodexHome
    $skills = Join-Path $targetHome 'skills'
    $destination = Join-Path $skills 'visual-verification'
    $storage = Join-Path $targetHome 'codex-settings'
    Assert-PlainAncestors $skills
    Assert-PlainAncestors $storage
    New-Item -ItemType Directory -Path $storage -Force | Out-Null
    $lock = [IO.FileStream]::new((Join-Path $storage 'install.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
    try {
        $exists = Test-Path -LiteralPath $destination
        $oldFiles = $null
        $oldMarker = $null
        $oldLink = $null
        if ($exists) {
            $item = Get-Item -LiteralPath $destination -Force
            $oldLink = $item.LinkTarget
            if (Test-Path -LiteralPath (Join-Path $destination '.codex-settings.json')) {
                $old = Read-Installed $destination
                $oldMarker = (Get-FileHash (Join-Path $destination '.codex-settings.json')).Hash
                $oldFiles = $old.files
            } else {
                if (-not $AdoptExisting -or $Update) { throw 'Unmanaged existing Skill; install requires -AdoptExisting and identical content' }
                $oldFiles = Get-SkillFiles $destination -AllowRootJunction
                Assert-SameFiles $oldFiles $source.Files
            }
        } elseif ($Update) { throw 'No installed Skill; run install.ps1 first' }
        $id = [guid]::NewGuid().ToString('N')
        $stage = Join-Path $storage "stage-$id"
        $backup = Join-Path $storage "backup-$id"
        Copy-Item -LiteralPath $source.Path -Destination $stage -Recurse
        Assert-SameFiles (Get-SkillFiles $stage) $source.Files
        $metadata = [ordered]@{ schema = 'codex-settings.visual-verification.v1'; source_repo = $source.Repo; source_commit = $source.Commit; installed_utc = [DateTime]::UtcNow.ToString('o'); backup_path = $(if ($exists) { $backup } else { $null }); files = $source.Files }
        $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage '.codex-settings.json') -Encoding utf8NoBOM
        $fresh = Get-ValidatedSource
        if ($fresh.Commit -ne $source.Commit) { throw 'Source commit changed during staging' }
        Assert-SameFiles $fresh.Files $source.Files
        if ($exists) {
            if ((Get-Item -LiteralPath $destination -Force).LinkTarget -ne $oldLink) { throw 'Destination link changed during staging' }
            Assert-SameFiles (Get-SkillFiles $destination -AllowRootJunction -Installed:($null -ne $oldMarker)) $oldFiles
            if ($oldMarker -and (Get-FileHash (Join-Path $destination '.codex-settings.json')).Hash -ne $oldMarker) { throw 'Metadata changed during staging' }
        } elseif (Test-Path -LiteralPath $destination) { throw 'Destination appeared during staging' }
        New-Item -ItemType Directory -Path $skills -Force | Out-Null
        # Same-volume directory renames. Never traverse, delete, or alter a junction target.
        foreach ($path in @($stage, $backup)) {
            if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path)) -ne [IO.Path]::GetFullPath($storage)) { throw 'Transaction path escaped storage' }
        }
        $movedOld = $false; $movedNew = $false
        try {
            if ($exists) { [IO.Directory]::Move($destination, $backup); $movedOld = $true }
            [IO.Directory]::Move($stage, $destination); $movedNew = $true
            [void](Read-Installed $destination)
        } catch {
            if ($movedNew) { [IO.Directory]::Move($destination, $stage) }
            if ($movedOld) { [IO.Directory]::Move($backup, $destination) }
            throw
        }
        Write-Output 'RESULT=INSTALLED'
        Write-Output "SOURCE_COMMIT=$($source.Commit)"
        Write-Output "DESTINATION=$destination"
        if ($exists) { Write-Output "BACKUP=$backup" }
    } finally { $lock.Dispose() }
}
