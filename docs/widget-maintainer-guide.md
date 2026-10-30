# Maintaining the Iris proof-mode widget

The widget is an opt-in companion to the normal infoview. Its application code
is Lean. VIR supplies React and browser bindings; it does not recognize Iris
goals. This guide describes the local Lean 4.35.0 prototype, not a proposed
change to Iris proof-mode semantics.

## Start here

Open the worktree's `Iris/` directory as the VS Code workspace and open
[`WidgetDemo.lean`](../Iris/IrisTest/ProofMode/WidgetDemo.lean). Restart the Lean
server after changing dependencies or rebuilding the widget package.

- After the first `iintro`: inspect the persistent/spatial contexts and target.
- After `isplitr`: expand the second goal; inspect a shared persistent `P` in
  each goal independently.
- After `istart` in the last example: inspect `n` and `m` before introduction.

Click a tagged span, or focus it and press Enter. Use × to close inspection.
The [runbook](vir-demo-runbook.md) contains the cache-enabled build command.
This worktree pins VIR's last mainline Lean 4.35 commit,
[`81de859a`](https://github.com/ejgallego/lean-vir/commit/81de859a3ba1cb5da8bc5f128af025dd5a40b343).
Run `node scripts/widget-setup-runtime.mjs` to install its published, verified
runtime. See the [4.35 review](widget-review-435.md) for migration details.

## Where to make a change

| Concern | File | Responsibility |
| --- | --- | --- |
| Display data | [`Model.lean`](../Iris/Iris/ProofMode/Widget/Model.lean) | Plain Lean structures, tagged text, JSON version |
| Iris meaning | [`Rpc.lean`](../Iris/Iris/ProofMode/Widget/Rpc.lean) | Typed goal projection and saved-context inspection |
| Panel entrypoint | [`Widget.lean`](../Iris/Iris/ProofMode/Widget.lean) | VIR package root and native panel configuration |
| Layout and controls | [`View.lean`](../Iris/Iris/ProofMode/Widget/View.lean) | Goal cards, context rows, target, activation |
| Density and theme | [`Style.lean`](../Iris/Iris/ProofMode/Widget/Style.lean) | CSS using VS Code theme tokens |
| Browser integration | [`Client.lean`](../Iris/Iris/ProofMode/Widget/Client.lean) | Native JS/RPC values, React state, effect lifetimes |
| Semantic regressions | [`Widget.lean` tests](../Iris/IrisTest/ProofMode/Widget.lean) | Actual elaborated Iris goals, binder contexts and occurrence identity |
| Interaction regressions | [`widget-browser-entry.mjs`](../scripts/widget-browser-entry.mjs) | Real-server browser behavior, races, keyboard and ARIA |

For ordinary layout work, start in the view and style files. You should not
need to handle `Js.Any`, construct RPC objects, or change Promise callbacks.
`Client.useInspection` returns ordinary Lean state: `selected : Option Nat`,
`detail : Js String`, and `select`/`close` actions. The native text goes directly
to a React text node. `Client.useState` provides
React-backed Lean values for small controls such as goal collapse.

These are normal React hooks: call them unconditionally in component render
functions. Their state belongs to React, not to a parallel Iris state store.
`Vir.ProofWidgets.Html` is a client-side React construction action, **not** the
serialized server-side `ProofWidgets.Html` type.

Use selective namespace openings for common types and prop builders (`Props`,
`PanelWidgetProps`, `TaggedText`). In the view, `Client.Component` is the
Lean-valued props facade; retain `React.FunctionComponent` for the native
panel boundary. Likewise keep `React.Hooks.useState` distinct from the
Lean-valued `Client.useState` helper.
Declaration names, RPC method strings and provenance documentation remain fully
qualified where they identify an external interface.

## Boundaries to preserve

The proof-state path is:

```text
saved InteractiveGoal context → instantiated target → parseIrisGoal?
    → typed IrisGoal / Hyps → DisplayGoal → Lean-authored React view
```

Do not parse the pretty-printed goal or proposition text. A new modality or
mathematical presentation belongs in an expression-aware adapter, with tagged
Lean rendering as the fallback. It must not change context recognition.

Three kinds of identity deliberately differ:

- Model IDs identify displayed goals/hypotheses within a snapshot. The same
  persistent hypothesis can occur in several goals. Explicit React list keys
  are still a follow-up; do not mistake model IDs for installed React keys.
- DOM IDs identify *rendered occurrences*. React's `useId` supplies each
  component occurrence with an opaque native ID; related controls reuse that
  exact value without constructing a Lean string.
- Tag indices address saved expressions in one native server snapshot. They
  are neither DOM IDs nor names. Keep the exact native snapshot reference.

`ppExprTagged` supplies contextual expression information. The server retains
the expression, local context and elaboration context; only tag indices and
canonical text cross the display JSON boundary. Inspection uses the saved
context, including variables bound inside a proposition.

Keep native identity native. `PanelWidgetProps`, RPC sessions, retained snapshot
references, React IDs, and inspection reply text are `Js` values in the client
adapter; do not decode them into Lean merely to build another JavaScript object
or render a text node. The display JSON is the deliberate exception: it becomes
the typed `WidgetState` domain that the Iris view traverses.

New snapshots currently reset selection and collapse state. Effect cleanup
suppresses late success and failure; it does not cancel the transport or dispose
the VIR runtime. Do not infer correspondence across snapshots from spelling.
Document changes and native RPC session replacement also trigger refresh, even
when the cursor remains at the same position. The package fingerprint depends
on widget code, not on proof state, so these refreshes reuse the loaded package.

React's native `useId` supplies a per-instance DOM namespace. Each rendered
goal, context and inspection control receives its own native IDs, preventing
collisions both across split goals and across concurrent Iris widget instances.

## Review and testing

The 2026-09-11 review reproduced duplicate DOM IDs in split goals before fixing
them. Browser regressions now check uniqueness, each shared hypothesis's
`aria-controls` target, and independent inspection closing. The view no longer
encodes selected references as strings or owns native Promise continuations.

Use Beam for focused Lean development, then a Lake dependency build and the
browser test for changes to client hooks or the view. `lake test` alone does
not execute the browser scripts. SSR smoke checks package integrity and the
loading shell; it does not test effects or RPC. See the exact commands and
recorded results in [the current review](widget-review-435.md). The older
[4.32 migration note](widget-native-rpc.md) is historical.

Remaining acceptance work includes manual VS Code/theme/screen-reader checks,
server restart and expired-reference cases, preserving useful RPC error details,
and React list keys before upstreaming. See the current review for available
upstream bindings, and the historical [VIR API review](vir-widget-api-review.md)
for earlier dependency findings. No upstream
issue or PR has been opened by this review.
