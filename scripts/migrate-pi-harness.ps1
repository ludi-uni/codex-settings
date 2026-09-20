#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceAgentDir = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pi/agent'),
    [string]$ProfileDir = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.pi/profiles/compact'),
    [string]$PiPackageRoot,
    [AllowEmptyString()][string]$RiggingSkillsRoot,
    [string[]]$ExtraExtension = @(),
    [switch]$BackupConflicts
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This migration requires native Windows PowerShell 7.' }

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function FullPath([string]$Path) { [IO.Path]::GetFullPath($Path) }
function SamePath([string]$Left, [string]$Right) {
    return [string]::Equals((FullPath $Left).TrimEnd('\\'), (FullPath $Right).TrimEnd('\\'), [StringComparison]::OrdinalIgnoreCase)
}
function PathsOverlap([string]$Left, [string]$Right) {
    $leftFull = (FullPath $Left).TrimEnd('\\')
    $rightFull = (FullPath $Right).TrimEnd('\\')
    return (SamePath $leftFull $rightFull) -or $leftFull.StartsWith($rightFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $rightFull.StartsWith($leftFull + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-PlainParents([string]$Path) {
    $cursor = FullPath $Path
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ((-not $item.PSIsContainer) -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) { throw "Unsafe destination parent: $cursor" }
        $next = Split-Path $cursor -Parent
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
}
function Hash-Text([string]$Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}
function File-HashOrEmpty([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function Get-PiPackageRoot {
    $command = Get-Command pi.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw 'PiPackageRoot was not supplied and pi.cmd was not found.' }
    $candidate = Join-Path (Split-Path $command.Source -Parent) 'node_modules/@earendil-works/pi-coding-agent'
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "Pi package not found beside pi.cmd: $candidate" }
    return FullPath $candidate
}
function Move-ToBackup([hashtable]$Entry, [string]$BackupRoot) {
    $Entry.Backup = Join-Path $BackupRoot $Entry.Relative
    New-Item -ItemType Directory -Path (Split-Path $Entry.Backup -Parent) -Force | Out-Null
    Move-Item -LiteralPath $Entry.Destination -Destination $Entry.Backup
}
function Get-PreflightSignature([string]$ManifestPath, [hashtable]$Files, [hashtable]$Links, [string]$Profile) {
    $observedFiles = [ordered]@{}
    foreach ($relative in $Files.Keys) { $observedFiles[$relative] = File-HashOrEmpty (Join-Path $Profile $relative) }
    $observedLinks = [ordered]@{}
    foreach ($relative in $Links.Keys) {
        $item = Get-Item -LiteralPath (Join-Path $Profile $relative) -Force -ErrorAction SilentlyContinue
        $observedLinks[$relative] = if ($item) { "$($item.LinkType):$($item.Target)" } else { '' }
    }
    $manifestHash = File-HashOrEmpty $ManifestPath
    return Hash-Text (([ordered]@{ manifest = $manifestHash; files = $observedFiles; links = $observedLinks } | ConvertTo-Json -Depth 5 -Compress))
}

$SourceAgentDir = FullPath $SourceAgentDir
$ProfileDir = FullPath $ProfileDir
if (PathsOverlap $SourceAgentDir $ProfileDir) { throw 'SourceAgentDir and ProfileDir must be separate, non-overlapping directories.' }
if (-not (Test-Path -LiteralPath $SourceAgentDir -PathType Container)) { throw "Source agent directory missing: $SourceAgentDir" }
Assert-PlainParents $SourceAgentDir
$sourceSettingsPath = Join-Path $SourceAgentDir 'settings.json'
if (-not (Test-Path -LiteralPath $sourceSettingsPath -PathType Leaf)) { throw "Source settings missing: $sourceSettingsPath" }
try { $sourceSettings = Get-Content -LiteralPath $sourceSettingsPath -Raw | ConvertFrom-Json -AsHashtable } catch { throw "Source settings are not valid JSON: $sourceSettingsPath" }
if (-not $PiPackageRoot) { $PiPackageRoot = Get-PiPackageRoot }
$PiPackageRoot = FullPath $PiPackageRoot
if (-not (Test-Path -LiteralPath $PiPackageRoot -PathType Container)) { throw "Pi package root missing: $PiPackageRoot" }
$packageJsonPath = Join-Path $PiPackageRoot 'package.json'
if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) { throw "Pi package metadata missing: $packageJsonPath" }
try { $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json -AsHashtable } catch { throw "Pi package metadata is not valid JSON: $packageJsonPath" }
if ($packageJson.name -ne '@earendil-works/pi-coding-agent' -or [string]::IsNullOrWhiteSpace([string]$packageJson.version)) { throw "Pi package metadata is not a valid pi coding agent package: $packageJsonPath" }
$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeCommand) { throw 'node.exe is required to create the profile pi.cmd shim.' }
$nodePath = FullPath $nodeCommand.Source
$harnessLauncher = Join-Path $repo 'scripts/pi-harness.mjs'
if (-not (Test-Path -LiteralPath $harnessLauncher -PathType Leaf)) { throw "Harness launcher missing: $harnessLauncher" }

if (-not $PSBoundParameters.ContainsKey('RiggingSkillsRoot')) {
    $resources = Get-Content -LiteralPath (Join-Path $repo 'shared/resources.json') -Raw | ConvertFrom-Json
    $candidate = FullPath (Join-Path $repo $resources.riggingSkillsRelativeRoot)
    $RiggingSkillsRoot = if (Test-Path -LiteralPath $candidate -PathType Container) { $candidate } else { '' }
}
if ($RiggingSkillsRoot) {
    $RiggingSkillsRoot = FullPath $RiggingSkillsRoot
    if (-not (Test-Path -LiteralPath $RiggingSkillsRoot -PathType Container)) { throw "Rigging skills root missing: $RiggingSkillsRoot" }
}

$extensions = [Collections.Generic.List[string]]::new()
$connector = Join-Path $SourceAgentDir 'npm/node_modules/pi-devin-connector/extensions/index.ts'
$provider = if ($sourceSettings.ContainsKey('defaultProvider')) { [string]$sourceSettings['defaultProvider'] } else { '' }
if (Test-Path -LiteralPath $connector -PathType Leaf) { $extensions.Add((FullPath $connector)) }
if ($provider -eq 'devin' -and -not (Test-Path -LiteralPath $connector -PathType Leaf)) { throw "Devin provider requires installed connector: $connector" }
foreach ($extension in $ExtraExtension) {
    if (-not [IO.Path]::IsPathFullyQualified($extension)) { throw "ExtraExtension must be an absolute path: $extension" }
    $extension = FullPath $extension
    if (-not (Test-Path -LiteralPath $extension -PathType Leaf)) { throw "ExtraExtension missing: $extension" }
    if (@($extensions) -notcontains $extension) { $extensions.Add($extension) }
}

$settings = [ordered]@{
    defaultTools = @('read', 'powershell', 'edit', 'write')
    packages = @()
    extensions = @($extensions)
    enableSkillCommands = $true
    defaultProjectTrust = 'ask'
    enableInstallTelemetry = $false
    lastChangelogVersion = [string]$packageJson.version
}
foreach ($key in @('defaultProvider', 'defaultModel', 'defaultThinkingLevel')) {
    if ($sourceSettings.ContainsKey($key)) { $settings[$key] = $sourceSettings[$key] }
}
$settingsText = ($settings | ConvertTo-Json -Depth 5) + "`n"
$harness = [ordered]@{
    schema = 'codex-settings.pi-harness.v1'
    sourceAgentDir = $SourceAgentDir
    profileDir = $ProfileDir
    piPackageRoot = $PiPackageRoot
}
$harnessText = ($harness | ConvertTo-Json -Depth 3) + "`n"
$core = Get-Content -LiteralPath (Join-Path $repo 'pi/harness/AGENTS.md') -Raw
$loop = Get-Content -LiteralPath (Join-Path $repo 'shared/loop-prevention.md') -Raw
$agentsText = "<!-- Generated by codex_setting/scripts/migrate-pi-harness.ps1; do not edit. -->`n`n$($core.Trim())`n`n$($loop.Trim())`n"
$cmdText = "@echo off`r`n`"$nodePath`" `"$harnessLauncher`" --profile `"$ProfileDir`" %*`r`n"

$links = [ordered]@{
    'skills/pi-workflow' = Join-Path $repo 'pi/harness/skills/pi-workflow'
    'skills/visual-verification' = Join-Path $repo 'skills/visual-verification'
    'extensions/control' = Join-Path $repo 'pi/extensions'
}
if ($RiggingSkillsRoot) { $links['skills/rigging'] = $RiggingSkillsRoot }
foreach ($target in $links.Values) {
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Link source missing: $target" }
}

Assert-PlainParents (Split-Path $ProfileDir -Parent)
$profileItem = Get-Item -LiteralPath $ProfileDir -Force -ErrorAction SilentlyContinue
if ($profileItem -and ((-not $profileItem.PSIsContainer) -or ($profileItem.Attributes -band [IO.FileAttributes]::ReparsePoint))) { throw "Unsafe profile directory: $ProfileDir" }
$stateDir = Join-Path $ProfileDir '.codex-harness'
$manifestPath = Join-Path $stateDir 'manifest.json'
Assert-PlainParents $stateDir
$manifest = $null
$previousManifestText = $null
if (Test-Path -LiteralPath $manifestPath) {
    $manifestItem = Get-Item -LiteralPath $manifestPath -Force
    if ($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked harness manifest refused' }
    $previousManifestText = Get-Content -LiteralPath $manifestPath -Raw
    try { $manifest = $previousManifestText | ConvertFrom-Json -AsHashtable } catch { throw 'Harness manifest is not valid JSON.' }
    if ($manifest.schema -ne 'codex-settings.pi-harness.v1') { throw 'Unknown harness manifest schema.' }
}

$files = [ordered]@{
    'AGENTS.md' = $agentsText
    'settings.json' = $settingsText
    'harness.json' = $harnessText
    'bin/pi.cmd' = $cmdText
}
$plan = [Collections.Generic.List[hashtable]]::new()
foreach ($pair in $files.GetEnumerator()) {
    $destination = Join-Path $ProfileDir $pair.Key
    $actualHash = File-HashOrEmpty $destination
    $desiredHash = Hash-Text $pair.Value
    if ($actualHash -eq $desiredHash) { continue }
    $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    $recorded = $manifest -and $manifest.files -and $manifest.files.ContainsKey($pair.Key)
    $managed = $recorded -and $existing -and $manifest.files[$pair.Key] -eq $actualHash
    $conflict = (($existing -and -not $managed) -or ($recorded -and -not $existing))
    if ($conflict -and -not $BackupConflicts) { throw "Conflict: $destination. Use -BackupConflicts only after review." }
    $plan.Add(@{ Relative = $pair.Key; Destination = $destination; Text = $pair.Value; Existing = [bool]$existing; Kind = 'file' })
}
foreach ($pair in $links.GetEnumerator()) {
    $destination = Join-Path $ProfileDir $pair.Key
    $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    $targetMatches = $existing -and $existing.LinkType -eq 'Junction' -and (SamePath ([string]$existing.Target) $pair.Value)
    if ($targetMatches) { continue }
    $recorded = $manifest -and $manifest.links -and $manifest.links.ContainsKey($pair.Key)
    $managed = $recorded -and $existing -and $existing.LinkType -eq 'Junction' -and (SamePath ([string]$manifest.links[$pair.Key]) ([string]$existing.Target))
    $conflict = (($existing -and -not $managed) -or ($recorded -and -not $existing))
    if ($conflict -and -not $BackupConflicts) { throw "Conflict: $destination. Use -BackupConflicts only after review." }
    $plan.Add(@{ Relative = $pair.Key; Destination = $destination; Target = $pair.Value; Existing = [bool]$existing; Kind = 'junction' })
}
foreach ($entry in $plan) { Assert-PlainParents (Split-Path $entry.Destination -Parent) }
$preflightSignature = Get-PreflightSignature $manifestPath $files $links $ProfileDir

if (-not $PSCmdlet.ShouldProcess($ProfileDir, "create or update isolated pi harness profile ($($plan.Count) entries)")) {
    Write-Output "PI_HARNESS_PREVIEW changes=$($plan.Count) profileDir=$ProfileDir"
    return
}
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$lockPath = Join-Path $stateDir 'migration.lock'
$lockItem = Get-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
if ($lockItem -and ($lockItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Linked harness lock refused' }
$lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
try {
    if ((Get-PreflightSignature $manifestPath $files $links $ProfileDir) -ne $preflightSignature) { throw 'Profile changed while migration was waiting for its lock; rerun after reviewing current state.' }
    $backupRoot = Join-Path $stateDir ('backup-' + [guid]::NewGuid())
    $applied = [Collections.Generic.List[hashtable]]::new()
    $manifestReplaced = $false
    try {
        foreach ($entry in $plan) {
            New-Item -ItemType Directory -Path (Split-Path $entry.Destination -Parent) -Force | Out-Null
            $entry.Backup = $null; $entry.Created = $false; $applied.Add($entry)
            if ($entry.Existing) { Move-ToBackup $entry $backupRoot }
            if ($entry.Kind -eq 'file') { [IO.File]::WriteAllText($entry.Destination, $entry.Text, [Text.UTF8Encoding]::new($false)) }
            else { New-Item -ItemType Junction -Path $entry.Destination -Target $entry.Target | Out-Null }
            $entry.Created = $true
        }
        $fileHashes = [ordered]@{}
        foreach ($pair in $files.GetEnumerator()) { $fileHashes[$pair.Key] = Hash-Text $pair.Value }
        $manifestText = ([ordered]@{ schema = 'codex-settings.pi-harness.v1'; files = $fileHashes; links = $links } | ConvertTo-Json -Depth 5) + "`n"
        if ($previousManifestText -cne $manifestText) {
            $stage = Join-Path $stateDir ('manifest-' + [guid]::NewGuid() + '.tmp')
            [IO.File]::WriteAllText($stage, $manifestText, [Text.UTF8Encoding]::new($false))
            [IO.File]::Move($stage, $manifestPath, $true)
            $manifestReplaced = $true
        }
    } catch {
        if ($manifestReplaced) {
            if ($null -ne $previousManifestText) { [IO.File]::WriteAllText($manifestPath, $previousManifestText, [Text.UTF8Encoding]::new($false)) }
            elseif (Test-Path -LiteralPath $manifestPath) { [IO.File]::Delete($manifestPath) }
        }
        for ($index = $applied.Count - 1; $index -ge 0; $index--) {
            $entry = $applied[$index]
            if ($entry.Created) {
                if ($entry.Kind -eq 'file') { [IO.File]::Delete($entry.Destination) }
                else { [IO.Directory]::Delete($entry.Destination) }
            }
            if ($entry.Backup -and (Test-Path -LiteralPath $entry.Backup)) { Move-Item -LiteralPath $entry.Backup -Destination $entry.Destination }
        }
        throw
    }
    if (Test-Path -LiteralPath $backupRoot) { Write-Output "Backup: $backupRoot" }
    Write-Output "PI_HARNESS_MIGRATED changes=$($plan.Count) profileDir=$ProfileDir"
} finally { $lock.Dispose() }
