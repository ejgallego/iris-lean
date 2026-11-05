# Native expression-diff POC (Round H)

Changed resource propositions and targets carry Lean's native diff tags: the
before term has removed styling and the `↳` term has inserted styling. Unchanged
resources stay quiet. Identity, refusal cases, context order, panel/card keys,
and ordinary full-term text remain unchanged. This is presentation of structural
changes, not a claim about resource consumption or logical equivalence.

## Provenance and application

`Iris.ProofMode.Widget.Vendor.ExprDiff` contains the `ExprDiffTag`/`ExprDiff`
support and `exprDiffCore`, `exprDiff`, `addDiffTags` from Lean 4.35.0's
`Lean/Widget/Diff.lean`. The Apache header and E.W. Ayers attribution are retained.
The copied definitions are byte-for-byte identical; only imports, visibility
and the isolated `Iris.ProofMode.Widget.Vendor.Lean435` namespace differ.
Delete this file when Lean exports those functions.

The widget applies that code to each already-paired `IVarId` resource and each
resulting target. Both terms are printed independently at root in their own
saved contexts; diff computation uses the after context. Existing native
`CodeWithInfos` objects receive tags, with no text parsing, new JS renderer,
protocol schema change, or custom diff CSS. Invariant namespace/body fragments
are diffed at their own roots too. Added/departing resources retain their existing
Round D labels; there is no invented expression on the missing side.

## Dropped wrappers

The separate Iris adapter recognizes a unique, structurally identical application
argument: when `after` is that argument of `before`, only the dropped wrapper
is marked. It preserves the argument's entire tagged subtree. Repeated identical
arguments are ambiguous and use the ordinary diff instead.

An Iris unexpander can lose the argument's root annotation when unpacking
`iprop(…)`; SpinLock's `▷ if …` exposed this in the real-state regression.
For stripped later/fupd terms only, a local printer can reattach that root in
the original saved context. It accepts the repair only when the rendered text
is byte-identical. No global delaborator or unexpander changes. If the argument
cannot be recovered safely, use the vendored diff; if diffing fails, retain the
native term. Interrupts still propagate.

## Bounds of the prototype

Lean's diff is deliberately coarse when the outer expression changes, e.g.
SpinLock's WP becomes an fupd. Both complete targets remain visible. The POC does
not elide subterms. Lean's `Delaborator.omission` provides native `⋯` hover, but
identifying maximal unchanged subterms across that transition requires additional
correspondence and binder handling which this vendored diff does not supply.
That stretch item was reported and deferred rather than implementing another diff.

`IrisTest.ProofMode.WidgetDiff` checks exact highlighted spans and direction tags
for values, a WP program step, no change, stripped later/fupd wrappers, and the
actual saved SpinLock Hcond states. The browser and VS Code gates inspect diff
classes inside the Iris card, including quiet frames and wrapper bodies; existing
hover, definition navigation, optional-tour and continuity checks remain enabled.
Review screenshots and geometry are under `.tmp/round-h/`.
