# Native Windows pi foundation

Current operation: use `scripts/migrate-pi-harness.ps1` and official `pi`.
The compact instructions now live in the normal pi agent directory; see
[current harness documentation](harness/README.md). The audit below records the
earlier shared-foundation setup and is not a fixed version requirement.

Verified against installed `@earendil-works/pi-coding-agent` **0.85.1**, Node
24.19.0, PowerShell 7 and the Windows npm `pi.cmd`/`pi.ps1` launchers on 2026-09-17.
The installed package's README, `docs/settings.md`, `docs/skills.md`, `docs/rpc.md`
and resource loader are the specification used here. No WSL, new npm dependencies,
model changes or authentication changes are required.

```powershell
.\scripts\install-pi.ps1
.\scripts\check-pi.ps1
```

Restart `pi` or use `/reload` after source changes. Skills can be invoked as
`/skill:visual-verification`, `/skill:project-management`, etc.

## Actual installation

```text
~/.pi/agent/
  settings.json                 existing native pi settings, unchanged
  auth.json / models-store.json / sessions/   unchanged
  AGENTS.md                     generated common policy + agents/main.md
  agents/                       Junction -> repo/pi/agents
  extensions/codex-settings/     Junction -> repo/pi/extensions (all-model loop guard)
  skills/visual-verification/    Junction -> repo/skills/visual-verification
  skills/project-management/     Junction -> repo/skills/project-management
  skills/<external-group>/       optional Junctions -> declared external skill dirs
  codex-settings/pi.json         generated ownership/hash/source record
  codex-settings/install.lock    exclusive installer lock
  codex-settings/backup-*/       retained replaced entries when needed
```

The original user settings select `openai-codex/gpt-5.5` and the read/bash/powershell/
edit/write tools. These values are neither templates nor installer defaults; the
installer does not overwrite them. Main agent model/tool settings belong in pi's
real `settings.json`; there is no invented `mainAgent` or `agents` settings key.

`agents/main.md` contributes instructions to AGENTS. Coder, vision and reviewer
Markdown files are inactive future role contracts. They are not slash commands or
built-in registered agents. The extensions directory now includes a model-independent
loop guard; see [its behavior and tests](extensions/README.md). No delegation runtime
is implemented by this guard.

## Source selection and safety

The default agent directory honors `PI_CODING_AGENT_DIR`, otherwise
`$env:USERPROFILE/.pi/agent`. `-AgentDir`, `-CodexHome` (also honors `CODEX_HOME`),
and `-ExternalSkillsRoot` support explicit paths. Optional external skill groups
are declared in `shared/resources.json` under `externalSkillGroups`; explicit
missing paths fail. Absent optional sources are reported rather than created or
fetched.

The installer checks every source and destination conflict before publishing links.
Existing correct Junctions and unchanged generated content are no-ops. Unknown or
locally edited entries stop installation. After reviewing a conflict, use
`-BackupConflicts` to move it to a unique backup, then install the desired entry.
Managed AGENTS updates also retain the old file in a backup. Never edit the generated
AGENTS; edit its source and reapply. `AGENTS.override.md` is refused because pi would
load it instead of AGENTS. Existing destination parent links are refused.

Junctions share directories on native Windows without requiring file-symlink
privileges. No Symbolic Links, hard links or skill copies are created. AGENTS is a
generated composition because Codex routing must be excluded and pi instructions
added. Mutable settings and auth files stay ordinary user-owned files. Source files
are never rewritten by the installer. Linked content is live; do not delete its target.

Caught publication errors roll back created entries and restore backups; the sequence
is not crash-atomic. After process/power failure, inspect the exact backup and destination
before moving anything. Stop other installers/editors while applying. Backups are never
automatically deleted. Removed manifest entries are not pruned from the user profile.

## Verification and limitations

`tests/test-pi-installation.ps1` uses isolated temporary homes; no real settings change.
`check-pi.ps1` loads installed pi's actual resource loader, asserts common AGENTS and
expected skills without diagnostics, then starts the real CLI in offline RPC mode
with an ephemeral session and requests `get_commands` / `get_state`. It never sends
a prompt or makes a paid inference call. For a non-npm installation, pass
`-PiPackageRoot` pointing to the actual package containing `dist/bundle/cli.js`.

Acceptance on this machine: seven skills discovered; global AGENTS loaded; zero skill
diagnostics; CLI skill commands registered; original provider/model retained. This
proves startup/loading, not model execution of each skill, image inspection or Asana/MCP
availability. Shared instructions do not install Codex-only connectors or tools.

During final preservation checks, the user settings independently gained package
entries for `npm:pi-mcp-adapter` and `npm:pi-web-access`. They were preserved; this
installer never writes settings. The startup acceptance above preceded those entries
and does not certify those packages. Codex AGENTS/config and pi auth hashes remained
unchanged. Native pi startup can perform its own bookkeeping and load configured
extensions; the checker is an observation tool, not a sandbox for extension code.

Next multi-agent step: implement a bounded extension under `extensions/`, explicitly
load role contracts, select installed model IDs and allowed tools, isolate sessions,
define cancellation/timeouts and return evidence to main. Vision requires a verified
image-capable model. Do not infer runtime support from these Markdown files.
