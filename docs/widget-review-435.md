# Widget review and Lean 4.35 migration — 2026-10-30

## Checkpoint

`feat/proof-mode-widget` is rebased onto Iris `origin/master` at
`fb21a8af` (`local stepindex` / `@[indexed]`, PR #729). Both workspaces use
Lean 4.35.0. Upstream lint settings and library precompilation are retained,
along with the branch's artifact-cache settings.

VIR is pinned to `81de859a3ba1cb5da8bc5f128af025dd5a40b343`, the last
mainline commit with `leanprover/lean4:v4.35.0`. The following commit,
`5a5614b8`, upgrades to 4.36.0-rc1. The older `4.35` tag points to `225218e1`;
it is not the source/runtime pairing used here.

The pinned runtime resource is
`ab3614c15934e54b9fa85b0891e6da56d239d09d04c7a2f3177980b2cec6a1d7`.
The setup script uses VIR's validating Lake acquisition target, checks that
resource identity and the payload hashes, and installs the declared Wasm entry.
It does not select an independent SDK or rebuild Wasm locally. Follow the
[runbook](vir-demo-runbook.md) for setup and testing.

The pre-rebase branch is retained as
`archive/proof-mode-widget-before-435-20261030` at `7cef7fa2`. Historical isolated
4.32 acceptance files and the VIR producer checkout were not modified.

## Migration and corrected behavior

- `vir_proof_widget View.app` generates the factory and fingerprinted package
  descriptor. `panelProps` supplies the workspace-relative runtime path.
  The factory remains exported for the standalone package smoke test.
- JSX uses `jsx%{...}` and click callbacks use `React.SyntheticEvent`.
  The dependency-list helper now uses public `Js.erase`/array operations instead
  of unfolding VIR's representation types.
- The application effect now observes document edits and native RPC session
  replacement, as well as panel props. Previously, a same-position update that
  left props unchanged could leave stale goals. A regression edits the proof
  in memory at the same cursor and checks that the target changes from `S` to
  `T`, with no additional `buildIRPackage` call.
- Browser tests request the real generated descriptor through
  `Lean.Widget.getWidgets`. Obsolete root arrays and package polling assertions
  are replaced by fingerprint reuse and unavailable-fingerprint error checks.

The typed goal boundary remains sound: `Rpc.lean` enters each saved goal's
metavariable context and calls `Iris.ProofMode.parseIrisGoal?` on its instantiated
target. It traverses `IrisGoal`/`Hyps` into the display domain; it does not parse
rendered syntax. This remains the appropriate existing Iris interface for
recognizing goals. Contextual inspection retains elaborator-owned expressions
and binder contexts in a server snapshot.

## Findings at the migration checkpoint

All three findings below are addressed by the follow-up described in
[the UI development plan](widget-ui-development.md). This section retains the
review rationale from `8c1db345`.

1. **RPC failures lose useful diagnostics** (`Client.observe`, `useInspection`,
   `application`). The rejection handler discards the native error and substitutes
   a generic message. A registration error, expired reference and malformed
   reply can therefore look alike. Preserve a readable code/message, keeping the
   native error object until display is needed. The VIR shell's package error
   formatting passes; this finding concerns Iris's own RPC adapter.
2. **Dynamic children lack explicit React keys** (`View.contextSection`,
   `region`, tagged-term arrays, and `Client.Component.render`). Model IDs are
   currently DOM/data attributes, not React keys. Add a native optional key to
   the component helper and keys for the dynamic element arrays. Whole-snapshot
   remounting currently prevents cross-snapshot state reuse, so this is mainly
   React hygiene today and a prerequisite for preserving state during updates.
3. **Obsolete requests still run** (`Client.useEffect`/`observe`). Lifetime guards
   correctly suppress stale success and failure, but do not cancel server work.
   VIR now exposes `RpcSession.callWithOptions` and native `AbortController`
   bindings. Adopt cancellation if cursor movement or expensive projections
   cause measurable backlog; retain publication guards regardless.

## Design and upstream direction

The 360-pixel browser capture shows a compact judgment: persistent and spatial
contexts, a horizontal rule, and a turnstile target, with one small goal header.
Canonical Lean text and keyboard inspection work. The current small fixed font
sizes deserve a VS Code zoom/theme and screen-reader review before wider use;
the headless light-theme capture does not establish accessibility acceptance.

VIR now exposes `Infoview.interactiveCode`, the actual upstream React component,
and native `CodeWithInfos` accessors. This is the most useful next integration
experiment for infoview-style term interaction. It requires genuine native
`CodeWithInfos` and the upstream contexts: the current `TaggedText Nat` projection
cannot be passed as a substitute. Keep typed Iris structure in the display
domain and carry the richer leaf data as native references alongside it. Compare
hover/navigation behavior before replacing the existing contextual inspector.
The browser harness intentionally throws if that currently unused host component
is invoked; it does not claim to test upstream hover behavior.

No reproduced VIR blocker remains on this 4.35 pairing. Fresh-server acquisition
exercises imported `readAsset` and `buildIRPackage`, followed by Iris `state`
and `inspect`. This result does not diagnose or retroactively validate the old
4.32 registration regression.

## Migration validation (`8c1db345`)

Commands were run with `LAKE_ARTIFACT_CACHE=true`,
`LAKE_CACHE_DIR=/home/egallego/.cache/mathlib`, and
`LAKE_RESTORE_ARTIFACTS=true` where Lake was involved:

- `node scripts/widget-setup-runtime.mjs`: validated runtime installed.
- From `Iris/`, `lake build IrisTest.ProofMode.Widget IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir`:
  passed, including 46 generated package members and one exported factory.
- From `Iris/`, `lake test`: passed.
- `node scripts/widget-runtime-smoke.mjs`: all 46 member hashes, runtime factory,
  and server-rendered loading state passed.
- `IRIS_WIDGET_PACKAGE_DELAY_MS=500 node scripts/widget-browser-smoke.mjs`:
  passed at 360 pixels with 39 real RPC requests. Covers keyboard activation,
  canonical text, nested binders, repeated occurrences, rejection, stale
  selection/snapshot races, split goals, unique IDs, ARIA/close isolation,
  same-position edits, package reuse, unmount, ordinary goals, readable package
  failure, Strict Mode, and slow startup.
- `git diff --check`: passed.

Focused Client/View/entrypoint diagnostics were checked with Lean Beam. Its
owner completed shutdown before the final clean local batch build. These are
local results, not CI evidence. Earlier harness failures were missing host
stubs, an unwritable default cache path, and an obsolete error-text assertion;
the final run used the writable cache and the updated contract.

Not exercised: a full IrisMath build, a real VS Code session with server restart,
manual theme/screen-reader use, or the proposed upstream `InteractiveCode` path.
