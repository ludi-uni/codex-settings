#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ProfileDir = (Join-Path $env:USERPROFILE '.pi/profiles/compact'),
    [string]$PiWebConfigDir = (Join-Path $env:USERPROFILE '.config/pi-web'),
    [switch]$UserPath,
    [switch]$Disable
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProfileDir = [IO.Path]::GetFullPath($ProfileDir)
$PiWebConfigDir = [IO.Path]::GetFullPath($PiWebConfigDir)
foreach ($root in @($ProfileDir, $PiWebConfigDir)) {
    $cursor = $root
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Linked activation parent refused: $cursor" }
        $cursor = Split-Path $cursor -Parent
    }
}
$shim = Join-Path $ProfileDir 'bin/pi.cmd'
if (-not (Test-Path -LiteralPath $shim -PathType Leaf)) { throw 'Migrate the compact profile first.' }
$bin = Join-Path $ProfileDir 'bin'
if ($UserPath) {
    $beforePath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = if ($beforePath) { @($beforePath.Split(';') | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') }) } else { @() }
    $afterPath = if ($Disable) { $parts -join ';' } else { (@($bin) + $parts) -join ';' }
    if ($afterPath -cne $beforePath) {
        if (-not $PSCmdlet.ShouldProcess('Windows User PATH', $(if ($Disable) {'restore native pi lookup'} else {'select compact pi as the default command'}))) { return }
        $stateDir = Join-Path $ProfileDir '.codex-harness'
        $stateItem = Get-Item -LiteralPath $stateDir -Force
        if ($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked harness state directory refused.' }
        $backup = Join-Path $stateDir ('user-path-backup-' + [guid]::NewGuid() + '.json')
        @{ path = $beforePath } | ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding utf8NoBOM
        if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $beforePath) { throw 'User PATH changed concurrently; no change made.' }
        [Environment]::SetEnvironmentVariable('Path', $afterPath, 'User')
        Write-Output "PI_USER_HARNESS mode=$(if ($Disable) {'native'} else {'compact'}) backup=$backup"
    } else { Write-Output 'PI_USER_HARNESS unchanged' }
    if ($WhatIfPreference) { return }
    $processParts = @($env:PATH.Split(';') | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') })
    $env:PATH = if ($Disable) { $processParts -join ';' } else { (@($bin) + $processParts) -join ';' }
    return
}
$envPath = Join-Path $PiWebConfigDir 'env'
$item = Get-Item -LiteralPath $envPath -Force
if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked pi-web env file refused.' }
$before = [IO.File]::ReadAllText($envPath)
$pathMatches = [regex]::Matches($before, '(?m)^PATH=([^\r\n]*)')
if ($pathMatches.Count -ne 1) { throw 'Expected exactly one PATH entry in the existing pi-web env file.' }
if ($before -match '(?m)^PI_CODING_AGENT_DIR=') { throw 'Review pi-web agent-dir override before changing its launcher; session storage must remain stable.' }
$entries = @($pathMatches[0].Groups[1].Value.Split(';') | Where-Object { $_.TrimEnd('\') -ine $bin.TrimEnd('\') })
$path = if ($Disable) { $entries -join ';' } else { (@($bin) + $entries) -join ';' }
$match = $pathMatches[0]
$after = $before.Substring(0, $match.Index) + 'PATH=' + $path + $before.Substring($match.Index + $match.Length)
if ($after -ceq $before) { Write-Output 'PI_WEB_HARNESS unchanged'; return }
if (-not $PSCmdlet.ShouldProcess($envPath, $(if ($Disable) { 'restore native pi command lookup' } else { 'select compact harness for pi-web child processes' }))) { return }
$backup = Join-Path $PiWebConfigDir ('backup-harness-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $envPath -Destination (Join-Path $backup 'env')
if ([IO.File]::ReadAllText($envPath) -cne $before) { throw "pi-web env changed concurrently; original backup: $backup" }
$stage = Join-Path $PiWebConfigDir ('env-' + [guid]::NewGuid() + '.tmp')
[IO.File]::WriteAllText($stage, $after, [Text.UTF8Encoding]::new($false))
# Preserve the original env file's Windows ACL (it contains the existing web token).
Set-Acl -LiteralPath $stage -AclObject (Get-Acl -LiteralPath $envPath)
Set-Acl -LiteralPath (Join-Path $backup 'env') -AclObject (Get-Acl -LiteralPath $envPath)
[IO.File]::Move($stage, $envPath, $true)
Write-Output "PI_WEB_HARNESS mode=$(if ($Disable) {'native'} else {'compact'}) backup=$backup"
