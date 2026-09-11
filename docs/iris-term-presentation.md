# Annotated term presentation: proposed contract

Mathematical presentation proposal, 2026-09-08; its API remains unimplemented.
Review alongside the [notation gallery](notation-gallery/index.html) and
[widget design](proof-mode-widget-design.md). The canonical tagged-Lean slice
is now implemented in version 3; see [native-RPC migration](widget-native-rpc.md).
The mathematical presentation tree below remains a proposal.

## Boundary and ownership

Keep the existing structural path:

```text
elaborated target → parseIrisGoal? → IrisGoal / Hyps → DisplayGoal
                                                        │
                                    each proposition expression
                                                        ↓
                       tagged Lean fallback + optional presentation tree
                                                        ↓
                                 Lean-authored VIR component / renderer
```

The new layer enriches proposition leaves, not context recognition. Version 3
retains `ppExprTagged`'s tree with snapshot-relative indices. The native snapshot
owns saved expressions and their contexts; click/Enter inspection uses those
contexts. Mathematical layout, navigation and full hover popups remain future work.

An expression tree is not a presentation tree. One expression can appear in
several places, one visual unit can refer to several expressions, and punctuation
can have no expression at all. A binder header also needs more than a bare
expression without its local context.

## Candidate shape

The following is datatype pseudocode, not compilable Lean or a finalized JSON
schema. `TaggedLean`, reference handles, and binder metadata must reuse the
actual Lean/VIR facilities available after the cleanup.

```text
TermPresentation = {
  canonical : TaggedLean,                  -- authoritative source-copy payload
  mathematical? : Presentation
}

Presentation =
  text(style, literal)
  | sequence(children, breakOpportunities)
  | group(delimiters, body)
  | scripts(base, subscript?, superscript?)
  | enclosure(style, body)                  -- e.g. an invariant box
  | binder(header, body)                    -- explicit visual scope
  | annotate(Annotation, body)
  | leanFallback(TaggedLean)

Annotation = {
  displayKey : NodeKey,                     -- layout/React identity only
  label : String,
  targets : Array ReferenceKey,             -- zero, one, or several
  copyText? : String                        -- server-supplied source fragment
}

ReferenceEntry = {
  key : ReferenceKey,
  handle : OpaqueContextualServerReference,
  capabilities : Set { inspect, definition, selectExpression }
}

SnapshotEnvelope = {
  epoch : SnapshotKey,
  references : Array ReferenceEntry,
  goals : Array DisplayGoalWithPresentedLeaves
}
```

The reference table belongs to the snapshot, not to global display strings.
Do not serialize raw `Expr` values or invent reference handles from names. The
server retains the saved elaboration context needed to interpret a reference,
including bound variables and metavariables. The exact handle type and lifetime
are an integration question, not something this proposal claims VIR already has.

| Visual case | Required mapping |
| --- | --- |
| `E₁,E₂` below an update | Two ordered mask references, not an invented pair expression |
| Namespace above an invariant | Reference to the namespace argument of `Iris.inv` |
| `∃ n : Nat` | Enclosing binder information, with a contextual route to its type and body |
| Two occurrences printed `P` | Distinct occurrence keys, even if their expressions are equal |
| `A n` with no registered renderer | Tagged Lean fallback, retaining available references |
| Mathematical `l ↦ n` | Source copy retains `l ↦ some hl_val(#n)` when that is the actual term |

For a multi-target annotation, expose the individual targets to the user rather
than choosing one arbitrarily. The gallery only explains such groups; it does
not implement their server interactions. Capabilities control which actions are
offered; a visible annotation need not support jump-to-definition.

## Projection and extension rules

1. Work from elaborated expressions in the saved goal/delaboration context.
   Use declaration-aware hooks for recognized constructs such as `FUpd.fupd`,
   `Iris.inv`, and `Wp.wp`; never parse pretty-printed text.
2. Reuse delaboration's contextual subexpression information when available.
   Construct binder bodies under the corresponding local context. Avoid
   arbitrary unfolding just to obtain a prettier shape.
3. Let extensions return an optional presentation for a recognized expression.
   Priority and scope must be deterministic. A declined, failed, or unsupported
   extension falls back to tagged Lean, with a diagnostic available to developers.
4. Preserve precedence, explicit grouping, binding scope, and argument order.
   A renderer may abbreviate a value encoding only with an inspectable source
   counterpart; mathematical spelling is never the copy authority.
5. Treat the presentation tree as data, not executable HTML or unrestricted TeX.
   Bound depth/size and keep labels/text escaped. Extensions should not create
   arbitrary browser actions, scripts, styles, or trusted KaTeX commands.

Prefer a small open extension mechanism over a closed grammar containing every
Iris connective. Whether these hooks extend delaborators directly or consume
their structured results remains to be settled against the real APIs.

## Snapshot and UI-state rules

- A reference is valid only for its server session and retained elaboration
  snapshot. Document version alone is not sufficient to identify that context.
- A new request supersedes older in-flight responses. Do not let a delayed hover
  result populate a new goal's inspector.
- On a new snapshot, clear term selection unless the server provides an explicit
  valid correspondence. Never reattach by text, array index, or a React key.
- Preserve collapse state only for goals whose identity is still valid. A split
  introduces distinct goals; matching displayed names is not identity evidence.
- Layout/theme changes within one snapshot may preserve selection. Unmounting
  or retiring a snapshot releases its reference resources through the supported
  RPC mechanism. Expired references disable interaction but leave source readable.
- Copy entire propositions from `canonical`; copy a selected semantic fragment
  only when its server-provided copy payload exists. A binder header or visual
  mask group need not be an independently well-formed Lean term.

## Renderer evaluation, not selection

The offline gallery uses native [MathML Core](https://w3c.github.io/mathml-core/)
and CSS to explore scripts, boxes, and explicit break points. It is a disposable
design aid, not a JavaScript replacement for the Lean widget or a commitment to
MathML as its backend. Its data is authored by hand, including interaction notes.

Compare a reusable VIR KaTeX component with extended DOM/MathML rendering after
the reference contract works. Test a restricted set of actual paper macros,
annotation boundaries after layout, narrow wrapping, accessible math, themes,
and source copying. KaTeX's [supported functions](https://katex.org/docs/supported.html)
and [options](https://katex.org/docs/options) describe its TeX subset and output
modes; they do not establish that our semantic annotations will survive layout.

## Smallest next implementation

The version-3 slice retains tagged references and implements contextual
inspect/selection in Lean. It conservatively resets selection on a new
snapshot; selective goal-state preservation still needs an identity contract.
Next add one renderer extension, preferably `FUpd.fupd`, and compare it
with its canonical fallback at narrow width. Increment the wire version when
shipping another changed contract; the mathematical proposal is not yet a wire API.
