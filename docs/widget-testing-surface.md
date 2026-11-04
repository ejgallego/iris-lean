# Widget testing and use-case surface

Current local checkpoint: Lean 4.35 / VIR `81de859a`; lifecycle fixes at
`278633ae`, followed by the interactive browser demo. The live demo is served by
`node scripts/widget-browser-smoke.mjs --demo`; see the
[runbook](vir-demo-runbook.md).

## Coverage map

| Layer | What is exercised | Limit |
| --- | --- | --- |
| Typed ingress | Actual elaborated Iris goals via `parseIrisGoal?`; persistent/spatial contexts, canonical text, contextual types; HeapLang store/read and SpinLock release states | Generic BI, one sequential heap program and one invariant proof |
| Tagged terms | Nested tags, plain-text fallback, distinct repeated occurrences, saved `n`/`m`/`r` binder contexts; locations embedded in HeapLang syntax | One HeapLang custom-delaborator regression; no broad notation corpus |
| Runtime/package | 47 package-member hashes, component factory, SSR loading shell, generated fingerprint, real imported asset/package RPCs | SSR alone does not run effects |
| Live browser | Contexts, two-goal split, binder inspection, empty ordinary goal; keyboard Enter, IDs, ARIA/close isolation; store/load changes and preserved frame; SpinLock persistent invariant, ghost token, later removal, mask and closing update | Nine proof positions in `WidgetDemo.lean`; no parallel client program |
| Async behavior | Held same-panel refresh, cursor movement and typing preserve card DOM/collapse and disable inspection; new semantic epoch; refresh failure/recovery; moving outside Iris; late outcomes, unmount, Strict Mode, package reuse, delayed startup | No long-session stress, full editor focus/scroll test or latency budget |
| Errors/cancellation | Native error message/code, string/unknown rejections, malformed reply, missing method, bad package fingerprint; cancellation observed by Lean on selection/close | Cancellation is cooperative; the slow server probe is test-only |
| Presentation | Light/360px/14px text, dark/320px/22px text, high-contrast/280px/28px text; no horizontal overflow, configured font size, screenshots | Three selected combinations, not the full Cartesian product; simulated theme variables |
| Demo controls | Generic proof positions, split expansion, contextual inspection, theme/font/width changes preserving inspection; HeapLang store/read walkthrough | Browser host adapter, not VS Code integration |

The browser acceptance also deliberately injects transport/decoding faults;
those tests are distinct from real server errors and the cancellation probe.

The HeapLang fixture exposed a real tag-provenance bug: selecting the program's
`l` displayed the WP postcondition instead of `l : Loc`. In
`Iris/HeapLang/Notation.lean`, `unexpVal` delaborated the embedded value with the
top-level `PrettyPrinter.delab`, starting a separate position/info map. It now
uses `SubExpr.withAppArg Delaborator.delab` in the enclosing delaboration.
The browser test checks the actual expression/type returned for that location,
the mask, and the postcondition binder, as well as canonical text and resource
changes. It does not infer semantic identity from token spelling.

The separate notation gallery has broader paper-inspired specimens and 90
layout combinations. Those are manually authored design data. Its passes do not
establish live Iris semantics or widget acceptance.

## Highest-value additions

1. **Broader weakest-precondition states:** the demo now covers `wp_store` and
   `wp_load`, points-to ownership, a preserved frame, sequencing, masks and a
   postcondition binder. Add fractional/persistent ownership and loads beneath
   more complex evaluation contexts from `IrisTest/HeapLang/HeapTactics.lean`.
2. **Invariants and ghost state:** `SpinLock.release_spec` is now copied as a
   complete proof with pause points before/after its atomic store. Extend to
   acquire/CAS branching and a client using the lock.
3. **Scale and syntax:** large spatial/persistent contexts, long induction
   hypotheses, mixed ordinary/Iris goals, Unicode, and user-defined notation.
