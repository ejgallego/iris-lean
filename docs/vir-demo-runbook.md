# Iris widget demo

Open `Iris/IrisTest/ProofMode/WidgetDemo.lean` in the `Iris/` VS Code workspace.
Put the cursor on the code line after each marker. The card sits beside the
normal Tactic state and labels its projection of the tactic's **before-state**.
Allow ten minutes; rehearse once in VS Code before presenting.

## Presenter positions

Each marker has the prefix `widget-position-`.

- **heap-store:** `wp_store` updates `Hl`; `Hframe` stays untouched.
- **heap-load:** `wp_load` only changes the goal.
- **heap-post:** `iframe` discharges both cells; the target reduces to pure equality.
- **spin-open:** show the reduced mask, expand `Hinv`, and follow `Hpt`/`Hcond`.
- **spin-stored:** `imodintro` strips only the goal's update modality.
- **spin-frame:** `iframe Hpt`; that resource leaves the context and the goal reduces.
  Lean's positional context diff also highlights `Hcont`, `Hinv` and `Hcond` here
  because removing `Hpt` shifts the context. The card pairs by resource identity,
  so only `Hpt` has a hypothesis annotation.
- **contexts:** `isplitr [HQ HS]` sends spatial ownership to goal 2; persistent resources stay in both.
- **split / binders / ordinary:** independent collapse, contextual native terms, no Iris card on an ordinary goal.
- **how-vir:** Lean-authored React in `View.app`, native InteractiveCode, local panel declaration.
- **feedback:** which changes matter—ownership, modalities, masks, invariants—and which real proof next?

HeapLang comes from the heap tactic tests; SpinLock is the library `release_spec`
proof. Its local `pp.iris.quotations false` also shortens the normal Tactic state.
The widget uses that option throughout; see [implementation and limits](proof-mode-widget.md).

Optional tour: add `public meta import IrisTest.ProofMode.WidgetTour` among the demo imports.
Then add `show_panel_widgets [local IrisTest.ProofMode.WidgetTour.widget with IrisTest.ProofMode.WidgetTour.panelProps]` after the existing panel declaration.

## Presenter setup (existing checkout)

```bash
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true
(cd Iris && lake build IrisTest +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir)
code Iris
```

## Attendee setup

Install Git, `elan`, Node.js/npm (tested with Node 24), and VS Code with the Lean 4
extension (tested with `leanprover.lean4 0.0.240`). Setup downloads pinned Lean
**4.35.0**, Lake/npm dependencies and the matching VIR runtime; no local Wasm
compiler is needed. This is a demo branch, not a released extension/package.

```bash
git clone -b feat/proof-mode-widget-demo https://github.com/ejgallego/iris-lean.git widget-demo
cd widget-demo
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_RESTORE_ARTIFACTS=true
# Optional: export LAKE_CACHE_DIR=/your/writable/lake-cache
(cd Iris && lake update && npm ci --prefix .lake/packages/lean_vir)
node scripts/widget-setup-runtime.mjs
(cd Iris && lake build IrisTest.ProofMode.WidgetDemo IrisTest.ProofMode.WidgetTour.Test +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir)
code Iris
```

Keep the checked-in pins (VIR `81de859a`); setup verifies the matching runtime.
`LAKE_RESTORE_ARTIFACTS=true` materializes cached files for package capture.

## Troubleshooting and checks

Empty panel: wait for elaboration, inspect Lean's Messages/Output, rebuild, then
**Lean 4: Restart File**. Keep the demo imports and local panel declaration.
Asset/runtime error: rerun `node scripts/widget-setup-runtime.mjs`, retain the
actual error, and restart the file. Restart after any dependency change.

Run `lake test` from `Iris/`, then `node scripts/widget-browser-smoke.mjs` from
the checkout root. Run `TMPDIR=$PWD/.tmp node scripts/vscode-e2e/widget-vscode.test.mjs`
for the [real VS Code gate](../scripts/vscode-e2e/README.md); it needs desktop VS Code/Xvfb and stays outside CI.
Browser fallback: `node scripts/widget-browser-smoke.mjs --demo` serves
<http://127.0.0.1:8140/>. Ctrl+C stops it and its Lean server.
