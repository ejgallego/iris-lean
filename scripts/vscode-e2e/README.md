# Real VS Code acceptance for the Iris widget

Runs the widget in a real, isolated, headless VS Code with the installed Lean extension and its real infoview. That's the path users get, and the browser harness does not exercise it.

```bash
# from the worktree root, after the usual widget build (see docs/vir-demo-runbook.md)
TMPDIR=$PWD/.tmp node scripts/vscode-e2e/widget-vscode.test.mjs [path/to/Iris]
```

Requires Linux with desktop VS Code (default `/usr/share/code/code`), `Xvfb` on
`PATH`, Node.js 22 or newer, and installed `leanprover.lean4` and
`tamasfe.even-better-toml` extensions under `~/.vscode/extensions`. Build the Iris
widget and install its matching runtime first, as in the
[demo runbook](../../docs/vir-demo-runbook.md). The validated extension version is
`leanprover.lean4 0.0.240`; Node 24 was used for the recorded run. This gate is
local-only and is not part of CI.

The default `Iris` path is this worktree's. Exit status is 0 only if every check passes. Each run writes
`$TMPDIR/vscode-e2e-runs/<timestamp>/` (override with `IRIS_E2E_RUNS`) containing `results.json`, a screenshot per check, `code.log`, and the throwaway profile.

How it works:

- `vscode.mjs` starts its own `Xvfb -displayfd` display and launches `/usr/share/code/code` (override
  with `IRIS_E2E_CODE`) with a fresh `--user-data-dir` and `--extensions-dir` in that run directory.
  `leanprover.lean4` and its dependency `tamasfe.even-better-toml` are symlinked from
  `~/.vscode/extensions`. Your own profile, settings and window are never touched. VS Code runs in
  its own process group and is killed on exit.
- `driver/` is a test-only extension. It exposes a loopback HTTP endpoint for opening files,
  finding marker comments, moving the cursor, typing, reverting and reading diagnostics, all
  through the real VS Code API.
- `cdp.mjs` and `infoviewEval` read the infoview webview over the Chrome DevTools Protocol.
  The webview is an out-of-process iframe target, and the script evaluates in its execution contexts.

The test never saves: typing edits only the buffer, which is reverted before VS Code closes. It
uses the real workspace and its `.lake`, so a stale build makes the Lean server rebuild imports,
and it waits for any concurrent `lake build`.

Checks (`widget-vscode.test.mjs`): HeapLang store and load contents with the `:` separator; native
hover popup type (`l : Loc`); both SpinLock positions; no panel on an ordinary goal; two split
cards; collapse and card DOM identity across a cursor move in the same proof state and across a
typing edit.


Round A follow-up adds actual editor-destination verification for native definition
navigation (synthetic Ctrl-click dispatched inside the real webview), the Heap
postcondition, and explicit SpinLock before/after and typing DOM-identity assertions.
The store check also records the normal Tactic state's built-in diff spans.
These checks do not claim physical pointer or keyboard accessibility coverage.
The harness is committed here; generated profiles, logs and screenshots remain
under the run-output directory and must not be added to Git.

Round B adds Heap store and SpinLock store resource-status checks (13 checks total),
including the old/new proposition text, preserved resources and native new-side
terms. Cursor waits identify the selected tactic so the new after-view cannot
make a stale snapshot accidentally satisfy the next position's predicate.

Round G removes the guided tour and its four checks. The remaining 19 checks
cover native terms/navigation, annotations, split distribution, mask/invariant
folding, before-state labelling and continuity while moving or typing.
