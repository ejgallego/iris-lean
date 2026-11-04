# Iris widget prototype: a ten-minute demo

This prototype stays **beside the normal Tactic state**. It groups Iris resources
and uses upstream `InteractiveCode` for propositions and the target. It does not
replace the ordinary Lean context. A demo prototype compares resources before and
after the tactic under the cursor.
The meeting is for feedback on what an Iris-specific view could add.

## Presenter setup — before the meeting

In the maintainer's existing checkout:

```bash
cd /home/egallego/lean/iris-lean/.worktrees/proof-mode-widget
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true
cd Iris
lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir
cd ..
node scripts/widget-runtime-smoke.mjs
code Iris
```

If dependencies/runtime have not been installed, use the attendee setup below
first. Keep the Lean server warm. The installed extension is
`leanprover.lean4` **0.0.240**, whose `@leanprover/infoview ~0.13.0` dependency
matches VIR's 0.13.0 pin. The isolated real VS Code acceptance now passes,
including native hover/navigation and cursor/edit continuity. Still do a short
presenter preflight in the window used for the meeting; the standalone browser
host and the real VS Code harness are separate checks.

Open `IrisTest/ProofMode/WidgetDemo.lean`. For each marker below, put the cursor
at the **first non-space character of the following tactic line** (its before
state). Keep both Tactic state and the Iris panel visible.

## Live flow — about ten minutes

1. **Heap ownership, 0–2 minutes.** At `widget-position-heap-store`, the program
   writes `v'` to `l` and then reads it. Show `∗Hl : l ↦ some v` and the frame
   `∗Hframe : l' ↦ some w`. Hover over `l`, `E`, and the postcondition binder
   `r`: native popups report `Loc`, `CoPset`, and `Val`. Ctrl/Cmd-click `some`
   in a hypothesis to try native go-to-definition. The normal view still gives
   the complete Lean context.
2. **One tactic, two resource states, 2–4 minutes.** Stay at
   `widget-position-heap-store`: under the current goal, **After wp_store · resources**
   shows `Hl` changed to `l ↦ some v'`, with `was: l ↦ some v`, while `Hframe`
   is marked preserved. The new terms have native hover too. This adds named
   resource correspondence beside Lean's existing expression diff; it does not
   infer that a preserved resource was framed. Move to `widget-position-heap-load`:
   `wp_load` preserves both resources. At `widget-position-heap-post`, the current
   WP has become the postcondition, including `⌜v' = v'⌝` and both cells.
3. **An opened invariant, 4–6 minutes.** At `widget-position-spin-open`, show
   persistent `Hinv`, `Hl : locked γ`, `HR : R`, and
   `Hpt : ▷ l ↦ some hl_val(#b)`. At `widget-position-spin-stored`, `Hpt` contains
   `false` and loses the later; `Hcond` also loses its later. The target is the
   update that closes the invariant under the reduced mask. Hover over `γ` or
   `b` for their native context. At the store, the comparison marks `Hpt` and
   `Hcond` changed (both lose `▷`), and `Hinv`, `Hl`, `HR`, `Hcont` preserved.
   Optional: `widget-position-spin-frame` selects `iframe Hpt` and lists `Hpt`
   as removed from the resulting goal. “Removed” does not mean “consumed”.
   The existing `spin-stored` marker selects `imodintro`, which preserves all
   resources. This is the complete `SpinLock.release_spec`.
4. **How VIR is used, 6–8 minutes.** Show the local `show_panel_widgets` line in
   the demo, `vir_proof_widget View.app` in `Iris/ProofMode/Widget.lean`, and
   `hypothesisRow` in `Widget/View.lean`. React components are authored in Lean;
   the native `InteractiveCode` component receives the original RPC object.
   Briefly show `displayIrisGoalAt?` in `Widget/Rpc.lean`: the elaborated target
   goes through `Iris.ProofMode.parseIrisGoal?`, then typed `Hyps` projection.
   No rendered syntax is parsed. If useful, show collapse at the generic
   `widget-position-split`; cursor movement and edits retain presentation state.
5. **Feedback, 8–10 minutes.** Use the questions at the end of this guide.

