# Widget testing and use-case surface

## In-place expert annotations (Round D)

The card shows the selected tactic's before-state in its own context order.
`GoalChanges` tests, independent of VIR, check instantiated target comparison
alongside typed `IVarId` pairing on HeapLang and SpinLock. They cover target-only
changes, an unchanged tactic, additions, departures, branching, closure and the
existing refusal cases. `WidgetModel` checks the presentation rules: quiet
unchanged rows, persistence changes, additions in context order, neutral “no
longer in context”, every split destination/target, summaries and unavailable
comparisons. No text or name matching establishes resource identity.

The browser gate checks native new propositions and targets, additions, split
distribution, unchanged-row silence, departure wording, and the stable before-card
even at after-side cursor positions. Held replies, stale semantic actions,
refresh failure, cursor/typing collapse continuity and leaving Iris remain covered.
The real VS Code gate checks all nine terse tour headlines against rendered proof
states, native hover on an annotated new value, definition navigation from an
annotation, `imodintro`'s target-only change, `iframe` departures, split distribution,
and the existing card identity/collapse checks. Screenshots of Heap store,
SpinLock store, `imodintro` and the split are retained in `.tmp/round-d/`.

Validation on 2026-11-05: `lake build Iris IrisTest +Iris.ProofMode.Widget:vir
+IrisTest.ProofMode.WidgetTour:vir`, `lake test`, runtime package verification,
and **20/20** real VS Code checks. Browser checks pass at light 360px/14px, dark
320px/22px (500ms package delay) and high contrast 280px/28px. The browser pointer
uses a painted text fragment for wrapped native leaves, rather than their bounding
box's potentially empty centre. Real-host evidence:
`.tmp/vscode-e2e-runs/2026-11-05T14-22-50-903Z/`.

At SpinLock, the context's order itself changes after `wp_store`: the before-store
state has `Hpt, Hcond`, while the before-`imodintro` state has `Hcond, Hpt`. Each
card follows its own before-state. Long SpinLock cards still require scrolling
below the standard Tactic state. Native enclosing-subterm selection and term
keyboard policy remain gaps. Subterm highlighting is deferred: Lean 4.35 exports
whole-goal diffing but keeps its per-expression helpers internal.


## Guided demo tour (Round C)

The tour steps live in `IrisTest.ProofMode.WidgetTour.Model`, beside the demo.
`check_widget_tour` checks their references against the complete `WidgetDemo`
source. Missing and duplicate markers are build errors; the model tests also
cover invalid destinations, line insertion, exact selection, neutral selection
and the nearest preceding step. Actual negative builds, with one marker removed
or duplicated, both fail with the expected count (0 or 2).

The separate Lean-authored tour uses VIR's `EditorContext` and
`EditorConnection.revealPosition`. Its server resolves destinations from the
current document buffer on each position/revision; the native destination
objects are retained directly. Stale replies and navigation are retired with
the effect. The production widget does not import the tour. A named alias of
VIR's loader gives the two local panels distinct infoview identities while
sharing the same JavaScript source. Reusing the same module name caused React
key collisions in infoview 0.13; the browser gate caught them.

Round C passed **17/17** real VS Code checks: the prior thirteen checks plus Next,
Prev, manual step sync (including dimmed between-step text and final feedback),
and navigation after an unsaved line insertion. It verifies the editor's actual
URI/line/character, not just a callback. The original DOM-identity/collapse tests
still passed. At that checkpoint, resource comparisons preceded the current-state
body; Round D supersedes that separate section with inline annotations. This moves the useful rows earlier, but
does not guarantee they fit above the fold beneath a long normal Tactic state.

Validation on 2026-11-04: focused Lake build including `WidgetTour.Test`, both VIR
packages and RPC fixtures; `lake test`; runtime package verification; browser
gate at light 360px/14px, dark 320px/22px with 500ms package delay, and high
contrast 280px/28px. The browser gate checks the same tour navigation, neutral
initial state, panel order and unsaved line insertion. No React key warning
remains. The real-host evidence is
`.tmp/vscode-e2e-runs/2026-11-04T19-56-11-776Z/`; other logs and screenshots are
under `.tmp/round-c/`.
The separate `--demo` probe also traverses all eight steps and back, checking
that reveal updates the source highlight and proof-position selector.

Two test synchronization failures are retained there. The delayed-package
browser run first moved before the initial tour was ready; the gate now checks
that neutral initial state before moving. A VS Code run passed 16/17 but the
native-definition round trip left the entire infoview at the previous cursor
position. The test now waits for the infoview to follow both file changes before
issuing the next cursor move, in addition to checking the actual editor. This
is test synchronization, not a production workaround or an upstream fix claim.
Tour button input in the VS Code gate is synthetic DOM activation; physical
keyboard navigation and full accessibility remain outside this acceptance.

