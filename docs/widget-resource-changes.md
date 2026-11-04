# Proposal: a pinned comparison of Iris resources

**Design only; implementation requires a maintainer decision.** Keep this beside
the normal Tactic state. The first useful question is “what happened to the
resources across this step?”, not a diff of pretty-printed goals.

## What is the previous step?

For a first version, the user explicitly pins a **before position and goal**,
then moves to an after position. “Previous” means that pinned snapshot, not the
last cursor event, the last completed RPC, or the previous line of source.
Record document URI/version, elaboration generation, exact LSP position and
selected goal. Label both positions visibly. Moving the cursor within a tactic
must not silently change the baseline. An edit or server restart invalidates the
comparison; ask for a new pin rather than comparing across changed elaboration.

Start with the two Heap pause points `heap-store` → `heap-load`, and the two
SpinLock points `spin-open` → `spin-stored`. A tactic can create several goals or
solve one: equal `MVarId`s establish identity only when they survive, and list
position is not proof ancestry. For changed goal IDs, require an explicit
before/after goal choice and describe it as a user-selected comparison. Automatic
successor selection would need tactic-info provenance and a branching policy.
Never reuse the widget's ordinal collapse fallback for semantic correspondence.

## What is shown?

Keep a compact list of changed, added and removed resources, with the unchanged
count available to expand. Show complete canonical before/after propositions
initially, not token-level edits. For Heap, `Hl` changes from `l ↦ some v` to
`l ↦ some v'`, while `Hframe : l' ↦ some w` is unchanged. For SpinLock,
`Hpt` changes from `▷ l ↦ some hl_val(#b)` to the `false` cell without later;
`Hcond` loses its later. `Hinv`, the ghost token `Hl`, and `HR` provide useful
unchanged context. Show the WP-to-invariant-closing target transition separately;
do not describe it as a resource mutation. Use words/icons as well as colour.

## Typed correspondence, without text matching

`parseIrisGoal?` gives `Hyps.hyp` nodes with `IVarId`, persistence and typed
proposition expressions. Within one elaboration generation, pair hypotheses by
`IVarId`, compare persistence and the underlying `Expr`s in their saved contexts,
and use pretty-printing only for display. The current `wp_store` implementation
explicitly removes and re-adds the cell with the same `vid`; this supports the
Heap example without matching the spelling `Hl`. The recorded Heap and SpinLock snapshots preserve their respective cell IDs
across the store, including when row order changes. Check that contract before
generalising it to other tactics. These IDs are Iris identifiers,
not Lean local-variable identifiers or globally durable resource IDs.

Begin with bounded structural expression comparison after instantiating known
metavariables. “Unchanged expression” is a precise claim; a structural change is
not proof of semantic inequivalence. Avoid speculative unification or unbounded
normalisation merely to make a diff prettier. Snapshot the relevant context and
metavariable assignments so later assignments cannot rewrite the baseline.
The current `DisplayGoal` strings/code objects are insufficient for this operation:
a server-side comparison request would retain the typed inputs and emit typed
change records. `IrisGoal` supplies resource structure, but not history or goal
ancestry by itself.

## Failure modes and boundaries

Fresh IDs, duplicate user names, context changes, branching, framing/consumption,
and custom tactics may defeat pairing. Show “unpaired/added/removed” or
“comparison unavailable”, never infer a replacement from equal names or nearby
text. Missing Iris states, stale replies, parse failures and document edits must
not silently advance the pin. Bound retention to one baseline plus the current
snapshot and release it on replacement/unmount. Old-snapshot hover/navigation
requires its original RPC/position context; a first version can display baseline
text only. Enclosing-subterm paths must not be borrowed from the current goal.

Decision requested: is an explicit pin-and-compare interaction worth prototyping,
and which goal-pairing ambiguities should be shown to the user first?