Enclosing-subterm selection and a complete keyboard policy for native terms
remain gaps. Do not present ordinary native hover as a new Iris feature: it
provides familiar interactions while the resource view develops.

## Attendee installation and trying it

Today this is a development branch, not a released extension or installable
optional Iris widget package. Obtain the **demo checkpoint from the maintainer**
(the demo commits are local until separately published). Install Git, VS Code
with the Lean 4 extension, `elan` (which installs the pinned Lean **4.35.0**),
and Node.js/npm. Our checked host uses Node **24**. A first setup needs network
access for Lean, Lake/npm dependencies and the pinned VIR runtime pack.
No Emscripten installation or local Wasm compilation is required.

From the supplied checkout, choose your own writable cache directory:

```bash
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_RESTORE_ARTIFACTS=true
# Optional: export LAKE_CACHE_DIR=/your/writable/lake-cache
cd Iris
lake update
npm ci --prefix .lake/packages/lean_vir
cd ..
node scripts/widget-setup-runtime.mjs
cd Iris
lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir
cd ..
code Iris
```

Keep the checked-in dependency pins. VIR is pinned to `81de859a`, the last
compatible mainline commit before Lean 4.36. The setup script validates its
resource pack and installs the matching Wasm. `LAKE_RESTORE_ARTIFACTS=true`
materializes cached module files for this VIR package generator; it does not
disable the artifact cache. Open the demo and follow the Heap/SpinLock markers
above. Adding Iris as a dependency of a different project is not yet a supported
one-command widget setup; see the downstream fixture in the coverage guide.

If the panel stays empty, first use the exact tactic position after a marker,
wait for elaboration, and check Lean's Messages/Output. At the ordinary `Nat`
example an empty Iris panel is expected. Confirm that the open workspace is
`Iris/`, that the demo imports `Iris.ProofMode.Widget`, and that its
`show_panel_widgets` line is present. Rebuild the command above, rerun
`node scripts/widget-setup-runtime.mjs` from the checkout root if an asset/runtime
error is shown, then run **Lean 4: Restart File**. Record the actual error if it
persists; do not change toolchain or dependency pins to make it disappear.

## Browser fallback and developer checks

After setup, `node scripts/widget-browser-smoke.mjs --demo` serves a read-only
proof-position selector at <http://127.0.0.1:8140/>; Ctrl+C stops it and its Lean
server. `IRIS_WIDGET_PORT` selects another port. It uses real upstream infoview
providers and the production widget. Native navigation reaches an editor callback
but the browser host does not open a Lean source editor.

For the automated gate, build `IrisTest.ProofMode.Widget` and
`IrisTest.ProofMode.WidgetRpc` and `IrisTest.ProofMode.GoalChanges` as well, then run `lake test`,
`node scripts/widget-runtime-smoke.mjs`, and `node scripts/widget-browser-smoke.mjs`
(the Node commands run from the checkout root). Chromium is needed only for the
browser regression. See [coverage and limits](widget-testing-surface.md).

The **real VS Code gate** is separate from that browser host:

```bash
# From the worktree root; keep the cache environment above and avoid concurrent Lake builds.
TMPDIR="$PWD/.tmp" node scripts/vscode-e2e/widget-vscode.test.mjs
```

It launches desktop VS Code with an isolated Xvfb display/profile and the installed
Lean extension. It needs Linux, desktop VS Code, Xvfb, Node 22+, and the installed
Lean/TOML extensions; see the [harness README](../scripts/vscode-e2e/README.md).
Outputs go to `$TMPDIR/vscode-e2e-runs` (or `IRIS_E2E_RUNS`), outside the harness
source directory. The typing test never saves its buffer. This gate passes on
the prototype and stays out of CI because it requires a desktop VS Code install.
It complements the presenter's manual run-through before the meeting.

## Questions for the Iris authors

- When does this resource grouping help alongside the normal Tactic state?
- Does this prototype of resource changes before/after the tactic explain a useful
  proof step? Would comparing more distant states justify explicit pinning?
  Which changes matter most: ownership, modalities, masks, or invariant state?
- What is the next representative proof: lock acquisition/CAS, fractional
  ownership, a concurrent client, or custom notation?
- What information must stay visible in a dense state, and what can collapse?
- Which confusing state should we capture as a regression before adding polish?
