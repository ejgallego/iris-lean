# VIR + Iris Widget Demo Runbook

## Goal

Give a friendly 8–10 minute tour of the smallest useful VIR workflow:

1. author a React component in Lean;
2. export it through VIR;
3. obtain application-specific state through a typed Lean server RPC;
4. mount it in the Lean infoview.

The point is the development model, not a finished Iris UX.

## Preflight

Do this before the meeting, not during it:

```bash
cd /home/egallego/lean/iris-lean/.worktrees/proof-mode-widget
export LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true
cd Iris
lake update
cd ..
node scripts/widget-setup-runtime.mjs
cd Iris
lake build IrisTest.ProofMode.Widget IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir
lake test
cd ..
node scripts/widget-runtime-smoke.mjs
node scripts/widget-browser-smoke.mjs
```

Lake's artifact cache stays enabled. `LAKE_RESTORE_ARTIFACTS=true` materializes
cached module files for VIR's standalone package generator, which currently
does not consume Lake's artifact-path mapping. This is not a cache invalidation
or a downloader workaround. Choose a writable `LAKE_CACHE_DIR` on another machine.

The toolchain is Lean **4.35.0**. VIR is pinned to
[`81de859a`](https://github.com/ejgallego/lean-vir/commit/81de859a3ba1cb5da8bc5f128af025dd5a40b343),
the last mainline commit before the 4.36 upgrade, rather than the earlier `4.35`
tag. `widget-setup-runtime.mjs` asks VIR's Lake target to download and validate
the pinned runtime resource pack, then installs its Wasm at the path used by the
panel. It needs network access on first use; a verified cached pack works offline.
No local Emscripten build or separately selected SDK is needed. Node/npm are
required for VIR's shell build; the browser regression also needs Chromium.

Open this `Iris` directory as the VS Code workspace, restart the Lean server,
and open `IrisTest/ProofMode/WidgetDemo.lean`. Check the context, split and binder pause points and
leave the editor/server warm.

## Suggested live flow

### 1. Start with the result — 1 minute

Open `WidgetDemo.lean` and put the cursor in the ordinary `Nat` proof. The Iris
widget is absent. Move to just after `iintro`: the panel shows two persistent
and two spatial resources plus the target.

Message: the same Lean infoview can host an application-specific view without
replacing its normal goal display.

### 2. Show the activation line — 1 minute

Point at:

```lean
show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.panelProps]
```

Message: activation is local and opt-in for this prototype. Outside Iris proof
mode, the server returns no Iris goals and the component renders nothing.

### 3. Show one Lean component — 2 minutes

Open `Iris/ProofMode/Widget/View.lean` at `targetSection` or `hypothesisRow`.

Message: this is a normal typed Lean function constructing React nodes. Styles,
ARIA properties, children, and event handlers are all authored in Lean;
VIR supplies the browser bindings and runtime.

Click `P`, `R`, or `S` in the target, or focus a span and press Enter. Its actual
expression/type appears inline. In the quantified example, pause after `istart`
and inspect `n` or `m` before introduction: the saved binder context supplies
their types. Use × to close inspection. These are contextual subterm controls,
not full infoview hover popups or jump-to-definition.

Then show `vir_proof_widget View.app` and `panelProps` in `Widget.lean`.
VIR generates the factory and a package fingerprint from the component's code.
Proof edits refresh the snapshot while reusing that code package.

### 4. Show the typed boundary — 2 minutes

Open `Iris/ProofMode/Widget/Model.lean`, then
`Iris/ProofMode/Widget/Rpc.lean` at `displayIrisGoalAt?` and `toDisplayGoal`.

Message: we first tried parsing the text shown by the infoview, but Iris syntax
is extensible. The current version asks Lean for the elaborated goal and passes
its target to Iris's canonical read-only `Iris.ProofMode.parseIrisGoal?`
interface. That returns a typed `IrisGoal`; the widget traverses its typed
`Hyps` and maps them to a small versioned display domain. Proposition text is
only a rendered leaf; it is never parsed.

### 5. Demonstrate React state — 1 minute

Move the cursor to just after `isplitr`. Two Iris goals appear. Expand and
collapse the second card.

Message: the component and its local state execute through VIR. A new snapshot
resets selection and collapse state to avoid
reattaching references by spelling. `Client.lean` uses native Promises and
effect cleanup to ignore late success and failure.

### 6. Invite Iris feedback — 2 minutes

Ask the authors:

- Which real proof state should replace this generic `P Q R S` example?
- Is persistent/spatial/target the right information hierarchy?
- Which interaction should follow contextual inspection: hover popups,
  source navigation, modality information, or something else?
- Is the denser layout now close to normal Iris working density?

## What not to live-demo

- Do not rebuild the WASM runtime during the meeting.
- Do not explain the artifact cache or pinned VIR checkpoint unless asked.
- Do not promise tactic buttons, jump-to-definition, or infoview-identical
  subterm hovers; those are future extensions of the typed domain and VIR
  bridge.
- Do not spend time on the full component implementation. One small component,
  the mapping function, and the generated widget entrypoint tell the story.

## Recovery

If the panel reports an old package/runtime error:

1. rerun `node scripts/widget-setup-runtime.mjs` from the worktree root;
2. run “Lean 4: Restart File”;
3. return to the line after `iintro`.

If the live widget still fails, use the code tour: the typed RPC and browser
mount have automated smoke coverage, so the architectural discussion remains
useful without debugging the editor during the meeting.
