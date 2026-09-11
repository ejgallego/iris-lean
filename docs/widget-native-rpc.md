# Contextual subterm inspection — 2026-09-10

Iris adopted VIR compatibility checkpoint `be6931c` (PR #171 at `8750e1b`,
Lean 4.32.2). It now pins `8032fd34add0b75d4f59c82382e2a57b4c2522a4`, adding
two [shell error/startup fixes](widget-shell-errors.md).
This replaces the old `ResolvedRef`/`ExprWithCtx.save`/`Rpc.resolve` interaction.
The widget no longer uses the local `ReactRpcWidget`/`RpcJson` bridge.
The exact VIR pin is published on
[`fix/iris-widget-errors`](https://github.com/ejgallego/lean-vir/tree/fix/iris-widget-errors);
Iris review changes are on
[`feat/proof-mode-widget`](https://github.com/ejgallego/iris-lean/tree/feat/proof-mode-widget).

For the contributor-facing code map and the 2026-09-11 cleanup, see the
[maintainer guide](widget-maintainer-guide.md). Dependency defects and API
ergonomics are separated in the [VIR API review](vir-widget-api-review.md).

## Implemented boundary

Goal provenance is unchanged: the server enters each saved goal's metavariable
context, instantiates the target, calls `Iris.ProofMode.parseIrisGoal?`, and
traverses the typed `IrisGoal`/`Hyps` result. No goal or proposition text is parsed
to recognize Iris structure.

`RenderedTerm` now includes the canonical `TaggedText Nat` tree, alongside its
plain text, type text, summary and display ID. Each tag number indexes a saved
expression in the owning server snapshot. The mapper consumes the delaborator's
term-info variants only at this adapter boundary, retaining the expression,
local context and elaboration context in Iris's own `SavedTerm` structure.
Internal info nodes and raw expressions never enter the display JSON.

The native RPC response has two fields:

- `display`: a JSON string containing `WidgetState` version **3**.
- `snapshot`: a real `WithRpcRef Snapshot`, registered by the official infoview
  client. Its value is kept opaque and sent back unchanged for inspection.

`inspect` receives that snapshot reference and a bounded array index, then
pretty-prints the actual expression and inferred type in its saved context.
A display ID, repeated spelling or React key is never used to find an expression.
The native session owns reference registration/release; VIR owns the lifetimes
of JavaScript resources retained by Lean callbacks and components.

## Client and interaction

The ordinary VIR `Surface` shell supplies a position-specific native RPC
session. `Client.lean` requests snapshots using native Promises, decodes only
the display string, and constructs the Lean-authored snapshot view once per
accepted response. All application behavior remains in Lean; the added
JavaScript files are regression-test drivers, not production widget code.

The renderer keeps the tag tree but displays innermost-tagged text fragments
as inline buttons. Untagged text and whitespace remain ordinary text; buttons
never nest. Click a span, or focus it and press Enter, to open inline contextual
inspection. Use × to close it. The complete canonical text is preserved without
reconstructing it from a mathematical view.

Each snapshot request and selected-span request owns an effect-local active
flag. Effect cleanup retires that flag. Late success and late failure are
observed but cannot mutate a retired selection/snapshot or resurrect an
unmounted widget. Fulfillment-handler exceptions also reach the failure path.
Requests are currently **not aborted**: suppression of stale UI effects and
transport cancellation are distinct concerns.

New snapshots conservatively reset selection and collapse state. Within one
snapshot, goals collapse independently. No correspondence across snapshots is
guessed from names, indices or text. No global reference table is introduced.

## Try it

Open the existing worktree's `Iris/` directory in VS Code, restart the Lean
server, and open `IrisTest/ProofMode/WidgetDemo.lean`:

1. At `widget-position-contexts`, inspect `P`, `R` or `S` in the target.
2. At `widget-position-split`, expand the second goal and inspect its target.
3. At `widget-position-binders`, inspect `n` or `m` before `iintro`: their saved
   binder contexts supply the type `Nat`.

The existing runtime path is unchanged. This checkout uses the rebuilt 4.32.2
Wasm with SHA-256
`8aca7930f8f0dee9bd88ee6aceb472dab45f3ded65d52740176f6da5dbec71e2`.

## Validation commands

From `Iris/`, after stopping the owned Beam session:

```sh
export LAKE_ARTIFACT_CACHE=true
export LAKE_CACHE_DIR=/home/egallego/.cache/mathlib
export LAKE_RESTORE_ARTIFACTS=true
lake clean
lake build IrisTest.ProofMode.Widget IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir
lake test
```

From the worktree root, with the same environment:

```sh
node scripts/widget-runtime-smoke.mjs
node scripts/widget-browser-smoke.mjs
node docs/notation-gallery/smoke.mjs
git diff --check
```

Beam supplied focused probes/checkpoints; dependency freshness across several
importers required a Lake build. The final clean build is separate batch evidence.
The SSR test now checks package hashes and native Surface factory/mount/loading;
it does not claim to execute React effects or native RPC.

Recorded results on 2026-09-10: the clean widget/demo/package build and full
`lake test` passed. The rebuilt package contains 38 verified members and 1,142
declarations. Runtime smoke, real-server browser acceptance (32 RPC calls,
360 px viewport), all 90 notation-gallery layout cases, and `git diff --check`
passed. These results do not replace the manual acceptance checks below.

Revalidated after the 2026-09-11 maintainer cleanup: the same cache-enabled
`lake clean`, widget/demo/package build and full `lake test` passed. Runtime
smoke verified 38 members (1,136 declarations). Browser acceptance passed with
34 RPC calls, including new unique-ID and shared-hypothesis ARIA/close-isolation
regressions. `node --check scripts/widget-browser-entry.mjs` and
`git diff --check` passed. The unchanged notation gallery was not rerun in this
review. Beam provided the focused typed-state probe and development checkpoints;
the final clean Lake build validated the complete dependency cone.

The browser test runs the actual VIR shell and Lean-authored widget against a
real Iris `lake serve` session with the official RPC client. It checks canonical
text, native Enter activation, contextual inspection, binders, distinct repeated
occurrences, both split goals, server rejection, delayed success/failure after
reselection, delayed snapshots, cross-snapshot inspection, unmount, ordinary
non-Iris goals, React Strict Mode and a 360 px viewport. Delayed outcomes are
genuine server results held by the test transport. Failure injection forwards
an invalid index to the real server; it does not fabricate an error response.

## Still outside this slice

- Hover popups, definition navigation and arbitrary semantic range selection.
- Mathematical presentation extensions, KaTeX, or production MathML rendering.
- Selective preservation of UI state across snapshots, request cancellation,
  and dedicated released-reference/server-restart tests.
- Deterministic downstream runtime packaging; publishing the source pin does
  not install the matching generated Wasm.
- Manual VS Code/theme/screen-reader acceptance. Browser fixtures are not a
  claim that the VS Code extension itself has been manually exercised.