4. **Editor lifetime:** real VS Code server restart, expired references, multiple
   files/panels, and focus/scroll behavior across edits. The current browser
   adapter substitutes the editor context; it does not establish these behaviors.
5. **Accessibility and performance:** complete keyboard traversal, a screen
   reader, actual VS Code themes/zoom, measured latency and long-session memory.

Native infoview hover/navigation has an experimental comparison below; it is
not enabled in the production renderer. Mathematical presentation remains
design work.

## Automation status

The recorded widget build, `lake test`, runtime smoke and browser matrix passed
locally. The new demo path was also exercised against its running server and the
normal browser acceptance was rerun after the shared harness change.

For the HeapLang addition, validation includes
`lake build IrisTest.ProofMode.WidgetDemo IrisTest.HeapLang.HeapTactics`,
`lake test`, and `node scripts/widget-browser-smoke.mjs`. The running demo's
three Heap selectors and `l`/`E`/`r` inspections were also checked in Chromium.
The generic-only browser run previously made 57 RPC requests; the extended run
makes 74 in the default configuration. Counts describe executions, not coverage
percentages.
The extended acceptance also passed with
`IRIS_WIDGET_WIDTH=320 IRIS_WIDGET_FONT_SIZE=22 IRIS_WIDGET_THEME=dark IRIS_WIDGET_PACKAGE_DELAY_MS=500`
and with `IRIS_WIDGET_WIDTH=280 IRIS_WIDGET_FONT_SIZE=28 IRIS_WIDGET_THEME=contrast`,
each using the same `node scripts/widget-browser-smoke.mjs` command.

The subsequent continuity gate made 84 requests. The SpinLock extension makes
96 in the default run; it checks the canonical persistent/spatial terms, ghost
resources, cell update and later removal, reduced mask/closing update, contextual
`l`/`γ`/`b` inspections, and narrow layout. These counts are historical run
observations; the assertions are the acceptance contract.
The extended gate passes in all three configurations above (96 requests each),
and the final `lake test` passes with only the existing redundant-private warning
in `IrisTest/ProofMode/Widget.lean`.

Repository CI builds/tests/lints Iris and IrisMath. It does **not** currently
invoke `widget-runtime-smoke.mjs`, `widget-browser-smoke.mjs`, or the notation
gallery smoke test. There is no fresh remote CI verdict for this local branch;
the full IrisMath build has not been rerun in this widget work.

The core browser regression gate is:

```bash
# From Iris/, after installing the pinned runtime:
lake build IrisTest.ProofMode.Widget IrisTest.ProofMode.WidgetDemo IrisTest.ProofMode.WidgetRpc +Iris.ProofMode.Widget:vir
lake test
cd ..
node scripts/widget-runtime-smoke.mjs
node scripts/widget-browser-smoke.mjs
```

Keep the cache environment from the runbook. Adding the browser gate to CI and
adding realistic proof fixtures would increase confidence more than adding more
small `P Q R S` examples.

## Native component experiment (2026-11-02)

`IrisTest/ProofMode/WidgetCompare.lean` exports the current view and a minimal
Lean wrapper around VIR's `Infoview.interactiveCode`. A test RPC prints the
same typed Iris target as native `CodeWithInfos`. The browser passes that
registered JavaScript object through the Lean wrapper unchanged; identity is
asserted at the host `createElement` boundary. Production still uses the
existing renderer. This is evidence for a design review, not a renderer choice.

The comparison uses the real upstream `renderInfoview` and its RPC providers.
Widget discovery/source are host shims; state, goal, native tag and popup RPCs
reach Lean. Canonical target text agrees at every position. Real pointer hover
over the bound `m` shows `Nat`; Ctrl-click on `some` invokes native navigation
and records the editor's `showDocument` call for `Init/Prelude.lean`. It does
not exercise VS Code's execution of that call. Docstring contents, semantic
selection, screen readers and long-session GC remain untested.