## Tactic-local resource prototype (Round B)

`IrisTest.ProofMode.GoalChanges` has no widget/VIR import. Complete Heap and SpinLock
proofs assert statuses using saved before/after contexts: store changes the owned
cell and preserves the frame; load preserves both; SpinLock store changes Hpt and
Hcond while preserving Hinv/Hl/HR/Hcont; framing removes Hpt. Additional cases
cover introduced resources, a two-result split, closure (no removal claims),
renaming versus fresh IDs, duplicate IDs, changed local bindings and ambiguous
predecessors. Names label test expectations, never resource correspondence.

The browser gate checks production `findGoalsAt?` selection, all split outcomes,
Heap/SpinLock statuses and both proposition sides, native hover on a new-side term,
resource removal at `spin-frame`, and the unchanged ordinary view in a comment.
It retains held-response/stale-action, collapse, edit, failure and outside-Iris
checks. The real VS Code gate adds Heap store and SpinLock store comparisons to
its existing eleven checks. All terms in the after-view use the same snapshot
lease as the current view; old-side terms deliberately remain plain text.

`spin-stored` still selects `imodintro`, not the following frame operation.
`spin-frame` is an additional exact cursor position at `iframe Hpt`. Hcond loses
its later modality at the store; it is not removed there. These are structural
Expr comparisons, not semantic equivalence, consumption or framing analyses.

Validation on 2026-11-04: focused Lake build and `lake test`; runtime package
verification; browser gate at 360px/14px light, 320px/22px dark with a 500ms package
delay, and 280px/28px high contrast; real VS Code **13/13**. Browser checks include
after-side branching and a closed-goal cursor position. The final real-host run
is `.tmp/vscode-e2e-runs/2026-11-04T17-08-39-719Z/`; other retained logs and the dark
Heap screenshot are under `.tmp/round-b/`. No change to toolchain, VIR pin,
runtime installation, packaging or CI.



Current prototype: Lean 4.35 / VIR `81de859a`, with native `InteractiveCode`
terms beside the normal Tactic state. The pre-migration experiments below are
historical evidence, not claims about the current renderer. The live demo is served by
`node scripts/widget-browser-smoke.mjs --demo`; see the
[runbook](vir-demo-runbook.md).

## Round A acceptance (2026-11-04)

Production now sends native `CodeWithInfos` objects separately from the version-4
metadata JSON. Each hypothesis proposition and the target uses upstream
`InteractiveCode`; custom per-leaf buttons and the inline inspector are gone.
The normal Tactic state remains visible. The browser/demo hosts now use actual
upstream infoview providers, with bundled widget-source substitution and an
editor API bridge. A separate real VS Code acceptance run now passes as well;
its scope is recorded below.

The final light/360px/14px, dark/320px/22px with 500 ms package delay, and
high-contrast/280px/28px runs pass (421 host RPC calls each, including injected
failures and ordinary infoview activity). They check canonical terms, the `: `
separator, hover for `P`, `n`/`m`, `l`/`E`/`r`, and `γ`/`b`; actual browser
Ctrl-click on `some` reaches `EditorApi.showDocument` for `Init/Prelude.lean`.
The large-font navigation test targets the first text fragment of a wrapped tag.

Continuity cases retain card DOM, collapse and collapse-control focus across
cursor moves, same-position edits, typing with a moving cursor, goal-ID churn,
and a surviving goal changing ordinal. Held replies leave old canonical text
visible, add no Iris-panel height/status announcement, and leave no native
semantic handlers. A held native popup is cancelled on snapshot retirement;
late snapshot successes/failures and unmount cannot replace current content.
Refresh failure/recovery, non-Iris empty results, malformed replies, readable
RPC/package errors and server-observed cancellation remain covered. One expected
console error comes from the deliberately invalid package fingerprint; its UI
message/code are checked. No unhandled error or React key warning was observed.

| Live state | Native hover spans, whole Iris panel | Term buttons |
| --- | ---: | ---: |
| Heap before store | 29 | 0 |
| Heap after store | 27 | 0 |
| Heap postcondition | 22 | 0 |
| SpinLock invariant open | 74 | 0 |
| SpinLock after store | 65 | 0 |

These are structural counts, not performance measurements. Each Iris panel
passes its own horizontal-overflow check. The standard Tactic state can still
overflow the very narrow 280px viewport at 28px font; this run does not certify
page-wide layout or full editor accessibility. Enclosing-subterm selection and
a complete native-term keyboard policy remain explicit gaps. Collapse still
works through real Enter key events. No fabricated goal/subterm path is used.

