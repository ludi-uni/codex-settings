# codex-settings

Personal Codex Skills and their controlled local installation. Manages only
`skills/visual-verification` and `skills/subagent-management`; it does not import
the entire `.codex` directory.

## Subagent management

`skills/subagent-management/SKILL.md` is a self-contained Codex Skill: no runtime,
scheduler, queue, model configuration or external project integration. Invoke it
as `$subagent-management` or let Codex select it for suitable delegation work.
It uses whichever collaboration tools and roles are available in the current session.

Main owns decomposition, bounded assignment, collection, conflict resolution and
final acceptance. Assign independent questions once, pass minimal context, preserve
shared work, and serialize overlapping writes or dependent evidence. Subagents do
not spawn agents, widen scope or manage external state. Simple tasks stay with Main.

## Source and initial audit (2026-09-09)

- Source: local operational `D:\Develop\agent-verification-lab\skills\visual-verification`.
- Upstream: private `ludi-uni/agent-verification-lab`, commit
  `dc7017b285d65b2e992b9e6da5dd2eb6e127da46`, Skill tree
  `84bed55062b25ff048e1aca386dd07eb3b6e8755`.
- The active `~/.codex/skills/visual-verification` was a Junction to that directory.
  Local master and GitHub master/HEAD matched. The canonical checkout and phase1
  worktree were clean, including untracked-file checks. The ignored `work/` acceptance
  report and `.worktrees/` remain in the original repository and are not imported.
- All 13 Skill files are adopted without code or instruction changes. Existing
  capture safeguards, numeric formatting and Unicode fixes are retained.
- The original repository is neither renamed, modified nor removed. This repository
  owns future published Skill snapshots; its updates do not flow back to the lab.

The Skill retains `%TEMP%\agent-verification-lab` evidence paths and existing JSON
schema names for compatibility. Optional speech scripts retain the existing
`C:\Users\leade\.cache\agent-verification-lab` defaults; on another machine pass
`-WhisperXVenvPath` and `-ModelCachePath`. WhisperX/models are not installed by these
scripts. An unavailable backend remains `REQUIRES_BACKEND`, not successful speech
verification. FFmpeg and FFprobe must be on PATH for media operations.

## Usage

Requires Windows, PowerShell 7 and Git. Clone the private repository using your
existing GitHub authentication; never put credentials in a clone URL or this repo.

```powershell
git clone https://github.com/ludi-uni/codex-settings.git
Set-Location codex-settings
pwsh -NoProfile -File .\scripts\install.ps1
pwsh -NoProfile -File .\scripts\check.ps1
```

For the initial migration of an existing, byte-identical Skill (including a
Junction), explicitly adopt it:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -AdoptExisting
```

The default destination uses `CODEX_HOME` if set, otherwise `$env:USERPROFILE\.codex`.
All three scripts accept `-CodexHome 'C:\path\to\.codex'` for an explicit destination.

After reviewing and committing changes, or obtaining an update:

```powershell
git pull --ff-only
pwsh -NoProfile -File .\scripts\update.ps1
pwsh -NoProfile -File .\scripts\check.ps1
```

`update.ps1` does not fetch, merge, push or install dependencies. Resolve a dirty
checkout before running it. It adds the new Skill to an existing managed visual-only
installation; an entirely new home still requires `install.ps1`. Existing v1 visual
installation metadata remains compatible. `check.ps1` is read-only: it checks both Skills' file hashes,
prints installed source commit/repository and backup location, validates the current
source, and checks that its commit and files match. Failure returns a nonzero exit;
missing FFmpeg/FFprobe is reported separately as unavailable. A commit-only change
also requires update to refresh the recorded provenance.

Start a new Codex task after installation to load the refreshed Skill instructions;
an already-running task may retain its previous loaded instructions.

## Safety and recovery

- Only the two explicitly listed Skills are installed, as copies independent of the checkout. The
  `config.toml`, policies, other Skills, authentication, sessions and plugin cache
  are not copied or rewritten.
- Before changing the installed Skill, require a clean committed repository,
  tracked payload only, required files/frontmatter, PowerShell parsing, supported
  file types, no nested links and a basic known-secret-pattern scan. This is minimum
  validation, not a substitute for reviewing executable changes or a comprehensive
  secret detector.
- Local installed changes stop an update. There is no force-overwrite option.
  Preserve/reconcile those edits explicitly before trying again.
- Validate both sources and destinations before any installed changes. Stage and
  hash-check both copies, record a per-Skill `.codex-settings.json`, recheck sources
  and destinations, then rename each old directory to a unique backup
  under `<CodexHome>/codex-settings/backup-*` and publish the stage. A per-home lock
  prevents concurrent runs of this installer. Caught publication failures restore
  all switched Skills in reverse order; if restoration itself fails, report the
  exact backup for manual recovery. Backups and failed stages are retained.
- The directory renames are not one crash-atomic transaction. A process or
  machine crash between them can leave a Skill absent or versions mixed: stop other installers,
  inspect `backup-*` / `stage-*` and move the exact backup back to
  `<CodexHome>/skills/<skill-name>` only when that path is absent. If a current
  installation exists, preserve it separately before restoring. A migrated Junction
  backup still points to the lab, so restoration restores that link. Never recursively
  delete its target. Other programs must not edit the Skill during an update.
- The old lab's `.agent-verification-lab-visual-verification.manifest.json` is retained
  untouched as legacy metadata. The new installer uses only its own in-Skill marker.
  Do not run both installers against the same Skill.

Secrets, PATs, API tokens, Codex config/auth files, captured media, caches and models
do not belong in this repository. `.gitignore` excludes common sensitive/generated
files; always review `git diff --cached` before committing. Asana management,
broad policy reorganization, frameworks, schedulers, queues and lab redesign remain
outside scope.

## Focused verification

```powershell
pwsh -NoProfile -File .\tests\test-installation.ps1
```

Tests use isolated temporary Git repositories and Codex homes: fresh install,
update/check, dirty and committed-invalid source preservation, ignored payload
refusal, concurrent lock refusal, local modification refusal and explicit Junction
migration, visual-only upgrade, preservation of the first Skill when the second
Skill is invalid or locally edited, and rollback after an injected second-Skill
publication failure. Fixtures are retained in TEMP for inspection. Actual image inspection
remains required when claiming visual behavior; installation/hash checks alone do
not establish capture, A/V or speech quality.
