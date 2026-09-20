# Compact pi harness

A separately selectable native Windows profile. Existing `pi`, Codex, provider
credentials, packages and sessions remain in place. The candidate uses installed
pi **0.85.1** SDK and native interactive, print and RPC modes; it is not a pi fork.

## Migrate and start

From the repository root in PowerShell 7:

```powershell
.\scripts\migrate-pi-harness.ps1 -WhatIf
.\scripts\migrate-pi-harness.ps1
.\scripts\start-pi-harness.ps1
```

The default profile is `~/.pi/profiles/compact`. The migration reads current
`~/.pi/agent/settings.json` and retains the selected provider/model/thinking default,
but creates its own small settings file. Reapplying reconciles those managed
defaults; save custom candidate changes elsewhere or review conflicts before using
`-BackupConflicts`. The existing `scripts/install-pi.ps1` still manages the original
shared-resource foundation. These are separate destinations and ownership records.

Inspect effective resources without inference:

```powershell
.\scripts\start-pi-harness.ps1 -PiArgs @('--inspect', '--offline')
.\scripts\start-pi-harness.ps1 -PiArgs @('-p', 'Explain the current task briefly.')
.\scripts\start-pi-harness.ps1 -PiArgs @('--workflow', 'review')
```

The second command invokes the selected model and may incur its normal cost.
Use explicit `--provider` and `--model` to select another configured model. There is
no automatic provider fallback. `--help` lists the deliberately small CLI surface;
it is not a replacement for every pi package-management command.

Native Skill discovery is the default. `--workflow code|review|visual|research`
deterministically preloads exactly one workflow for the session when the model is
unreliable at following reference links. Other workflow bodies remain unloaded;
domain skills remain available on demand. Choose a new launch without the option
when changing to unrelated work.

## What is loaded

- Generated AGENTS = short `pi/harness/AGENTS.md` + `shared/loop-prevention.md`.
- `pi-workflow`: a short entry that selects code, review, visual or research guidance.
  Only the chosen reference is read; small edits need no workflow ceremony.
- Junctions to shared visual-verification and optional full rigging skill group.
  Skill names/descriptions are discovered; bodies are read on demand.
- Existing all-model loop guard, reused through a Junction.
- Installed Devin provider extension when present, to preserve provider selection.
  Other extensions can be explicitly added with migration `-ExtraExtension`.
- Native read, PowerShell, edit and write tools. Choose `--tools` for tasks requiring
  another available tool; repository requirements remain controlling.

The candidate does not automatically load baseline goal, compression, delegation,
web or image packages. This preserves a small, measurable starting point without
uninstalling anything. A needed capability must be explicitly configured and tested.
This selection limits prompt/tool overhead; it is not a security sandbox.

Project AGENTS are discovered normally, including when project executable resources
are disabled. Project `.pi` settings/extensions and `.agents/skills` require explicit
`--approve` for this launcher run. Baseline `defaultProjectTrust=always` is not
inherited. A repository's instructions still apply; skipping executable discovery
does not waive them. The launcher does not implement an interactive trust prompt.

## Authentication and data ownership

`harness.json` records source/profile/package paths, never credential values.
The SDK directly uses the source profile's canonical `auth.json` and `models.json`.
It stores sessions, settings, model cache and trust state in the candidate profile.
There is no auth copy, file symlink or hardlink: the source auth file and its existing
lock path remain the single owner. Native login/logout/OAuth refresh can therefore
update the shared source authentication; it is not an isolated second account.

Migration does not read credential contents or write the source profile. Runtime
uses pi's credential handling. Do not put auth/models config containing credentials
in the repository. Reuse currently installed provider code through explicit paths;
package updates can change that code and require renewed validation.

## Safety and rollback

Migration refuses overlapping source/destination paths and destination reparse-point
parents. It validates all sources/conflicts before publication, uses an exclusive
lock, records managed file hashes/Junction targets and preserves native session/cache
files. Correct reruns have zero changes. Unknown content or local edits stop the run.

`-BackupConflicts` explicitly preserves replaced entries under the candidate's
`.codex-harness/backup-*`. Managed changed files are backed up too. Caught publication
errors restore changed entries. Publication is not crash-atomic; retain backups and
inspect exact paths after a crash. Never recursively delete Junction targets. No
automatic pruning is performed when optional source selection changes.

To return to the original environment, stop the candidate and launch ordinary `pi`
with the original PATH and without candidate `PI_CODING_AGENT_DIR`. No baseline
rollback or credential restoration is needed. The migration changes neither system
PATH nor pi-web startup. `--session PATH` resumes that exact file; avoid pointing it
at baseline sessions during comparisons because resumed history is writable.

For an explicitly requested pi-web promotion, run:

```powershell
.\scripts\activate-pi-harness.ps1 -WhatIf
.\scripts\activate-pi-harness.ps1
```

This changes only PATH in the existing pi-web startup env file, preserving its token
and other settings, file ACL and session-storage configuration. The full env backup
stays locally under `~/.config/pi-web/backup-harness-*`; it contains the existing
token, so do not publish it. Restart pi-web afterward. `-Disable` restores native
command lookup for the same profile and also requires a restart. By default, this
activation changes only pi-web's command lookup.

To make compact the normal Windows user command as well:

```powershell
.\scripts\activate-pi-harness.ps1 -UserPath -WhatIf
.\scripts\activate-pi-harness.ps1 -UserPath
```

This prepends the profile shim to User PATH, preserves Machine PATH and backs up
the original value under the profile's `.codex-harness/`. Restart existing terminal
applications to inherit it. `-UserPath -Disable` removes only this profile entry;
it retains other PATH changes. Package commands still forward to native pi. The
native npm `pi.cmd` remains available by its absolute path for baseline sessions.

## pi-web integration boundary

Migration creates a profile-local `bin/pi.cmd` that accepts `--mode rpc` and routes
through the same SDK host. A **separate** pi-web instance can prepend that directory
to its process PATH. Its get_state/get_commands/switch_session use native pi RPC.
Do not launch another server on the existing port or replace the current service
before comparing task outcomes. No web-service restart or promotion is automatic.

Native package-management commands, version/model listing, and extension-free helpers (`--no-extensions`)
are forwarded to the absolute installed pi CLI with the baseline agent directory.
This preserves pi-web's update/title-helper contract without recursively invoking
the shim. Such explicit extension-free runs do not use the harness loop guard or
its knowledge context. Regular RPC workers use the compact harness. Qualified
`--model provider/id:thinking`, tool/context suppression and system-prompt overrides
are supported for host compatibility. RPC workers start with an in-memory placeholder
and use the requested session file after `switch_session`.

The launcher is version-gated to pi 0.85.1 because it uses installed SDK mode entry
points. An upgrade fails with a compatibility message instead of guessing signatures.

## Verification

```powershell
pwsh -NoProfile -File tests/test-pi-harness-migration.ps1
pwsh -NoProfile -File tests/test-pi-harness-activation.ps1
node tests/test-pi-harness-runtime.mjs
node --test tests/test-swe-loop-guard.mjs
node tests/test-swe-loop-runtime.mjs
```

Migration tests use temporary profiles. Runtime tests use a synthetic offline provider
with the real installed SDK and exercise resource discovery, project instructions,
print, RPC and missing-model refusal without paid model calls. `--inspect` reports
actual context/tool-definition character counts, not fabricated tokenizer counts.
These checks establish installation/runtime contracts; model task quality must be
measured separately using the accepted design's task suite. A smaller prompt alone
does not prove improved quality.