The comparison rerun asserted exact object identity for 388 native component
invocations and collected 86 target observations; it used the native production
renderer before the separator/import follow-up. Historical leaf-button timings
below must not be presented as current performance. The demo host passes all
nine proof selectors; screenshots of the normal view beside the native widget
were inspected. The final Lake build, `lake test` and runtime smoke pass (34
package members); one pre-existing redundant-`private` warning remains.

Visual inspection caught an implementation-dependency issue: ordinary imports
only track public interfaces, while `vir_proof_widget` captures runtime IR during
elaboration. The entrypoint now also meta-imports `View`. A controlled
implementation-only separator change preserved `View.olean`, changed `View.ir`,
and rebuilt `Widget.olean`; restoring the source restored all three exact hashes.
This needs upstream documentation/API guidance, not a cache purge.

Local evidence is retained in `.tmp/round-a/`: `light-v4`, `dark-v4` and
`contrast-v4` JSON/log/PNG files, `native-comparison.json`, `demo.json`/`demo.png`,
`import-dependency.json` with variant/restoration logs, and Lake build/test logs.
Earlier failing probes are retained. The downstream fixture was rerun against
this code in `.tmp/widget-downstream-nYFncg/result.json`: registration/state/package
pass; missing runtime installation and the matching donor control behave as
recorded below. Packaging placement is unchanged.

## Real VS Code acceptance follow-up (2026-11-04)

The isolated headless VS Code harness using the installed
`leanprover.lean4 0.0.240` passes **11/11 checks** against the production checkpoint
`81472c77`. It uses its own Xvfb display/profile and the actual infoview webview,
without substituting the widget source or its context providers. It never saves
the typing edit and reverts the buffer on exit. No production code changed in
this follow-up.

Checks cover Heap store/load and postcondition; the `: ` separator; `l : Loc`
hover; actual native definition navigation opening `Init/Prelude.lean` at line
3058; both distinct SpinLock states; empty ordinary goals; two split cards;
collapse and card DOM identity across cursor movement **and typing**. The
navigation check reads the active editor's URI/position, not just a callback.
Hover and Ctrl-click are synthetic DOM input inside the real webview; this does
not establish physical-pointer, keyboard-policy or screen-reader acceptance.

The store check also records Tactic state's existing diff spans. They mark
`l`, `v`, `l'`, `w` and the program in this state, even though the frame
proposition remains unchanged. The [resource-change proposal](widget-resource-changes.md)
now evaluates possible resource-level value beyond that built-in expression diff.

Run locally, with no concurrent Lake build:

```bash
TMPDIR="$PWD/.tmp" node scripts/vscode-e2e/widget-vscode.test.mjs
```

The real-VS-Code gate is now in [`scripts/vscode-e2e/`](../scripts/vscode-e2e/README.md),
with generated output under `$TMPDIR/vscode-e2e-runs` (override `IRIS_E2E_RUNS`).
It is deliberately outside CI: Linux, desktop VS Code, Xvfb and installed
Lean/TOML extensions are required. The initial eleven-check run's results,
temporary profile, VS Code log and screenshots are under
`.tmp/vscode-e2e-runs/2026-11-04T14-24-42-026Z/`. Its original nine-check predecessor
is retained in `.tmp/vscode-e2e/runs/2026-11-04T14-02-49-717Z/`.
The added definition-navigation round trip included a roughly 47-second wait
before the Heap postcondition became ready; this is not a latency benchmark or
an attribution to widget rendering. Full editor focus/scroll, restart recovery,
long-session reference release and accessibility remain open.

The relocated gate was then run from `scripts/vscode-e2e/` using its default
workspace resolution: **11/11 pass**, with evidence in
`.tmp/vscode-e2e-runs/2026-11-04T14-32-38-659Z/`. No profiles or generated outputs
were copied into the harness source directory. This is the committed local gate;
it is not enabled in CI.

## Pre-migration coverage map (historical)

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
   files/panels, and focus/scroll behavior across edits. The current browser host uses actual upstream providers with an editor API bridge;
   it does not establish these behaviors in the installed VS Code extension.
5. **Accessibility and performance:** complete keyboard traversal, a screen
   reader, actual VS Code themes/zoom, measured latency and long-session memory.

Native infoview hover/navigation is now the production term renderer.
The earlier experiment below records the evidence used for that decision.
Mathematical presentation and resource-change rendering remain design work.

## Historical automation status before native migration

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
asserted at the host `createElement` boundary. At that checkpoint production still used the
leaf-button renderer. The maintainer subsequently approved native terms.

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
replacement would require host/upstream support. The maintainer has chosen coexistence for this prototype; replacement is out of scope.

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

## Continuity correction before native migration

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
