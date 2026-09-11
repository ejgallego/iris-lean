# Iris notation showcase

Design brief and offline gallery, 2026-09-08. Production rendering implementation
is deferred while VIR's cleanup settles. This brief extends the
[proof-mode widget roadmap](proof-mode-widget-design.md#18-rollout-plan).

## Open the first gallery

Open [`notation-gallery/index.html`](notation-gallery/index.html) in a browser,
directly from this worktree. No server, build, or internet connection is needed.
The paper links are external; the gallery itself has no external assets.

Select a specimen, compare wide/360 px/280 px panels and light/dark/high-contrast
themes, and try the marked parts or their keyboard-accessible buttons. Escape
clears selection. The first specimen has two manually transcribed proof
positions; the second position has independently collapsible goals.

“Source fallback” and “Copy source” retain the supplied source text, not text
reconstructed from mathematical layout. If clipboard access is unavailable,
copy selects the source field for Ctrl/Cmd+C. These are manual transcriptions,
not claimed canonical outputs from a Lean server.

| Study | Provenance | Review focus |
| --- | --- | --- |
| Two-context judgment, before/after split | Local `WidgetDemo.lean`, manually transcribed | Resource allocation, compact headers, selection invalidation |
| Fancy-update transitivity | Ground Up Fig. 15; local `Iris.fupd_trans` counterpart | Ordered masks and separate occurrence references |
| Counter invariant | Local `Counter.counterInv`, styled using paper invariant notation | Namespace, binder, source-style custom predicate fallback |
| Long list-reversal induction hypothesis | POPL 2017 §3, PDF p. 5, adapted | Binder scope and explicit wrapping; paper pseudocode, not a Lean fixture |

This is an HTML/MathML design aid, not the Lean-authored VIR widget. Its
inspections are explicitly mock annotations; it neither elaborates terms nor
stores snapshot references. ReLoC remains on the shortlist for an author-guided
second round. The [presentation contract proposal](iris-term-presentation.md)
records the distinction between layout nodes and contextual semantic targets.

Browser smoke check, from the worktree root (requires Node, Chrome/Chromium,
and the existing pinned VIR checkout, but no built VIR runtime):

```sh
node docs/notation-gallery/smoke.mjs
node --check docs/notation-gallery/specimens.js
node --check docs/notation-gallery/gallery.js
git diff --check
```

The check covers 90 width/theme/notation combinations, a 280 px browser viewport,
native keyboard activation, pointer selection, split/collapse behavior, selection
invalidation, copy success/fallback, and local source links. Screenshots go to a
reported temporary directory, not Git. Screen-reader behavior and actual VS Code
themes still need manual review; gallery tests are not live-widget acceptance.
These commands passed on 2026-09-08. No Lean build was run for this design-only
change; the production modules and dependency pins are untouched.

## Purpose

Use mathematical notation from Iris papers to guide the widget's eventual
typesetting and semantic term interactions. The showcase should reveal where
two-dimensional layout improves comprehension: indexed modalities, invariant
boxes, binding structure, specifications, and inference rules.

Each specimen compares the attributed paper notation, the corresponding Lean
rendering when available, and a proposed interactive view. Record the paper
version and page/figure alongside each specimen. Label manually authored
examples as design specimens; label live examples with their Lean declaration
and proof position. Paper notation alone does not establish a correspondence
to a checked Lean proof state.

## Initial reading and specimen shortlist

| Source | Starting points | Proposed design use |
| --- | --- | --- |
| [Iris from the ground up](https://cs.au.dk/~birke/papers/iris-journal.pdf), Jung et al., JFP 2018 | Fig. 1, p. 7 (Hoare rules); Fig. 14, p. 52 (program logic); Fig. 15, p. 57 (fancy updates and invariants) | Rule layout, postcondition binders, mask indices, and invariant notation |
| [Interactive Proofs in Higher-Order Concurrent Separation Logic](https://iris-project.org/pdfs/2017-popl-proofmode-final.pdf), Krebbers, Timany, and Birkedal, POPL 2017 | Section 3; Figs. 3–4 and the list-reversal proof state on PDF p. 5; Fig. 8 on PDF p. 10 | Connect mathematical rules to persistent/spatial proof contexts; exercise a large induction hypothesis and logical-relation notation |
| [ReLoC Reloaded](https://iris-project.org/pdfs/2021-lmcs-reloc-reloaded-final.pdf), Frumin, Krebbers, and Birkedal, LMCS 2021 | Section 5; Fig. 7 on p. 9:26 and Fig. 8 on p. 9:30 | Relational specifications, nested quantifiers, ghost-state indices, and logically atomic specifications |

These are visual and interaction references. Availability of corresponding
iris-lean developments must be checked with the authors before selecting live
examples. The foundational paper also fixes a historical Iris version; retain
that provenance when comparing its notation with current Lean declarations.

## Rendering direction

Extend the presentation of proposition leaves while retaining the existing
typed goal/context projection. A candidate next layer is an annotated
presentation tree: tokens, grouping, scripts, binders, layout choices, and
semantic references tied to a Lean snapshot. Its precise datatype remains a
design question; see the [candidate contract](iris-term-presentation.md).

Construct that presentation from elaborated terms and extensible Lean
delaboration/rendering hooks. Preserve canonical Lean text for unfamiliar
notation, inspection, and copying. Do not reconstruct terms or mathematical
structure by parsing the pretty-printed output. Extensions should support
domain-specific notation without requiring a closed grammar of every Iris
proposition.

A reusable Lean-facing VIR KaTeX component could supply mathematical
typesetting. KaTeX provides HTML/MathML output and a documented subset of TeX
commands; custom paper macros need a compatibility check. See its
[output options](https://katex.org/docs/options) and
[supported functions](https://katex.org/docs/supported.html).

Term identity, snapshot validity, hover/selection, and copying remain explicit
parts of our presentation contract. Evaluate how annotations survive KaTeX
layout before choosing a backend. An extended DOM/React renderer, or a mixture
of ordinary code spans and mathematical fragments, remains a candidate where
typesetting, wrapping, or interaction requires it. Keep semantic projection
and application behavior authored in Lean.

## First review exercise

Select three to five small specimens with the Iris authors. Include a
two-context judgment, an indexed update or invariant, a specification with
nested binders, and one long relational or weakest-precondition term. For each:

- Identify what the typesetting makes easier to read and which syntax must
  remain visibly unambiguous.
- Name the subterms users should be able to inspect or select, and the Lean
  expression/reference each interaction would address.
- Compare a wide showcase view with a narrow editor panel; assess line breaks,
  index legibility, theme behavior, and keyboard access.
- Specify copying behavior and a readable fallback for unsupported notation.
- Where a live Lean counterpart exists, compare several successive proof
  states so that layout changes and retained selection can be reviewed.

The first deliverable is the attributed specimen catalogue and offline gallery
above, with interaction requirements and a candidate presentation contract.
The production datatype and a KaTeX integration follow review; neither is
implemented by this design-only work.
