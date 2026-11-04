# Proposal: compare Iris resources across proof steps

**Design only; maintainer decision required.** Keep this beside Tactic state.
For the simple question “what changed in this expression?”, Lean's built-in diff
already covers much of the Heap example. A second coloured term diff alone would
add little; keeping the present widget without resource history is a valid outcome.

## Existing baseline and possible added value

In real VS Code, Tactic state already marks the upcoming store's changes in red,
including `l`, `v` and the program. The captured run also marks `l'` and `w`
although `Hframe`'s proposition stays unchanged: typed resource status could make
that preservation explicit. Lean's `getInteractiveGoals` uses tactic
before/after data and `diffInteractiveGoals` to decorate `CodeWithInfos` with
`diffStatus` tags; upstream `InteractiveCode` renders them. Our Iris projection
currently pretty-prints each proposition afresh and does not retain those diffs.

The possible addition is **both selected states visible together, organised by
Iris resource identity**: changed, added, removed/unpaired and preserved rows,
with unchanged resources collapsible. Heap's `Hl` would show `l ↦ some v` beside
`l ↦ some v'`, while `Hframe : l' ↦ some w` stays visible as preserved. SpinLock's
`Hpt` changes to the `false` cell and loses later; `Hcond` loses later while
`Hinv`, `Hl : locked γ` and `HR` remain. Keep target/mask changes separate.

“Consumed”, “framed”, or “opened/closed this invariant” are stronger explanations
than two snapshots establish. Removed resources may be renamed, replaced or
moved to another branch; preserved resources are not necessarily framed by the
tactic. Use those labels only with tactic/invariant provenance. An Iris-specific
view could then group exposed resources with their invariant and explain closing
obligations. First ask the authors whether this helps beyond the existing diff.

## Which previous step, and which goal?

Initially, explicitly pin a **before position and goal**, then select an after
position/goal in the same document version and elaboration generation. Label both
positions. The baseline is neither the last cursor event nor the previous source
line. An edit or server restart invalidates it. Use the Heap `heap-store` →
`heap-load` and SpinLock `spin-open` → `spin-stored` pause points as examples.

For one tactic, reuse Lean's before/after provenance and parent-goal relation
where available. Arbitrary pinned positions need explicit goal pairing when IDs
change or goals branch/disappear. List order, user names and the widget's
collapse-key fallback cannot establish semantic correspondence.

## Reuse upstream diffs; add only the missing resource layer

Prefer existing diff data for the **same tactic pair and expression root**.
`InteractiveCode` already understands native diff tags; no new highlighting
renderer is needed. Whole-goal tags, however, refer to the enclosing `Entails'`
expression. Our independently printed Iris propositions have different roots.
Do not copy their paths, infer spans from text, or assume the cursor's diff
compares the user's pinned pair. Reuse requires a verified typed subtree
projection/rebasing contract; without one, leave token-level highlighting to
Tactic state and show whole before/after propositions in the widget.

`parseIrisGoal?` supplies `Hyps.hyp` nodes with `IVarId`, persistence and typed
expressions. Pair resources by `IVarId` within the same generation and compare
expressions under frozen contexts/metavariable assignments, without text matching.
Both sampled stores preserve cell IDs, even when row order changes; other tactics
may not. Structural inequality is not semantic inequivalence. `IrisGoal` does
not itself supply history, goal ancestry or consumed/framed provenance; the
current display strings are insufficient for that server-side comparison.

Lean 4.35 publicly exports `diffInteractiveGoals`; lower-level `exprDiff` and
`addDiffTags` are internal module definitions. If safe per-resource expression
diffs become necessary, seek a supported upstream adapter instead of duplicating
the algorithm or importing private internals. A small typed resource comparison
would supplement, not replace, the existing expression diff.

## Failure boundaries and decision

Show unpaired/unavailable states for fresh IDs, incompatible contexts, ambiguous
branches or failed/stale requests. Never silently advance the pin. Retain only
one baseline and the current snapshot; invalidate on edits/restart and release
on replacement/unmount. Baseline text can remain noninteractive until its original
RPC/position context is supported; never borrow current-goal subterm paths.

Decision: is explicit resource pairing and simultaneous before/after display
useful enough to build, or does Tactic state's existing diff meet the authors'
needs? No history, diff mapping or resource-status code is added by this proposal.
