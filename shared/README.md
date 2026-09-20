# Shared resource ownership

`resources.json` is the selection manifest; shared payloads remain at their existing
authoritative locations. Moving existing sources would break the Codex installer or
project-relative links, so this directory does not contain duplicate skill trees.

| Resource | Authoritative editable source | pi delivery |
| --- | --- | --- |
| Common operating policy | `<CodexHome>/AGENTS.md`, before `## Multi-agent routing` | Generated global AGENTS plus pi main adapter; reapply after changes |
| Loop prevention, all models | `shared/loop-prevention.md` | Generated global AGENTS and runtime extension use the same source |
| visual-verification / project-management | This repository's `skills/` | Individual Junctions |
| 2d-rigging-knowledge / Live2D / Cast2D knowledge | Existing `2.2.Cast2D_Parametric_Sprite/.agents/skills/` checkout | Group Junction, retaining sibling links |

The Codex policy stays authoritative for compatibility; only its common prefix is
projected. A missing boundary fails closed instead of importing Codex routing.
The generated AGENTS file is not a second editable source. Project-local AGENTS
continue to be discovered by each agent using its native rules.

The existing Codex release installer intentionally retains its managed copies and
committed-source checks. This change adds no skill copies. Pi reads live checkout
content, including uncommitted edits; review edits before reloading pi. Existing
Codex release copies do not update until its own installer is run after a commit.

The rigging group currently has five skills; adding skills there makes them discoverable
in pi too. To relocate it, pass `-RiggingSkillsRoot` and explicitly back up the old link
after reviewing the new source. Passing an empty root skips adding it; it does not
remove an already installed link. No automatic pruning or source deletion is performed.
