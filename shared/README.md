# Shared resource ownership

`resources.json` is the selection manifest; shared payloads remain at their existing
authoritative locations. Moving existing sources would break the Codex installer or
project-relative links, so this directory does not contain duplicate skill trees.

| Resource | Authoritative editable source | pi delivery |
| --- | --- | --- |
| Common operating policy | `<CodexHome>/AGENTS.md`, before `## Multi-agent routing` | Generated global AGENTS plus pi main adapter; reapply after changes |
| Loop prevention, all models | `shared/loop-prevention.md` | Generated global AGENTS and runtime extension use the same source |
| visual-verification / project-management | This repository's `skills/` | Individual Junctions |
| External skill groups (optional) | Local checkouts named in `resources.json` `externalSkillGroups` | Group Junction per entry, retaining sibling links |

The Codex policy stays authoritative for compatibility; only its common prefix is
projected. A missing boundary fails closed instead of importing Codex routing.
The generated AGENTS file is not a second editable source. Project-local AGENTS
continue to be discovered by each agent using its native rules.

The existing Codex release installer intentionally retains its managed copies and
committed-source checks. This change adds no skill copies. Pi reads live checkout
content, including uncommitted edits; review edits before reloading pi. Existing
Codex release copies do not update until its own installer is run after a commit.

Optional external skill groups are declared in `resources.json` under
`externalSkillGroups` as `"group-name": "relative/or/absolute/path"`. Each group is a
directory whose subdirectories each contain a `SKILL.md`; the whole group is linked as
`~/.pi/agent/skills/<group-name>` so sibling references stay intact. An empty map (the
default) installs no external skills and produces no warnings. To link a one-off
directory without editing the manifest, pass `-ExternalSkillsRoot` to the installer;
it is linked as `skills/external`. Removing a manifest entry does not prune an already
installed link; back it up and remove it explicitly after review.
