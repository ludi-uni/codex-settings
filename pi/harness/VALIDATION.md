# Validation — 2026-09-20

Historical SDK-profile measurements below. The current implementation uses the
official CLI, native AGENTS/Skills, and public Extension API instead; see README.md.
Current native-layout migration and official CLI print/RPC tests pass. No fixed
runtime version or custom update manager is active.

Candidate: native Windows, installed pi 0.85.1, separate
`~/.pi/profiles/compact` profile. Baseline remains
`~/.pi/agent`. No commit/push or automatic pi-web promotion.

## Contract checks

- Migration fixture PASS: preview without writes, isolated source/destination,
  nested/aliased overlap refusal, state-directory reparse refusal, file/target
  manifest verification, repeat no-op, edited-file refusal and backup, invalid state
  refusal, and injected publication rollback preserving the Junction target.
- Runtime fixture PASS with the installed SDK and a synthetic local provider:
  discovered pi-workflow; project AGENTS preserved; four default tools;
  print context verified; RPC get_state/get_commands/new_session verified;
  missing model refused without fallback; source auth unchanged and no copied auth.
- Existing guard: six unit cases PASS and actual CLI synthetic cycle stops after
  seven A/B/C calls, without a paid provider request.
- Real candidate: seven skills, two extensions, selected `devin/swe-2-high`,
  existing authentication recognized, zero resource diagnostics.
- Real native TUI started and displayed candidate AGENTS/skills/extensions and model;
  exited with Ctrl+C. No prompt or paid model request was sent in this check.
- Source pi settings/auth/models and Codex AGENTS/config SHA-256 unchanged after
  migration, inspection and local inference.

## Effective startup footprint

Measured with the same repository cwd, project executable resources disabled and
without sending an inference request. Counts are JavaScript string lengths, not
tokenizer token counts or claimed billing savings. Tool definitions include SDK
metadata. Additional task history, project files and on-demand documents add context.

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Active tools | 25 | 4 |
| Loaded extensions | 11 | 2 |
| Discovered skills | 15 | 7 |
| Base system prompt characters | 16,805 | 9,243 |
| Active tool definition characters | 58,173 | 3,909 |

The reduction trades automatic access to baseline optional tools for explicit
selection. It does not prove a higher task-completion rate or lower end-to-end cost.
Run `start-pi-harness.ps1 -PiArgs @('--inspect','--offline')` for current exact counts.

## One real local-model task

Model: `freetoken/Qwen3.6-35B-A3B-NVFP4`, explicitly selected for this run only.
An isolated order-total fixture had a failing quantity calculation and an unrelated
sentinel. The task asked for investigation, a focused fix and verification without
editing tests. It did not replay any user production-session commands.

- Initial tests failed as expected.
- Four tool calls: read, read, edit, PowerShell; four inference turns.
- Agent corrected quantity multiplication, retained shipping and ran the tests.
- Independent test rerun passed; tests and sentinel were byte-preserved.
- Elapsed about 15 seconds including verification; process exit 0, no timeout.
- Evidence retained in `%TEMP%/pi-compact-live-E8bY3d/` (report, event log, fixture).

This is one successful small task, not a controlled multi-run A/B quality benchmark.
An additional local review completed without editing, but it did not read the
explicitly requested workflow reference. Consequently the launcher also supports
deterministic `--workflow` preloading; the offline runtime test verifies review
content reaches the model while the code-workflow body remains unloaded. Default
autonomous knowledge selection is still dependent on model behavior.

Long investigations, autonomous knowledge selection, image/tool backends, different
model families and production pi-web usage still require task-specific acceptance.
The harness deliberately remains separately selectable until that evidence exists.
