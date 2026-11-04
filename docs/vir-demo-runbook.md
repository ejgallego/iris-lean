# Iris widget demo: follow the guided tour

The demo stays beside the normal Tactic state. Its eight-step Lean-authored tour
covers HeapLang store/load, SpinLock, how VIR is used, and feedback. The final
step contains the questions for the Iris authors.

## Presenter setup

From the demo checkout (the maintainer's copy is `.worktrees/widget-demo`):

```bash
mkdir -p .tmp
export TMPDIR="$PWD/.tmp"
export LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true
cd Iris
lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir
cd ..
code Iris
```

Open `IrisTest/ProofMode/WidgetDemo.lean`, put the cursor on a proof line, and
follow the **Iris demo tour** above the Iris card. **Next** and **Prev** move the
real editor cursor; the talking points and hover suggestions follow it. Allow
about ten minutes. A manual jump onto a step's code line selects that step;
between steps the nearest preceding step is dimmed. Before the first step,
Next starts the tour. Navigation targets the first non-space character on the
line following each marker, preserving the intended before-tactic state.

The main effect is at the first store: `Hl` changes, with its old proposition
still visible, while `Hframe` is preserved. The resource comparison appears
first inside the collapsible goal body. Keep the normal Tactic state available
for the full Lean context. This is a prototype for feedback; “removed” does not
mean “consumed”. Native enclosing-subterm selection and keyboard policy remain
known gaps.

Do a short preflight in the presenter's window. The validated Lean extension is
`leanprover.lean4 0.0.240` with infoview `~0.13.0`, matching VIR's pin.

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
lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir
cd ..
code Iris
```

Open `IrisTest/ProofMode/WidgetDemo.lean` and follow the tour. This is the
[published demo branch](https://github.com/ejgallego/iris-lean/tree/feat/proof-mode-widget-demo),
not a released extension or optional downstream widget package. Keep the
checked-in pins; VIR is `81de859a`. The setup script verifies the matching Wasm.
`LAKE_RESTORE_ARTIFACTS=true` materializes files for package capture while keeping
the artifact cache enabled.

## Troubleshooting and checks

- **Empty panel:** wait for elaboration and check Lean's Messages/Output. Open
  the `Iris/` workspace, keep the demo's imports and local `show_panel_widgets`
  declaration, then rebuild with the command above and use **Lean 4: Restart File**.
  The ordinary `Nat` goal has a tour but deliberately has no Iris goal card.
- **No tour on an older checkout:** update to a demo checkpoint containing
  `IrisTest/ProofMode/WidgetTour.lean`, rebuild, and restart the file. Publication
  of new checkpoints is separate from local development.
- **Marker error:** restore the missing marker or remove its duplicate. Lean
  checks each tour reference during the build; navigation also resolves the
  current unsaved buffer, rather than using baked-in line numbers.
- **Asset/runtime error:** rerun `node scripts/widget-setup-runtime.mjs` from the
  checkout root, rebuild and restart the file. Keep the actual error message;
  do not change dependency pins to work around it.
- **Browser fallback:** `node scripts/widget-browser-smoke.mjs --demo` serves
  <http://127.0.0.1:8140/> (`IRIS_WIDGET_PORT` overrides it). The tour also moves
  the browser preview; native cross-file navigation is only an observed callback.
  Ctrl+C stops the server.

Developer gates: `lake test` from `Iris/`; runtime and browser checks with
`node scripts/widget-runtime-smoke.mjs` and `node scripts/widget-browser-smoke.mjs`
from the checkout root. Build `IrisTest.ProofMode.WidgetRpc` first for the browser
cancellation probe. The real VS Code gate is
`TMPDIR=$PWD/.tmp node scripts/vscode-e2e/widget-vscode.test.mjs`.
It needs desktop VS Code, Xvfb and the installed extensions; keep it outside CI
and avoid concurrent Lake builds. See the [harness README](../scripts/vscode-e2e/README.md)
and [coverage](widget-testing-surface.md). Generated evidence stays under `.tmp`.
