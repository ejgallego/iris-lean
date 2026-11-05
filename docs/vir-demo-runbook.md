# Iris widget demo

Open `Iris/IrisTest/ProofMode/WidgetDemo.lean` in the `Iris/` VS Code workspace.
The widget stays beside the ordinary Tactic state. Put the cursor on the code
line immediately after each marker; the card explicitly shows the tactic's
before-state. Allow about ten minutes.

To enable the optional tour, add `public meta import IrisTest.ProofMode.WidgetTour` among the imports in `WidgetDemo.lean`.
Then add `show_panel_widgets [local IrisTest.ProofMode.WidgetTour.widget with IrisTest.ProofMode.WidgetTour.panelProps]` immediately after the existing panel declaration.

## Presenter list

Each name below has the prefix `widget-position-` in the file.

- **heap-store:** `wp_store` updates `Hl`; `Hframe` stays untouched.
- **heap-load:** `wp_load` only changes the goal.
- **heap-post:** `iframe` discharges both cells; the target reduces to pure equality.
- **spin-open:** store inside the opened invariant; show the reduced mask, expand `Hinv`, and follow `Hpt`/`Hcond`.
- **spin-stored:** `imodintro` only changes the goal's update modality.
- **spin-frame:** `iframe Hpt`; that resource leaves the context and the goal reduces.
- **contexts:** `isplitr [HQ HS]` sends spatial ownership to goal 2; persistent resources remain in both goals.
- **split:** two independently collapsible resulting goals.
- **binders:** native hover under nested binders, before introducing them.
- **ordinary:** an ordinary Lean goal has no Iris card.
- **how-vir:** Lean-authored React through VIR, with native InteractiveCode terms.
- **feedback:** which changes matter—ownership, modalities, masks, invariants—and which real proof should we try next?

The HeapLang example is adapted from the heap tactic tests; SpinLock is the
complete library `release_spec` proof. It also uses the experimental
`set_option pp.iris.quotations false in`, shortening value and iProp wrappers
in the ordinary Tactic state. The widget uses that display option throughout;
[the POC note](widget-quotation-poc.md) explains the retained wrappers and limits.
For an optional notation discussion,
[the offline MathML gallery](notation-gallery/index.html) contains manually
authored specimens and mock inspections, not live Lean terms.

## Presenter setup

From the checkout root:

```bash
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true
cd Iris
lake build IrisTest +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir
cd ..
code Iris
```

## Attendee setup

Install Git, VS Code with the Lean 4 extension, `elan` and Node.js/npm (tested
with Node 24). The checkout pins Lean **4.35.0**. Initial setup needs network
access for Lean, Lake/npm dependencies and the matching VIR runtime pack;
Emscripten and local Wasm compilation are not needed.

```bash
git clone -b feat/proof-mode-widget-demo https://github.com/ejgallego/iris-lean.git widget-demo
cd widget-demo
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
lake build IrisTest.ProofMode.WidgetDemo IrisTest.ProofMode.WidgetTour.Test +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir
cd ..
code Iris
```

Open `IrisTest/ProofMode/WidgetDemo.lean` and use the presenter markers above. This is the
[published demo branch](https://github.com/ejgallego/iris-lean/tree/feat/proof-mode-widget-demo),
not a released extension or optional downstream widget package. Keep the
checked-in pins; VIR is `81de859a`. The setup script verifies the matching Wasm.
`LAKE_RESTORE_ARTIFACTS=true` materializes files for package capture while keeping
the artifact cache enabled.

## Troubleshooting and developer checks

For an empty panel, wait for elaboration, check Lean's Messages/Output, rebuild
and use **Lean 4: Restart File**. Keep the demo imports and local
`show_panel_widgets` declaration. For an asset/runtime error, rerun
`node scripts/widget-setup-runtime.mjs`; retain the actual error and keep the pins.

From `Iris/`, run `lake test`. From the checkout root, run
`node scripts/widget-browser-smoke.mjs` and
`TMPDIR=$PWD/.tmp node scripts/vscode-e2e/widget-vscode.test.mjs`.
The latter needs desktop VS Code/Xvfb and the installed extensions; it stays
outside CI. The last validated extension is `leanprover.lean4 0.0.240`.
`node scripts/widget-browser-smoke.mjs --demo` serves the browser fallback at
<http://127.0.0.1:8140/>; Ctrl+C stops it and its Lean server.
