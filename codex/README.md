# Codex compatibility boundary

Existing Codex management remains at `../skills/` and `../scripts/install.ps1`,
`update.ps1`, `check.ps1`, `common.ps1`. No files are moved and no wrapper is needed.

`~/.codex/config.toml`, authentication, sessions, memories, plugin settings, role TOML
files and `multi-agent-policy.md` stay Codex-only. `subagent-management` stays on
the existing Codex installation path; pi does not acquire Codex collaboration tools.
Only the common prefix of global AGENTS is consumed read-only by the pi installer.
