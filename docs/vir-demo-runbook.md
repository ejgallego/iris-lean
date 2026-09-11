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
cd /home/egallego/lean/iris-lean/.worktrees/proof-mode-widget/Iris
env LAKE_ARTIFACT_CACHE=true LAKE_CACHE_DIR=/home/egallego/.cache/mathlib LAKE_RESTORE_ARTIFACTS=true \
  lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir
```

Lake's artifact cache stays enabled. `LAKE_RESTORE_ARTIFACTS=true` materializes
cached module files for VIR's standalone package generator, which currently
does not consume Lake's artifact-path mapping. This is not a cache invalidation
or a downloader workaround. See the [local 4.32 refresh record](vir-v432-refresh.md).

The current VIR pin `8032fd3` (PR #171/Lean 4.32.2 plus shell fixes) is published
on [`fix/iris-widget-errors`](https://github.com/ejgallego/lean-vir/tree/fix/iris-widget-errors).
The command above assumes the existing worktree's matching runtime has already
been built. A fresh clone must build the Lean 4.32.2 Wasm separately; fetching
the dependency does not supply `web/public/vir-upstream.wasm`. See the
[runtime build record](vir-v432-refresh.md#pr-171-refresh--2026-09-10).

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
show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.widgetProps]
```

Message: activation is local and opt-in for this prototype. Outside Iris proof
mode, the server returns no Iris goals and the component renders nothing.

### 3. Show one Lean component — 2 minutes

Open `Iris/ProofMode/Widget.lean` at `TargetSection` or `HypothesisRow`.

Message: this is a normal typed Lean function constructing React nodes. Styles,
ARIA properties, keyed children, and event handlers are all authored in Lean;
VIR supplies the browser bindings and runtime.

Click `P`, `R`, or `S` in the target, or focus a span and press Enter. Its actual
expression/type appears inline. In the quantified example, pause after `istart`
and inspect `n` or `m` before introduction: the saved binder context supplies
their types. Use × to close inspection. These are contextual subterm controls,
not full infoview hover popups or jump-to-definition.

Then show `createComponent`, `mount`, and `widgetProps` near the end of the
file.

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

Message: the component and its local state execute through VIR. Keys are stable
within a snapshot; a new snapshot resets selection and collapse state to avoid
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
  the mapping function, and the component-factory/mount exports tell the story.

## Recovery

If the panel reports an old package/runtime error:

1. confirm `.lake/packages/lean_vir/web/public/vir-upstream.wasm` exists;
2. run “Lean 4: Restart File”;
3. return to the line after `iintro`.

If the live widget still fails, use the code tour: the typed RPC and browser
mount have automated smoke coverage, so the architectural discussion remains
useful without debugging the editor during the meeting.
