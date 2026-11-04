# Maintaining the Iris proof-mode widget

The widget is an opt-in companion to the normal infoview. Its application code
is Lean. VIR supplies React and browser bindings; it does not recognize Iris
goals. This guide describes the local Lean 4.35.0 prototype, not a proposed
change to Iris proof-mode semantics.

## Start here

Open the worktree's `Iris/` directory as the VS Code workspace and open
[`WidgetDemo.lean`](../Iris/IrisTest/ProofMode/WidgetDemo.lean). Restart the Lean
server after changing dependencies or rebuilding the widget package.

Start at the Heap store/load or SpinLock markers. Hover over proposition terms
for native infoview information; Ctrl/Cmd-click constants for definition navigation.
The collapse buttons retain keyboard activation. Enclosing-subterm selection and
a full native-term keyboard policy are still gaps.
The [runbook](vir-demo-runbook.md) contains the cache-enabled build command.
This worktree pins VIR's last mainline Lean 4.35 commit,
[`81de859a`](https://github.com/ejgallego/lean-vir/commit/81de859a3ba1cb5da8bc5f128af025dd5a40b343).
Run `node scripts/widget-setup-runtime.mjs` to install its published, verified
runtime. See the [4.35 review](widget-review-435.md) for migration details.

## Where to make a change

| Concern | File | Responsibility |
| --- | --- | --- |
| Display data | [`Model.lean`](../Iris/Iris/ProofMode/Widget/Model.lean) | Plain Lean metadata, native code-slot indices, shared JSON version |
| Iris meaning | [`Rpc.lean`](../Iris/Iris/ProofMode/Widget/Rpc.lean) | Typed goal projection and native tagged-code emission |
| Panel entrypoint | [`Widget.lean`](../Iris/Iris/ProofMode/Widget.lean) | VIR package root and native panel configuration |
| Layout and controls | [`View.lean`](../Iris/Iris/ProofMode/Widget/View.lean) | Goal cards, context rows, native terms, collapse |
| Density and theme | [`Style.lean`](../Iris/Iris/ProofMode/Widget/Style.lean) | CSS using VS Code theme tokens |
| Browser integration | [`Client.lean`](../Iris/Iris/ProofMode/Widget/Client.lean) | Native JS/RPC values, React state, effect lifetimes |
| Semantic regressions | [`Widget.lean` tests](../Iris/IrisTest/ProofMode/Widget.lean) | Actual elaborated Iris goals, binder contexts and occurrence identity |
| Interaction regressions | [`widget-browser-entry.mjs`](../scripts/widget-browser-entry.mjs) | Real-server behavior under upstream providers, races, native interactions |

For ordinary layout work, start in the view and style files. You should not
need to handle `Js.Any`, construct RPC objects, or change Promise callbacks.
`View.interactiveTerm` supplies the original native code object to upstream
`InteractiveCode`. `Client.useState` provides React-backed Lean values for small
controls such as goal collapse. There is no custom inspection RPC or inspector.

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

- Model IDs identify goals/hypotheses within an elaboration. Card keys preserve
  surviving goals first, with an ordinal fallback for collapse alone when IDs
  churn. No semantic reference follows that fallback.
- DOM IDs identify rendered occurrences. React's native `useId` supplies the
  opaque IDs for card/context/disclosure relationships.
- `RenderedTerm.codeIndex` selects one complete `CodeWithInfos` object in the
  current reply. Native tags inside it own their upstream RPC references and
  saved contexts. It is neither a DOM ID nor a subexpression path in the Lean goal.

`ppExprTagged` supplies contextual expression information, including binder
contexts. The native RPC client registers references nested in `SnapshotReply.codes`.
The view preserves those exact JS objects. Only `SnapshotReply.display` crosses
the intentional JSON-to-Lean boundary, yielding typed `WidgetState` metadata.
`Widget.lean` both imports and meta-imports `View`: `vir_proof_widget` captures
runtime IR during elaboration. A normal module import alone tracks the public
interface and can retain an old package after an implementation-only UI edit.
The meta import makes Lake track that implementation dependency. Do not remove
it as a duplicate import.

Version 4 is defined once in `Model.lean` and checked by the client. Do not
round-trip tagged code, session objects, React IDs or RPC references through JSON.

During refresh, cards and collapse remain while native terms become canonical
plain text. This unmounts their semantic handlers/popups before the new request's
effect runs. Each accepted snapshot mounts fresh native terms. A failed refresh
retains readable inactive content; a successful non-Iris state removes it.
Request cleanup retires publication before aborting the native controller.
The server checks cancellation between goal projections; a running pretty-printer
can finish first. Keep the late-success and late-failure guards. Cleanup does not
dispose the VIR runtime. A navigation activated before retirement may complete;
the renderer does not claim to cancel upstream's non-abortable navigation call.

Native reference release follows the upstream RPC client's object-lifetime/GC
mechanism. Iris holds only its current snapshot; no history is retained. Long
sessions and release latency still need measurement. Document edits and position
sessions trigger refresh; the code fingerprint stays independent of proof state,
so these changes reuse the package.

## Review and testing

The browser gate uses actual upstream `renderInfoview` providers, with a narrow
editor API bridge and bundled-widget-source substitution. It checks cursor/edit
continuity, retired native actions, native popup cancellation, binder hover,
definition callbacks, real Heap/SpinLock states, errors and server cancellation.
The ordinary Tactic state stays visible in the same host.

Use Beam for focused Lean development, then a Lake dependency build and the
browser test for changes to client hooks or the view. `lake test` alone does
not execute the browser scripts. SSR smoke checks package integrity and the
loading shell; it does not test effects or RPC. See the exact commands and
recorded results in [the testing surface](widget-testing-surface.md). The older
[4.32 migration note](widget-native-rpc.md) is historical.

Remaining acceptance work includes manual VS Code/theme/screen-reader checks,
server restart, expired-reference cases and long-session reference release.
RPC errors now retain native messages and codes until display, and the browser
suite checks errors, cancellation and absence of React key warnings. A
test-only server probe in `IrisTest.ProofMode.WidgetRpc` confirms that Lean
receives cancellation; the harness adds its import only to its in-memory file.
See the [UI development plan](widget-ui-development.md) for next steps and the current review for available
upstream bindings, and the historical [VIR API review](vir-widget-api-review.md)
for earlier dependency findings. No upstream
issue or PR has been opened by this review.
