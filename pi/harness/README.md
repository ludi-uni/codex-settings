# pi harness — official loading mechanisms

The official pi CLI owns startup, authentication, sessions, providers and RPC.
The harness consists of standard AGENTS, Skills and one small public-API Extension.
There is no internal SDK host, fixed-version check, staged runtime store or update manager.

## Apply / reapply

```powershell
.\scripts\migrate-pi-harness.ps1
```

On first migration, existing settings are backed up and the previously selected
compact resource set moves into `~/.pi/agent/settings.json`: four basic tools and
the installed Devin connector when present. Models, auth and UI preferences remain.
Optional packages stay installed but are initially deselected. Later reapplications
preserve subsequent user settings; they update managed instructions and links only.

The migration removes the old compact launcher directory from User PATH and pi-web's
startup PATH. It does not delete the retired profile or its sessions. Restart existing
terminal applications and pi-web after the first migration. Both then invoke official pi.

## Files and ownership

| Native location | Source |
| --- | --- |
| `~/.pi/agent/AGENTS.md` | Generated from `pi/harness/AGENTS.md` and `shared/loop-prevention.md` |
| `~/.pi/agent/skills/pi-workflow/` | Junction to this repository's short workflow entry and references |
| Shared visual/project skills | Existing Junctions, preserving sibling references |
| `~/.pi/agent/extensions/codex-settings/` | Existing small loop guard through the public Extension API |
| `settings.json`, `models.json`, `auth.json`, `sessions/` | Normal pi ownership; credentials are never copied to the repository |

Native Skill discovery includes only names/descriptions initially. The model reads
full instructions when needed. To explicitly load a workflow entry:

```text
/skill:pi-workflow
```

For a specific reference, use the official CLI append option:

```powershell
pi --append-system-prompt .\pi\harness\skills\pi-workflow\references\review.md
```

The optional `start-pi-harness.ps1` convenience launcher forwards directly to official
pi. It accepts the legacy `--workflow review` shorthand and translates it into the
native append option. It imports no SDK modules and is not needed by normal pi/pi-web.

## Updates

Update pi and pi-web using their normal commands. The instruction/Skill sources are
outside their installation directories and normally remain intact. There is no runtime
version pin or automatic rollback. If an update changes the loading conventions or
Extension API, inspect that specific incompatibility when it occurs. Reapply the
migration only if configuration/link repair is needed; do not add update infrastructure
preemptively. A third-party installer can still overwrite user files; backups are retained.

The tiny loop guard is the only executable integration that depends on pi's Extension
API. Removing it leaves the AGENTS/Skill instructions usable through standard pi.

## Checks

```powershell
pwsh -NoProfile -File tests/test-pi-harness-migration.ps1
node tests/test-pi-harness-runtime.mjs
node --test tests/test-swe-loop-guard.mjs
.\scripts\check-pi.ps1
```

The native runtime test uses an isolated fake provider and official pi CLI to verify
AGENTS/Skill discovery, project instructions, print and RPC without paid inference.
Old SDK-profile design/measurement documents are historical; they are not the current
startup contract. No guarantee of model task quality is implied by loading checks.
