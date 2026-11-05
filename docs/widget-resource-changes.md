# Proposal: compare Iris resources across proof steps

**Round D: the tactic-local prototype annotates its before-state in place.** The Iris
authors’ feedback will decide whether this becomes a feature. Pinning and token
diff mapping below remain proposals. Keep this beside Tactic state.
Lean's built-in diff already covers much of “what changed in this expression?”
A second coloured term diff adds little; keeping the widget without resource
history is a valid outcome.

## Existing baseline and possible added value

Tactic state already marks the upcoming store's changes in red. Our real VS Code
capture marks `l`, `v`, the program, and also `l'`/`w` although `Hframe`'s
proposition stays unchanged. Lean's `getInteractiveGoals` uses tactic before/after
information and `diffInteractiveGoals` to decorate `CodeWithInfos`; native
`InteractiveCode` renders those tags. Our separately printed propositions omit them.

Possible added value is **both states visible together, grouped by Iris resource
identity**, annotating changed and added resources, context departures, and split destinations. Unchanged rows stay quiet. Heap's `Hl` goes
from `l ↦ some v` to `l ↦ some v'`; `Hframe` stays preserved. SpinLock's `Hpt`
changes to the `false` cell and loses later; `Hcond` loses later while `Hinv`,
`Hl : locked γ` and `HR` remain. Show target/mask changes separately.

“Consumed”, “framed”, or “opened/closed this invariant” require tactic/invariant
provenance. Two snapshots alone cannot distinguish consumption from renaming,
replacement or movement into another branch. Preserved does not imply framed.

## Which previous step? Start with the tactic under the cursor

**Recommend the selected tactic's before/after pair first.** Reuse Lean's
selection of tactic information and its saved contexts, rather than guessing
from source lines or cursor history. Label the tactic/range and both sides.
At `heap-store` or `spin-open`, selecting `wp_store` compares against the states
illustrated at `heap-load` or `spin-stored`. Moving onto `wp_load` selects that
new tactic's pair.

| Model | User effort | Branching and multiple goals |
| --- | --- | --- |
| Tactic under cursor, first prototype | Move the cursor; no pin or baseline management. | Use tactic parent/successor data. Group each before-goal with its after-goals; allow choosing which branch to expand. Never silently select the first result. |
| Explicit pin, later extension | Choose before/after positions and goals; re-pin after edits/restart. Supports several tactics or distant states. | Correspondence across the span is harder; require explicit goal pairing when ancestry is unavailable. |

A solved goal is closed, not “all resources consumed”. Keep unchanged siblings
distinct. Missing/failed elaboration or ambiguous ancestry yields unavailable or
unpaired results. Names, list order and collapse keys never establish identity.
Both modes check document version/generation: recompute the tactic pair after
edits; invalidate a pin.

## Reuse upstream diffs; add only the missing resource layer

Prefer existing diff data for the **same tactic pair and expression root**;
`InteractiveCode` already renders it. Whole-goal paths refer to the enclosing
`Entails'`, whereas independently printed Iris propositions have different roots.
Reuse needs a verified typed subtree projection/rebasing contract. Do not copy
paths or infer spans from text; without that contract, leave token highlighting
to Tactic state and display whole before/after propositions. A future pin cannot
assume the cursor's diff compares its chosen pair.

`parseIrisGoal?` supplies `Hyps.hyp` nodes with `IVarId`, persistence and typed
expressions. Pair resources by ID within one generation and compare expressions
under frozen contexts/metavariable assignments. Both sampled stores preserve cell
IDs despite row reordering; other tactics may not. Structural change is not
semantic inequivalence. `IrisGoal` alone provides neither history nor ancestry;
the current display strings cannot support this server-side comparison.

Lean 4.35 exports `diffInteractiveGoals`; lower-level `exprDiff`/`addDiffTags` are
internal. If per-resource expression diffs become necessary, seek a supported
upstream adapter rather than duplicating the algorithm or importing internals.

Retain only the selected comparison; release it on replacement/unmount. Never mix
elaboration generations. Before-state text can remain noninteractive until its
original RPC/position context is supported; never borrow current-goal paths.

The prototype uses `FileWorker.findGoalsAt?`, the same tactic selection as Tactic
state, and assignment reachability from `mctxAfter` for goal ancestry. It compares
instantiated proposition Exprs under the two saved contexts, pairs only `IVarId`,
and refuses ambiguous ancestry, duplicate IDs or changed shared local bindings.
All branches remain visible; a closed goal is labelled closed. The card always shows the selected tactic’s before-state, even where the normal
infoview selects the after side. It preserves that state’s context order. Changed
rows carry a subordinate `↳ tactic:` and native new proposition; unchanged rows
have no annotation. Context departures say “no longer in context”, additions
follow the existing rows in their resulting context, and split destinations use
the tactic’s full resulting-goal order. Targets are compared with the same
saved-context guards and annotated too. Both sides use native `InteractiveCode`.
No pinning, subterm highlighting or path rebasing is implemented.

Feedback question: does this resource comparison add enough beyond Tactic state's
diff to retain and refine?
