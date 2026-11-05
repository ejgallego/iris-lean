# Quotation display POC (Round G)

`pp.iris.quotations` defaults to `true`. Existing output and all existing
printer tests retain their quotation syntax. With `false`, values such as
`hl_val(#false)`, `hl_val(#())` and `hl_val(#b)` display as `#false`, `#()` and
`#b`; pairs and injections lose the outer value wrapper too. An existing
iProp quotation keeps its parentheses but omits its keyword:
`inv N iprop(∃ b, …)` becomes `inv N (∃ b, …)`.

This is an experimental **display option**, not new Lean notation. The result
may not re-parse. In particular, iProp connectives can look like ordinary Lean
propositions once their re-entry keyword is hidden. The widget selects `false`
for both sides of every projection. The SpinLock demo example selects it
locally so the ordinary Tactic state demonstrates the same option. Outside
those scopes the default remains unchanged.

## Implementation and semantic information

Custom formatters operate on the existing `hl_val(…)` and `iprop(…)` syntax
nodes. With the option enabled they delegate to the original parser-descriptor
formatter. With it disabled they omit only wrapper tokens, preserving child
syntax, its tagged positions and the native `CodeWithInfos` path. No new term
parser or unexpander is registered, so this introduces no grammar competition
with `#[…]` or other Lean syntax. Both ordinary and annotated new terms still
use native InteractiveCode.

## Deliberately retained output

- `hl(…)` still distinguishes a HeapLang program from a Lean term.
- `v(…)` still marks a nonliteral value embedded in that program, for example
  `hl(v((#b, &v)))`.
- `hl_val(λ x, …)` and `hl_val(rec f x := …)` keep their boundary: simply
  deleting it would make low-precedence function values misleading in larger
  expressions. This POC does not add a new parenthesization scheme.
- `hl_binder(…)` and `term(…)` escapes are unchanged.
- Parentheses around an iProp body remain; the POC removes the keyword, not
  the grouping.
- `some` in `l ↦ some #false` is the heap cell's optional value, not a quotation.

A `Val` variable already prints as `v`: source `hl_val(&v)` elaborates to that
same variable. Inside structured value syntax it still appears as `&v`, as in
`(&v, #b)`. In contrast `#b` wraps a Lean `Bool` in a literal. Those are different
types and representations; this option does not normalize them into one syntax.

## Regression surface

`IrisTest.HeapLang.PPQuotations` checks exact default/short output for literals,
unit, a Bool variable, pairs, nested injections, nested values in `hl(…)`,
function values, standalone `Val` variables and an invariant containing a
quantified iProp. Tagged-printer checks verify local expression and type identity
for `b`, `v` and the invariant namespace in both modes. Existing default tests
are untouched. The real VS Code gate checks hover and definition navigation
from shortened terms and the ordinary Tactic state's local option.

The plain and shortened Heap store/SpinLock screenshots and run evidence live
in the worktree's `.tmp/round-g/`. They are review evidence, not package assets.