```bash
# From Iris/, using the cache/TMPDIR settings in the runbook:
lake build IrisTest.ProofMode.WidgetDemo +IrisTest.ProofMode.WidgetCompare:vir
cd ..
IRIS_WIDGET_WIDTH=1000 \
  IRIS_WIDGET_RESULT=.tmp/review/comparison.json \
  IRIS_WIDGET_SCREENSHOT=.tmp/review/comparison.png \
  node scripts/widget-browser-smoke.mjs --comparison
```

This command stops its browser/server after testing. The normal `--demo`
continues to show the production widget, including the two SpinLock positions.

Baseline counts reproduce the independent reviewer probe:

| State | Current term buttons | Punctuation-only | Current visible characters | Native target hover spans |
| --- | ---: | ---: | ---: | ---: |
| Contexts | 11 | 3 | 62 | 5 |
| Before store | 39 | 16 | 135 | 21 |
| After store | 35 | 15 | 123 | 19 |
| After load | 23 | 9 | 96 | 14 |
| Nested binders | 11 | 3 | 44 | 12 |
| SpinLock, invariant open | 94 | 35 | 387 | 33 |
| SpinLock, after store | 77 | 24 | 348 | 25 |

Native target columns have **zero buttons and zero Tab stops**. Removing leaf
buttons does not by itself provide keyboard accessibility. Current counts
include the context and target; native counts include only the target.

These measurements predate the document-scope continuity correction below;
rerun them before treating the timings as current performance estimates.
Measurements use production React, 360px columns, 14px monospace and a
1000×900 viewport, with one warmup pass followed by five measured passes.
The local five-state baseline's median decoded-reply-to-DOM durations were
8.8/12.3/11.5/10.3/6.3 ms for the current view and
0.8/1.0/0.8/0.6/4.4 ms for the native target. The extended run measured
30.8/29.0 ms for the two current SpinLock states and 1.6/1.0 ms for their native
targets; its RPC medians were 57.9/45.1 ms and 49.5/39.1 ms respectively.

These are different workloads on a shared page/server. They do **not**
establish a renderer speedup. The DOM boundary is a MutationObserver seeing
exact target text, after HTTP JSON decode; it includes remaining display
conversion, VIR/React work and observer delay. It is neither paint time nor
isolated renderer CPU. No concurrent builds/tests were launched by this run,
but the shared host's load was not controlled. Raw samples, load, Node/Chrome
versions, source, package, bundle and Wasm hashes are retained locally in
`.tmp/review/native-code-baseline.json` and `spinlock-comparison.json`, with
logs and a baseline screenshot. Exploratory pre-font-normalization runs are
retained separately and excluded from these figures. These are local evidence
paths, not artifacts shipped by the repository.

