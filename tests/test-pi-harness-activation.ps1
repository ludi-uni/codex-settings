#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../scripts/activate-pi-harness.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('pi-activate-' + [guid]::NewGuid())
$profile = Join-Path $root 'profile'
$web = Join-Path $root 'web'
New-Item -ItemType Directory -Path "$profile/bin",$web | Out-Null
Set-Content "$profile/bin/pi.cmd" '@echo fixture'
$original = "PI_WEB_TOKEN=fixture-not-a-secret`r`nPATH=C:\Windows;C:\Tools`r`nOTHER=preserve`r`n"
[IO.File]::WriteAllText("$web/env", $original)
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
& $scriptPath -ProfileDir $profile -PiWebConfigDir $web -UserPath -WhatIf
if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $userPathBefore) { throw 'User PATH preview wrote registry' }
& $scriptPath -ProfileDir $profile -PiWebConfigDir $web -WhatIf
if ([IO.File]::ReadAllText("$web/env") -cne $original) { throw 'Preview wrote env' }
& $scriptPath -ProfileDir $profile -PiWebConfigDir $web
$activated = [IO.File]::ReadAllText("$web/env")
if ($activated -cne $original.Replace('PATH=', "PATH=$profile\bin;")) { throw 'Unexpected activation change' }
& $scriptPath -ProfileDir $profile -PiWebConfigDir $web
if ([IO.File]::ReadAllText("$web/env") -cne $activated) { throw 'Activation is not idempotent' }
& $scriptPath -ProfileDir $profile -PiWebConfigDir $web -Disable
if ([IO.File]::ReadAllText("$web/env") -cne $original) { throw 'Native path restoration failed' }
if (@(Get-ChildItem $web -Directory -Filter backup-harness-*).Count -ne 2) { throw 'Backup count wrong' }
'PASS: activation preview, exact PATH-only edit, token preservation, no-op, disable and backups'
