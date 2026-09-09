#requires -Version 7.0
[CmdletBinding()]
param([string]$CodexHome)
. "$PSScriptRoot/common.ps1"
$targetHome = Get-SettingsHome $CodexHome
$sources = @(Get-ManagedSkillNames | ForEach-Object { Get-ValidatedSource $_ })
foreach ($source in $sources) {
    $destination = Join-Path $targetHome "skills/$($source.Name)"
    $state = Read-Installed $destination $source.Name
    Write-Output "SKILL=$($source.Name)"
    Write-Output "INSTALLED_SOURCE_COMMIT=$($state.source_commit)"
    Write-Output "INSTALLED_SOURCE_REPO=$($state.source_repo)"
    Write-Output "DESTINATION=$destination"
    Write-Output "BACKUP=$($state.backup_path)"
    Write-Output "REPO_COMMIT=$($source.Commit)"
    Assert-SameFiles (Get-SkillFiles $destination -Installed) $source.Files
    if ($state.source_commit -ne $source.Commit) { throw 'Installed source commit differs; run update.ps1' }
}
Write-Output 'RESULT=OK'
foreach ($name in @('ffmpeg', 'ffprobe')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
    Write-Output "$($name.ToUpperInvariant())=$(if ($command) { $command.Source } else { 'UNAVAILABLE (required for media operations)' })"
}
