# codex-settings

A reusable settings and skill-management base for AI coding agents on native
Windows. It installs a controlled set of Codex Skills and a pi (pi-coding-agent)
harness — shared instructions, skills, and a small loop-guard extension — via
Junctions and hash-verified copies, keeping credentials and mutable user config
outside the repository.

Native Windows **pi sharing** is now available alongside the existing Codex installer:
run `.\scripts\install-pi.ps1`, then `.\scripts\check-pi.ps1`.
See [pi setup and verification](pi/README.md), [shared ownership](shared/README.md),
and [Codex compatibility](codex/README.md). Existing Codex paths remain unchanged.

For the **compact harness using official pi loading**, use
`.\scripts\migrate-pi-harness.ps1` then ordinary `pi`.
See [migration, authentication, runtime and verification](pi/harness/README.md).
The migration removes the retired SDK launcher from command lookup. pi-web also
uses the official CLI; no version pin or custom update manager is required.

Personal Codex Skills and their controlled local installation. Manages only
`skills/visual-verification`, `skills/subagent-management` and `skills/project-management`; it does not import
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

## Asana-backed project management

Invoke `$project-management` for substantive project work with an existing Asana
boundary. `skills/project-management/SKILL.md` defines ownership, current-state
maintenance and hygiene; `references/operations.md` defines twelve semantic operations
from work-context lookup through follow-up and completion. These are instructions for
using existing connector tools, not an API wrapper or additional service.

Main alone decides and writes project state. Workers return implementation/research/
verification evidence and never write Asana. Routine bookkeeping needs no per-write
approval; explicit human priority, deadlines, exclusions and project boundaries are
preserved. No credentials, account IDs, queues, schedulers or role changes are installed.

The semantics were adapted from the existing local `asana-project-management` Skill
and its operation contracts, with Main calling the connector directly instead of an
Asana-writing coordinator. That separately installed legacy Skill is preserved. Select
this `$project-management` workflow for this ownership contract; do not run both PM
workflows for one milestone. If a session only exposes Asana to a coordinator, this
Skill reports unavailable synchronization instead of bypassing role permissions.

## Provenance

All content in this repository is authored by the repository owner. The
`visual-verification` Skill was originally developed in a separate private project
by the same author and is vendored here unchanged; this repository is now its
installation and distribution owner. The legacy `agent-verification-lab` name is
retained only in JSON schema identifiers and the default evidence/cache paths
(`%TEMP%\agent-verification-lab`, `$env:USERPROFILE\.cache\agent-verification-lab`)
for compatibility with previously installed copies. On another machine pass
`-WhisperXVenvPath` and `-ModelCachePath` to the optional speech script.
WhisperX/models are not installed by these scripts. An unavailable backend remains
`REQUIRES_BACKEND`, not successful speech verification. FFmpeg and FFprobe must be
on PATH for media operations.

## Usage

Requires Windows, PowerShell 7 and Git. Clone this repository using your
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
checkout before running it. It adds new Skills to an existing managed one- or two-Skill
installation; an entirely new home still requires `install.ps1`. Existing v1 visual
installation metadata remains compatible. `check.ps1` is read-only: it checks all three Skills' file hashes,
prints installed source commit/repository and backup location, validates the current
source, and checks that its commit and files match. Failure returns a nonzero exit;
missing FFmpeg/FFprobe is reported separately as unavailable. A commit-only change
also requires update to refresh the recorded provenance.

Start a new Codex task after installation to load the refreshed Skill instructions;
an already-running task may retain its previous loaded instructions.

## Safety and recovery

- Only the three explicitly listed Skills are installed, as copies independent of the checkout. The
  `config.toml`, policies, other Skills, authentication, sessions and plugin cache
  are not copied or rewritten.
- Before changing the installed Skill, require a clean committed repository,
  tracked payload only, required files/frontmatter, PowerShell parsing, supported
  file types, no nested links and a basic known-secret-pattern scan. This is minimum
  validation, not a substitute for reviewing executable changes or a comprehensive
  secret detector.
- Local installed changes stop an update. There is no force-overwrite option.
  Preserve/reconcile those edits explicitly before trying again.
- Validate all sources and destinations before any installed changes. Stage and
  hash-check all copies, record a per-Skill `.codex-settings.json`, recheck sources
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
- The old lab's `.agent-verification-lab-visual-verification.manifest.json` is accepted
  only when its known schema, owner, Skill, Junction mode and destination match. The
  installer moves it to a recoverable backup before publication and restores it if
  publication rolls back; unknown content is preserved by refusing the operation. The
  new installer uses only its own in-Skill marker. Do not run both installers against
  the same Skill.

Secrets, PATs, API tokens, Codex config/auth files, captured media, caches and models
do not belong in this repository. `.gitignore` excludes common sensitive/generated
files; always review `git diff --cached` before committing. New Asana infrastructure,
broad policy reorganization, frameworks, schedulers, queues and lab redesign remain
outside scope.

## Focused verification

```powershell
pwsh -NoProfile -File .\tests\test-installation.ps1
```

Tests use isolated temporary Git repositories and Codex homes: fresh install,
update/check, dirty and committed-invalid source preservation, ignored payload
refusal, concurrent lock refusal, local modification refusal and explicit Junction
migration, one-/two-Skill upgrades, preservation of earlier Skills when a later
Skill is invalid or locally edited, and rollback after an injected second-/third-Skill
publication failure. Fixtures are retained in TEMP for inspection. Actual image inspection
remains required when claiming visual behavior; installation/hash checks alone do
not establish capture, A/V or speech quality.

## External skills (optional)

The pi installer can link additional skill directories that live outside this
repository — for example private or work-in-progress skills — without copying
them. Declare groups in `shared/resources.json`:

```json
"externalSkillGroups": {
  "my-group": "../path/to/skills-directory"
}
```

Each group is a directory whose subdirectories each contain a `SKILL.md`. The
installer links the whole group as `~/.pi/agent/skills/<group-name>`, preserving
sibling references between skills. The default empty map installs nothing and
emits no warnings. For a one-off link without editing the manifest, run
`scripts/install-pi.ps1 -ExternalSkillsRoot 'C:\path\to\skills'`; it is linked
as `skills/external`. Removing a manifest entry never deletes an installed link
automatically — back it up and remove it explicitly after review.

## License

MIT — see [LICENSE](LICENSE).
