# Iris proof-mode widget

A Lean-authored VIR panel beside the normal Tactic state, aimed at Iris users.
Open `Iris/IrisTest/ProofMode/WidgetDemo.lean`; setup and demo positions are in
[the runbook](vir-demo-runbook.md).

## What the card shows

The card groups persistent (`□`) and spatial (`∗`) hypotheses in context order,
followed by the target. Native infoview terms retain contextual hover and
Ctrl/Cmd-click definition navigation. The header shows the outer WP/fupd mask;
an invariant's namespace stays visible while its body is folded initially.

Inside a tactic, the labelled card always projects its **before-state**. Changes
appear immediately below the affected row as `↳ tactic: …`; unchanged rows stay
quiet. New hypotheses follow their context, departures say “no longer in
context”, and a closed goal is labelled closed. Splits show each resource's
resulting goals and all resulting targets. No label claims that a resource was
consumed or framed. Outside a tactic, the card shows the selected Iris state.

Ingress is `Iris.ProofMode.parseIrisGoal?` on an instantiated goal expression in
its saved context. Comparisons use Lean's selected `TacticInfo`, assignment
reachability for goals, and `IVarId` for resources, within that one tactic.
Propositions are compared as instantiated `Expr`s; never match printed names
or text. Ambiguous correspondence, duplicate identities, changed proposition
domains or incompatible shared local declarations produce an unavailable reason.

## Module map

Paths below are relative to `Iris/Iris/`.

- `ProofMode/Widget.lean`: panel entrypoint, package capture and runtime location.
- `ProofMode/GoalChanges.lean`: saved before/after states and typed correspondence.
- `ProofMode/ResourceStatus.lean`: resource-change status shared with the view.
- `ProofMode/Widget/Model.lean`: display metadata, native code slots, wire version.
- `ProofMode/Widget/Rpc.lean`: goal selection, projection and snapshot RPC.
- `ProofMode/Widget/Details.lean`: typed mask/invariant recognition and fragments.
- `ProofMode/Widget/Diff.lean`: native expression-diff adapter and printer fallback.
- `ProofMode/Widget/Vendor/ExprDiff.lean`: unchanged Lean 4.35 diff definitions.
- `ProofMode/Widget/Client.lean`: RPC objects, React hooks and snapshot lifetimes.
- `ProofMode/Widget/View.lean`: cards, native terms, annotations and disclosures.
- `ProofMode/Widget/Style.lean`: compact layout using VS Code theme tokens.
- `Std/PPQuotations.lean`: experimental quotation-display option.
- `HeapLang/Notation.lean`: value formatting, including the quotation option.
- `BI/Notation.lean`: iProp formatting, including the quotation option.

Tests and the optional tour live under `Iris/IrisTest/ProofMode/`; quotation
regressions live in `IrisTest/HeapLang/PPQuotations.lean`.

## Boundaries to preserve

Only display metadata crosses the JSON-to-Lean boundary. Native `CodeWithInfos`,
RPC references and sessions stay JS objects passed directly to InteractiveCode.
Each code slot is printed at its own root in the corresponding saved context.
Card/disclosure keys preserve presentation across edits, using identity first
and a positional fallback where needed. Semantic references never follow that
fallback. During refresh, old content stays visible as plain text while its
native handlers retire; accepted replies mount fresh native terms. Failure
keeps the previous text with an error, and leaving Iris clears the card.

`Widget.lean` imports **and meta-imports** `View`: package capture reads runtime
IR during elaboration, so Lake must track implementation changes as well as the
public interface. Keep both. Keep artifact caching enabled and the checked-in
Lean/VIR pins; rebuilding or changing dependencies requires a Lean server restart.

## Two display experiments

`pp.iris.quotations` defaults to `true`, preserving ordinary output. The widget
selects `false`, as does the SpinLock demo locally. Existing-syntax formatters
hide `hl_val(…)` around literals/pairs/injections and the `iprop` keyword,
retaining grouping and native semantic tags. This adds no parser notation;
the display may not re-parse. `hl(…)`, embedded `v(…)`, function-value quotation
boundaries and escapes remain. `some` is an actual optional cell value. A `Val`
variable `v` differs from the Boolean literal `#b`.

Expression highlighting vendors Lean 4.35's private `exprDiff`/`addDiffTags`
helpers, retaining their Apache 2.0 header and E.W. Ayers attribution. **Delete
the vendor file once Lean exports these APIs.** Our adapter marks a stripped
wrapper while leaving its identical argument quiet. If printing drops a changed
subterm's tag but retains descendants, it marks the nearest printed ancestor;
wholly hidden arguments stay quiet. Native text and semantic contexts are kept.
Failures preserve full native terms; interrupts propagate. This is a structural
diff, not a test of logical equivalence, and WP-to-fupd changes can be coarse.

## Checks and limits

Run the build in the runbook, then `lake test` from `Iris/`. From the repository
root, run `node scripts/widget-browser-smoke.mjs` and the
[real VS Code gate](../scripts/vscode-e2e/README.md). Lean tests cover typed
projection, pairing/refusals, split/closed goals, details, quotation output,
expression tags and checked tour markers. Browser tests cover held replies,
stale actions, failure/cancellation, native terms and continuity. VS Code checks
exercise the actual extension, including definition navigation, masks/folds,
resource/goal annotations, diff spans, edits and optional-tour navigation.

`node scripts/widget-downstream-smoke.mjs` additionally tests Iris as a dependency
and relocation; it needs the same runtime and dependencies. It does not settle
packaging: VIR remains a required dependency and the panel's default runtime
path assumes the Iris workspace. Downstream users must provide the runtime there or override that path.

The widget does not replace Lean's local context or normal goal view. Full
keyboard/accessibility policy, enclosing-subterm selection, long-session memory
measurement and expression elision remain open. Mask/invariant recognition is
bounded to typed top-level shapes; unrecognized terms use the canonical native
rendering. The tour is a separate, opt-in demo widget, never production UI.
