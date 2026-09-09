---
name: subagent-management
description: Help Main delegate bounded independent tasks to subagents, collect evidence, resolve conflicts, and integrate results when parallel agent work is requested or justified. Skip simple tasks that Main can finish directly.
---

# Subagent Management

Use the available Codex collaboration tools and current repository instructions.
This Skill supplies an operating procedure, not a scheduler or permission to expand
the task. If delegation is unavailable or prohibited, Main does the work locally
and reports that limitation. Do not create user-visible tasks as a substitute.

## Main owns the task

Main alone decomposes and delegates work, changes assignments, resolves conflicts,
integrates results, and makes final decisions and acceptance claims within the
user's authorization. A subagent's completion is evidence, not final acceptance.
Subagents do not spawn other agents, expand to project-wide changes, alter shared
policy, or manage external projects/services. A need for any of these goes back
to Main; it does not grant Main additional user authorization either.

## Decompose before dispatch

Briefly state the requested outcome, acceptance evidence, scope/non-goals and
invariants. Break work into independently answerable questions or bounded changes
with explicit dependencies. Keep a small assignment list in the conversation:
task ID, owner, allowed files/questions, dependency and status. No queue or durable
planning artifact is needed for a small task.

Delegate only when the expected benefit exceeds context, coordination and review
cost. Main retains a useful independent activity, such as implementing a separate
change or preparing integration. Do not delegate a trivial command just to use agents.

Before dispatch, check that no active agent or Main is doing the same work. Assign
each question/change once. A deliberate independent review needs a specific risk
and a separate review objective; it is not permission to duplicate implementation.

## Select and bound agents

Use the smallest capable available role for the actual need: an explorer/researcher
for read-only evidence, an implementer for a bounded change, or a mechanic for
specified checks. Follow current role/model policy and explicit user choices; do
not hard-code model names or assume unavailable roles. Main normally reviews once;
extra architecture or review agents need a concrete unresolved question.

Normally use at most two concurrent subagents and one writer, subject to lower
runtime limits. Parallelize distinct read-only questions or work on disjoint files
with stable interfaces. Serialize dependencies, shared mutable state, overlapping
edits and operations on the same external resource. Read-only work also waits if
its evidence is being changed by another agent. Never race speculative fixes.

Pass a compact assignment, preferably with fresh or limited history when supported:

```text
Task ID and objective:
Allowed paths/questions; read-only or exact write ownership:
Non-goals and prohibited actions:
Inputs: paths/symbols, revision or snapshot, relevant instructions:
Dependencies and acceptance evidence:
Return: conclusion, evidence locations, changed files, checks, uncertainty/blockers:
You are not alone in this workspace. Preserve user and other agents' changes.
Do not spawn agents, widen scope, commit/push/deploy, or write external state.
Return missing evidence or boundary decisions to Main instead of guessing.
```

Send only needed excerpts and evidence references. Do not forward the entire chat,
large successful logs, secrets, or unrelated private context. Let the agent fetch
the specific missing input within its scope. If inherited context is required,
limit it to the relevant turns and still restate the task boundary.

## Collect and resolve

Track returned agent IDs and assignment status. Use completion notifications or
bounded waits instead of repeated short polling. Continue Main's independent work
while agents run. If an agent blocks, fails, or times out, collect partial evidence
and decide whether to narrow, reassign or finish locally. Stop/interrupt its previous
work before assigning the same work elsewhere; do not leave overlapping workers.

Require each result to identify what was inspected/changed, exact checks and their
outcomes, revision/snapshot, remaining uncertainty and any scope boundary reached.
Missing evidence is an incomplete result. Do not treat confidence or a passing
command as proof of an externally observable outcome.

For conflicting results, compare scope, inputs, revisions and reproduction steps.
Main establishes the current revision and relevant dirty-state snapshot, then
inspects the disputed evidence or runs the smallest discriminating check against it.
Do not vote, silently combine incompatible claims, or automatically launch another
reviewer. Stop dependent changes until the conflict is resolved; ask the user only
when a missing requirement or authorization controls the decision.

## Integrate and accept

Main reviews scoped diffs and evidence against the original acceptance criteria,
checks that unrelated work was preserved, and performs proportionate integration
verification. Subagents never make final project acceptance or lifecycle decisions.
Reject out-of-scope results rather than adopting them silently; preserve unrelated
edits and investigate ownership before any reversal. Report integrated outcomes,
actual checks and remaining limits, then stop when acceptance passes.
