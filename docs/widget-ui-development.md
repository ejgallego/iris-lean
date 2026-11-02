# Developing the Iris widget UI

## What this pass fixes

The review follow-up preserves native RPC errors through React state and formats
checked message/code fields at display time. Server errors, native JavaScript
errors, string rejections, and absent/unknown values all have readable output.
Malformed successful replies take the same error path. Error text remains native;
the display model is still the intentional JSON-to-Lean boundary.

Dynamic goal, hypothesis, context and term children now have explicit React
keys. Goal/hypothesis keys come from model identity; piece indices are local to
one immutable snapshot. These keys do not establish identity across snapshots.

Each snapshot/inspection effect owns an `AbortController`. Cleanup retires its
publication guard before calling `abort`, and passes the exact native signal
through `RpcSession.callWithOptions`. Iris checks cancellation around inspection
and between goal projections. Cancellation is cooperative: an individual
pretty-printing operation may finish first. Late response guards remain required.

Proof text, resource glyphs and the turnstile follow the editor's configured
font size. Compact spacing is retained. This follows VS Code's documented
[webview theme/font variables](https://code.visualstudio.com/api/extension-guides/webview#theming-webview-content).
Collapse/close controls have a 24-pixel minimum size; native button focus remains
visible. This is a readability improvement, not an accessibility certification.

## Design process for the next slice

### Editing continuity checkpoint (2026-11-02)

The view's component types are built once. Refresh retains the old goal cards
with disabled term actions and `aria-busy`, without inserting a routine status
line or live announcement. Initial loading still has a status; failed refreshes
retain disabled cards alongside the error; successful empty replies remove them.
Every accepted snapshot gets a fresh semantic epoch, remounting inspections.

Presentation belongs to the document in the mounted panel, independently of
position-specific RPC sessions. Surviving goal IDs retain their card keys even
when their ordinal changes. If elaboration changes IDs, unmatched goals reuse
unclaimed previous slots at the same ordinal. This fallback carries collapse
only: it does not establish mathematical identity, and may carry collapse to a
different goal in that slot. Document changes, panel remounts, and a successful
empty state reset presentation. Expression references never follow these keys.

The browser regression moves the cursor within the same proof state and back,
types with cursor movement, and re-elaborates after adding an ordinary local.
It records goal IDs and checks retained card identity/collapse, no stale RPC,
fresh semantic nodes, and surviving-goal identity after a preceding goal is
solved. Held refresh adds no height or live region. Failure/recovery and moving
outside Iris remain covered. Collapse-control focus is checked across cursor
moves/edits. Term focus is measured separately: disabling and replacing semantic
nodes can still lose it. This must inform the native-renderer keyboard review;
full VS Code focus/scroll and screen-reader behavior remain untested.

### Remaining design work

The goal is fluent proof work: quickly understand a judgment, locate a resource,
inspect its meaning, and continue editing without losing one's place. Reliability
and density alone do not make this a finished UI.

1. **Choose real tasks and a corpus.** Keep the small demo for regression, then
   capture the `wp_load`/`wp_store` states in
   `IrisTest/HeapLang/HeapTactics.lean` and an invariant proof from
   `Iris/HeapLang/Lib/SpinLock.lean`. Record declaration, cursor position,
   source revision, and exact tagged text. Use the existing
   [notation showcase](iris-notation-showcase.md) for paper-inspired designs;
   keep its manually transcribed specimens distinct from live server output.
2. **Compare actual interaction prototypes.** Prototype upstream
   `Infoview.interactiveCode` for one proposition beside the current inspector.
   Compare keyboard use, hover, contextual type information, text selection and
   navigation. Use genuine native `CodeWithInfos` and the upstream providers.
   The current `TaggedText Nat` is not a drop-in substitute.
3. **Design editing continuity.** Specify loading, stale, error, empty and
   reconnected states. Preserve the user's view while new data arrives, but
   retire stale semantic actions immediately. Separate safe presentation state
   (collapse/scroll) from snapshot-owned inspection references. Do not preserve
   selection by matching variable names.
4. **Review visual alternatives against tasks.** Compare the current judgment
   layout with one quieter alternative, using the same long proof states.
   Examine wrapping, context alignment, resource distinctions, focus and
   inspection placement at narrow widths and larger fonts. Prefer progressive
   disclosure to extra headers. Follow the
   [APG disclosure semantics](https://www.w3.org/WAI/ARIA/apg/patterns/disclosure/)
   for genuine show/hide controls; design richer term interactions separately.
5. **Validate, then extend.** Require exact source-text preservation and correct
   contextual inspection before mathematical typesetting. Keep plain/tagged
   Lean rendering available when a notation has no presentation adapter.
   Measure request/render latency before adding caching or scheduling policy.

The next implementation slice should be the real `InteractiveCode` comparison.
It can expose native tagged-code leaves alongside the typed Iris goal domain,
without replacing the canonical `parseIrisGoal?` ingress.

## Where Beam would help

The current browser test maintains its own Lean process, RPC connections,
keepalives, release notifications, cancellation bridge, document edits and
diagnostic barrier. Beam could own that server lifecycle. The browser should
still use the official `RpcSessions` client and render actual React/VIR code.

The useful first addition is a **version-bound widget/RPC lease**, with these
capabilities (an API proposal, not a claim of current support):

- Discover widgets at an accepted document version/position through
  `Lean.Widget.getWidgets`, returning their real generated props and fingerprint.
- Route RPC calls through the same worker/session, preserving wire references
  and forwarding cancellation. Check the document version atomically at dispatch;
  specify whether an operation uses a retained snapshot or the live worker.
  Do not label a live RPC result as belonging to an earlier version.
- Expose session/generation identity and explicit release/close. Keep references
  tied to their owning session; server restart must make stale leases fail
  clearly. A document edit need not destroy still-valid saved-snapshot references.
- Deliver document-change/restart events to a browser bridge and provide a
  readiness barrier after edits. The browser retains its native reference graph;
  the CLI must not reconstruct references from display JSON or names.
- Record method, source version/position, request start/end, cancellation and
  native error code. Keep rendering, screenshot and accessibility capture in a
  separate browser layer; Beam need not become a browser automation framework.

An initial end-to-end acceptance case is the existing browser cancellation probe:
start inspection, select another term, observe `$/cancelRequest`, and verify
both Lean's cancellation count and the new visible result.
Then test same-position edits and worker replacement with outstanding references.
These are concrete contracts we can migrate out of the hand-written harness.

## Independent design review brief

A second reviewer, including Claude, would be useful for a separate critique of
the same artifacts. Give it the notation gallery, actual widget captures in
light/dark/high-contrast themes, a larger proof state, and this task:

> Review this as an everyday Iris proof interface. Walk through finding a spatial
> resource, inspecting a nested binder, splitting a goal, and continuing after an
> edit. Identify the three highest-impact usability problems, with evidence from
> a specific state. Sketch one alternative using the same content. Evaluate
> keyboard focus, font scaling, narrow-width wrapping and stale/error states.
> Preserve exact source text and expression identity. Distinguish observed issues
> from assumptions; do not claim mock screenshots demonstrate working behavior.

Use the critique to compare decisions, then implement and test the chosen slice
in the Lean widget. The same brief can also be used in an Iris-author review.

## Follow-up validation

The Lean widget/demo/cancellation-fixture/package build and `lake test` pass.
The standalone runtime smoke validates 47 package members and the loading shell.
The real-server browser suite covers native message/code retention, malformed
replies, unknown rejections, React keys, cancellation reaching Lean on reselection
and close, navigation/unmount abortion, and the existing stale-response cases.

The browser matrix is light/360px/14px text, dark/320px/22px text with delayed
package loading, and high-contrast/280px/28px text. Captures are inspected for
layout; automated checks cover overflow, configured term font size, canonical
text, keyboard activation, IDs and ARIA isolation. These are simulated theme
variables, not a real VS Code or screen-reader acceptance run. Manual host
integration, focus continuity and richer proof states remain necessary.
