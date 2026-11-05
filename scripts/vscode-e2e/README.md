# Real VS Code acceptance for the Iris widget

Runs an isolated, headless desktop VS Code with the installed Lean extension
and its real infoview. Build/install the widget first as in the
[demo runbook](../../docs/vir-demo-runbook.md), then run from the checkout root:

```bash
TMPDIR=$PWD/.tmp node scripts/vscode-e2e/widget-vscode.test.mjs [path/to/Iris]
```

Requires Linux, desktop VS Code (`/usr/share/code/code`, override `IRIS_E2E_CODE`),
`Xvfb`, Node.js 22+, and `leanprover.lean4` plus `tamasfe.even-better-toml` under
`~/.vscode/extensions`. Validated with Lean extension `0.0.240` and Node 24.
This gate stays outside CI. The default workspace is this checkout's `Iris/`.

Exit 0 means every check passed. Output goes to
`$TMPDIR/vscode-e2e-runs/<timestamp>/` (override `IRIS_E2E_RUNS`): `results.json`,
screenshots, `code.log` and a disposable profile. Never commit these outputs.
`vscode.mjs` owns an Xvfb display, profile, extension directory and process group;
it closes them on exit without using the presenter's profile or window.
`driver/` exposes test-only editor operations over loopback; `cdp.mjs` reads the
real infoview webview through Chrome DevTools Protocol.

Checks cover HeapLang and SpinLock contents, native hover and actual definition
destinations, quotation shortening, mask/invariant details, in-place resource and
goal annotations, split distribution, native diff spans, closed/ordinary goals,
and collapse/DOM continuity across cursor movement and typing. Quiet resources
and continuations must stay unhighlighted. The gate records ordinary Tactic-state
diff spans for comparison. Synthetic pointer input does not establish physical
pointer or full keyboard/accessibility coverage.

The tour is absent in the default document. Later checks type its optional import
and panel declaration into the unsaved buffer, exercise Next/Prev/manual movement
and shifted markers, and verify that reverting hides it again. No buffer is saved.
The workspace and `.lake` are real: finish builds before running this gate.
