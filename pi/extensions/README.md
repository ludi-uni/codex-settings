# Pi extensions

This directory is linked to `~/.pi/agent/extensions/codex-settings`.
`index.js` contains the model-independent loop guard. Pi discovers this entry through the
existing Junction. Restart pi or `/reload` to load it into an existing session.

For every provider/model, the guard adds progress instructions and aborts after
three identical results from the same tool and arguments within the last twelve
completed tool results. Interleaved A/B/C cycles are detected; changed output for
that same input resets its repetition streak. Only hashes are retained in memory.
The stop explanation is displayed and recorded in the session. A new manual/RPC
user input resets the guard; extension-generated followups do not. Already-running
parallel sibling tools cannot be undone.

The single editable instruction source is `shared/loop-prevention.md`. The installer
includes it in `~/.pi/agent/AGENTS.md`; the extension injects it when absent (including
sessions started without context files). Reapply `scripts/install-pi.ps1` after edits.

This is a bounded mitigation, not a fix to the model's reasoning or connector.
Intentional identical polling can also stop. Paraphrased queries, changing outputs,
cycles longer than the window and repetition inside one model response are outside
this detector. Do not treat it as a general safety or permission boundary.

Verification:

```powershell
node --test tests/test-swe-loop-guard.mjs
node tests/test-swe-loop-runtime.mjs
```

The runtime test uses the installed pi CLI, a temporary home and a local synthetic
provider. It makes no paid Devin request and verifies actual abort and stop-message
delivery, not just hook return values. The original incident log also matched the
detector in a read-only replay without executing its commands.

## Future delegation

Pi discovers direct `.ts`/`.js` files and subdirectory `index.ts`/`index.js` entries.
Keep the existing guard entry when adding a real delegate extension.
For delegate tools, implement pi's `registerTool` API using the installed package's
`docs/extensions.md` and `examples/extensions/subagent/` contracts at that time.
Explicitly define model selection, tool restrictions, cancellation, cwd/session
isolation and returned evidence. The sibling agents Markdown is an application
contract, not a built-in pi agent configuration schema.
