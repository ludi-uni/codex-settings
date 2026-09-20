# Compact pi harness — design proposal

Superseded architecture note: the user chose official pi AGENTS/Skill/Extension
loading instead of a custom SDK host. The current implementation is documented in
`harness/README.md`; isolated SDK hosting and managed runtime updates are not used.

Status: proposal, 2026-09-20. No active profile, provider, credentials or runtime was
changed during this investigation. This document is a design, not evidence of
improved task performance.

Implementation update: the user subsequently approved this design. The first
separate candidate is implemented; see [usage and migration](harness/README.md)
and [observed validation](harness/VALIDATION.md). The design below records the
original decision boundary, not the current deployment status.

## Objective and boundary

Build a native Windows pi harness with a small mandatory context, reliable access
to relevant knowledge, bounded execution, and completion supported by evidence.
Keep existing Codex installation ownership and shared skill sources unchanged.
Use installed pi contracts; do not port Codex-specific tool/model assumptions.

Provisional first workload: code investigation and localized fixes, based on the
reported loop incident. The user has been asked whether coding, visual authoring,
or general research should be the first evaluation target. The core should remain
useful to all three; each needs different acceptance tasks.

## Evidence from the current installation

- Installed pi is 0.85.1. Global AGENTS is about 4.4 KB. Its size alone does not
  establish excessive total model input: tool schemas, extension injections,
  project context and conversation must be measured separately.
- User settings configure nine packages covering providers, MCP, web access,
  autonomous goals, compression, subagents, images/computer use and pi-web.
  Configuration does not prove every package is active or that it caused failure.
- The generated adapter still says delegation is not installed, conflicting with
  the configured subagent package. Installed capabilities must be discovered rather
  than asserted from stale prose.
- The main problematic session contains 618 tool results, 52 tool errors, up to
  25 occurrences of one exact tool input and three loop-guard stop messages.
  These are whole-session counts, not a benchmark or proof of a single cause.
- Native skills already load names/descriptions first and full instructions on
  demand. The existing MCP adapter also has a discovery/proxy approach. Reuse
  these mechanisms before inventing another search service.
- Earlier acceptance proved resource loading, provider smoke tests and mechanical
  loop stopping. It did not establish end-to-end task quality.

## Recommended architecture

| Layer | Always present | Loaded when needed | Owner |
| --- | --- | --- | --- |
| Core | Short pi AGENTS: scope, permissions, evidence, completion, knowledge lookup, recovery | None | pi-specific source in this repository |
| Knowledge | Compact task-to-skill index | Relevant workflow, then exact domain references | Shared existing skills plus small pi-specific workflows |
| Execution | Native read/write/edit/PowerShell and small control extension | Required MCP/browser/vision/delegation tools | Native pi and selected installed extensions |
| Work state | Current objective, next action, acceptance and unresolved issue | Source files and raw evidence | Current session; durable note only when resumption needs it |

Aim for roughly 600–1,000 added core instruction tokens; this is a design target,
not a measured total prompt budget. Never shorten by removing task-critical rules.
Measure effective startup instructions and tool-schema overhead before setting a
hard budget. Keep provider-specific settings separate from general instructions.

### Core behavior

1. Inspect relevant state and establish the smallest sufficient task boundary.
2. Select only the knowledge needed for the next decision. Confirm actual tools.
3. Act, inspect the result, and update the current hypothesis/next action.
4. When no new evidence appears, change the approach or state the limitation.
5. Verify the requested behavior and stop at acceptance; report limits honestly.

This is a working loop, not a mandatory multi-stage ceremony for every small edit.
Do not require a plan file, reviewer, subagent or complete skill load for trivial work.

### Knowledge retrieval

- Route from task/symptom to a short workflow entry, then follow only relevant links.
- Give each entry a clear trigger, inputs, procedure, exit condition and references.
- Preserve one owner for each fact. Link existing visual/rigging knowledge in place;
  keep related rigging directories together to preserve relative references.
- Start with native Skill discovery and ordinary file search. No vector database,
  background crawler, broad RAG service or automatic memory writer in version one.
- Distinguish established knowledge from temporary hypotheses and current results.
  Save new reusable knowledge only with the user's existing authorization policy.

### Runtime control

- Keep extensions small. Reuse pi's real tool/resource APIs rather than fork pi.
- Retain a bounded repetition safeguard, but test legitimate polling, build retries
  after edits, parallel calls and cancellation to avoid stopping useful work.
- Store only compact execution state/fingerprints; raw logs remain external evidence.
- Use single-agent execution as the initial baseline. Add delegation only when a
  bounded independent task or review demonstrably helps; no default agent tree.
- Treat automatic continuation and context compression as separate optional features.
  Start the comparison without overlapping control layers, then add them individually
  if they improve measured outcomes. Do not uninstall current user packages.
- Prefer user-visible provider/model selection. Do not silently switch models or
  send a task to another service when the current model stalls.

## Rollout choice

Recommended: build a separately selectable candidate profile/launcher, preserving
the current profile as a baseline and fallback. Select resources explicitly and
verify pi-web launches the same candidate before promotion. Determine authentication
reuse from the installed runtime; do not copy credentials into the repository or
assume a second agent directory automatically inherits login state.

Alternative: simplify the current global profile in place. This is quicker to launch
but changes daily-use tools and makes controlled comparison and rollback harder.

The material decision before implementation is the initial workload and whether the
candidate is separately selectable or replaces current global behavior. No live
package removal, provider/default changes, restart or paid benchmark is part of this
design-only pass.

## Acceptance and evaluation

Use a small fixed set of tasks with independently observable expected outcomes:

- Locate a relevant implementation in an unfamiliar repository.
- Establish that an assumed feature is absent and propose/implement the actual change.
- Make a localized fix and pass the focused regression while preserving unrelated edits.
- Recover from a missing command/tool without repeating the same failing request.
- Retrieve a domain rule and apply its cited constraint correctly.

Compare baseline and candidate on clean task snapshots with the same model, prompt,
tools needed by the task and starting state. Use more than one run where variance
changes the conclusion. Record task success, user interventions, repeated calls,
input/output tokens, elapsed time and scope violations. A shorter prompt or fewer
calls alone is not success. Avoid replaying the user's mutating session commands.

Run offline contract/regression tests first. Real model trials require a concrete
small task set and cost envelope before execution. Report stochastic results and
model differences honestly; the harness cannot guarantee a weak model's reasoning.

Promotion requires resource/protocol checks, correct knowledge lookup, complete
task outcomes, and no material regression against the baseline. An intentional stop
is evidence of bounded execution, not proof that the original task succeeded.

## First implementation slice

1. Measure effective resources; replace stale capability claims with actual discovery.
2. Author one short pi core and a small workflow index, retaining shared sources.
3. Add the separately selectable launcher/profile and focused control/retrieval checks.
4. Run the agreed comparison and revise only demonstrated weak points.
5. Promote to ordinary pi/pi-web startup with a recoverable backup after acceptance.