The pinned `@leanprover/infoview` 0.13.0 comes from commit
`66528403779d277160f1e9b9ee54de1ac24b8fec`. Its
[goal host](https://github.com/leanprover/vscode-lean4/blob/66528403779d277160f1e9b9ee54de1ac24b8fec/lean4-infoview/src/infoview/info.tsx#L194)
renders Tactic state unconditionally, then the panel widgets. The
[panel props](https://github.com/leanprover/vscode-lean4/blob/66528403779d277160f1e9b9ee54de1ac24b8fec/lean4-infoview/src/infoview/userWidget.tsx)
have no supported hide/replace callback. `expectedTypeVisibility` controls
Expected type only. Users can manually collapse Tactic state; automatic
replacement would require host/upstream support. Replacement versus coexistence
is still a maintainer decision.

There is also a content-coverage gap: `DisplayGoal` does not carry the ordinary
Lean context shown above the Iris judgment (for example `hlc`, `GF`, `s`, `E`,
`l`, `l'`, `v`, `v'`, `w`). The server retains local contexts for term inspection,
but the widget does not render a complete list of Lean locals/hypotheses.
Host support alone would not make it a replacement. Any replacement proposal
must include that context and validate the complete view; the target-only
native experiment does not do so. See the
[display baseline and replacement requirements](proof-mode-widget-design.md#current-iris-display).
In particular, iris-lean already uses `∗name : proposition`; Rocq's separator
lines are optional inspiration, while the widget's missing colon remains a gap.

Native enclosing-subterm selection also needs a valid `LocationsContext`
template. Freshly printed Iris proposition positions are relative to that
proposition, not the full Lean `Entails'` goal. A production integration must
map target/hypothesis extraction paths before producing `GoalsLocation` values.
The experiment deliberately makes no selection claim. Snapshot reclamation
still depends on upstream RPC object lifetimes/GC; this is not a memory test.

## Downstream packaging fixture (2026-11-02)

Run `node scripts/widget-downstream-smoke.mjs` from the worktree root, with the
usual cache settings. It creates a retained `.tmp/widget-downstream-*` project,
copies current Iris sources without build products or dependencies, requires
that copy as a path dependency, and fetches fresh pinned transitive dependencies.
It installs VIR's declared npm dependencies, builds `Consumer`, starts a fresh
Lean server, and tests widget discovery, typed Iris state, asset RPC and package
generation. Logs, exit codes and hashes are kept in the fixture's `result.json`.
The working Iris/dependency directories are only read. This uses the existing
artifact cache and a local source copy, not a released Iris package or a clean
cache. It does not run a downstream browser.

Observed result: `lake update`, `npm ci`, and `lake build Consumer` pass (1070
jobs). Imported widget/state RPCs work. The first `readAsset` fails with
`-32603`, missing the runtime at the **consumer's**
`.lake/packages/lean_vir/web/public/vir-upstream.wasm`. A diagnostic control
installs the already validated matching Wasm only into that isolated consumer;
the RPC then returns exactly the same 793324 bytes, SHA-256
`0b46452bf58183e41e9b9a53e26967ad3f72eba25bec86d99445b92ab9be9089`.
Package generation also succeeds with the advertised entry/fingerprint.
The first retained run is `.tmp/widget-downstream-4H29bj/result.json`.

The relative path itself works with Lake's flattened transitive dependency
layout. The gap is distribution/setup: ordinary consumer build does not install
the runtime, while our setup script is anchored to this repository's `Iris/`
workspace and is not a downstream install interface. The diagnostic copy is
not a proposed installation solution. The fixture intentionally expects this
missing-runtime failure and will need updating when that contract changes.

VIR is still declared in core Iris's Lake requirements, so even consumers that
do not import the widget fetch it during dependency resolution. A second
`lean_lib` in the same package would not make that dependency optional. Package
placement, a consumer-aware runtime installation mechanism, and documentation
distribution remain design decisions; this fixture changes none of them.

## Continuity correction after review

The first continuity implementation scoped presentation to the position-specific
RPC session. The reviewer was right: a real cursor move kept the same goal IDs
but remounted both cards. The new negative-control log records that failure in
`.tmp/review/continuity-cursor-before.log`.

Presentation now belongs to the document in the mounted panel. Exact surviving
IDs take priority; changed IDs can reuse unclaimed ordinal slots for collapse
only. Tests cover moving away/back within one proof state, typing a space with a
one-character cursor advance, and adding an ordinary local while moving the
cursor. In the recorded example, cursor movement, renaming the target variable
and comment typing preserve `_uniq.1016`/`_uniq.1017`; the added local changes
them to `_uniq.1021`/`_uniq.1022`. Both cards and collapse survive. A surviving
goal also keeps its own card after the preceding goal is solved. This small
corpus is evidence that IDs can churn, not an estimate of how often they do.

A held refresh adds no panel height or routine live region. Initial loading and
errors remain visible; `aria-busy` describes routine refresh. The renderer still
uses disabled term buttons and a fresh semantic epoch per accepted reply.
Focused collapse controls survive these updates, but the measured term-focus
sequence is **focused before → unfocused while pending → unfocused after**.
That observation uses DOM focus in Chromium; the existing Enter activation test
is separate. It is an unresolved input to the native-renderer keyboard review,
not a claim of focus continuity or screen-reader acceptance. No further native
renderer changes were made during this correction.
