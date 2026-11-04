# Iris Proof-Mode Widget Design

- Status: opt-in native-RPC/subterm prototype implemented; basic editor use confirmed, broader acceptance pending
- Task id: `proof-mode-widget`
- Branch: `feat/proof-mode-widget`
- Date: 2026-09-03

Contributor entry point: [maintainer guide](widget-maintainer-guide.md).
Pinned-dependency findings: [VIR API review](vir-widget-api-review.md).

## 1. Executive summary

Build a focused, Lean-authored companion panel for Iris proof mode. The widget
groups Iris hypotheses into persistent (`□`) and spatial (`∗`) contexts, keeps
the current Iris target visually distinct, handles multiple goals, and
otherwise stays out of the way. VIR supplies the infoview/React runtime; Iris
owns the server-side mapping, versioned display domain, components, styles, and
interactions in Lean.

The widget does not parse rendered goals. On each refresh, a custom Lean server
RPC obtains the elaborated goal, recognizes its typed `IrisGoal`, traverses the
typed `Hyps` tree, and maps it into a small JSON-serializable display model.
Only proposition leaves are pretty-printed, after their structural role is
already known. The Lean-authored VIR component decodes that model and renders
it with React.

Version 3 preserves Lean's tagged proposition rendering. Keyboard-focusable
subterm controls inspect actual expressions under their saved binder and
metavariable contexts. A native server snapshot reference owns that context;
display IDs are not semantic references. Inspection remains read-only and
click/Enter activated, with an inline expression/type result—not full infoview
hover popups, definition navigation, or mathematical typesetting.

The opt-in prototype now targets Lean 4.35.0 and pins VIR's last mainline
4.35 commit `81de859a3ba1cb5da8bc5f128af025dd5a40b343`. The
[4.35 review](widget-review-435.md) records the current implementation and
validation; the [runbook](vir-demo-runbook.md) installs the matching published
runtime. Later dated sections below preserve earlier design decisions and 4.32
validation history; their setup commands are superseded by the runbook.

## 2. Discovery and problem definition

### Current Iris display

`Iris.ProofMode.Display` already recognizes an `Entails'` goal and delaborates
its proof-mode state into a flat goal display:

```text
□persistentName : persistent proposition
∗spatialName : spatial proposition
⊢ target proposition
```

This repository's `Display.lean` output is the comparison baseline for notation
and resource conventions. The `∗` hypothesis prefix is already an iris-lean
convention. Rocq Iris's `────□` / `────∗` separator layout is optional design
inspiration, not a convention this widget must restore. The current widget's
missing `:` between hypothesis name and proposition remains a notation gap;
the comparison should preserve that distinction from the choice of layout.

The information is correct, but the two contexts remain one visual block. As
the number and size of resources grows, users must repeatedly scan the leading
symbol instead of seeing the persistent/spatial structure directly.

Relevant sources:

- [`Iris/Iris/ProofMode/Display.lean`](../Iris/Iris/ProofMode/Display.lean)
- [`Iris/Iris/ProofMode/Expr.lean`](../Iris/Iris/ProofMode/Expr.lean)
- [`Iris/IrisTest/Display.lean`](../Iris/IrisTest/Display.lean)
- [`Iris/proofmode.md`](../Iris/proofmode.md)

### Replacement remains undecided

The normal infoview also shows the ordinary Lean context above this Iris
judgment: variables, ordinary hypotheses, local definitions and instances.
The widget's `DisplayGoal` contains only the persistent/spatial Iris hypotheses
and target, plus display identity. It does not include that ordinary context.
Saved local contexts support semantic inspection of displayed terms, but are
not a visible context listing and do not cover locals absent from those terms.

Replacing the normal view therefore requires both host support and a complete
context presentation. A proposal must account for the ordinary Lean context,
either through the target model or host-provided typed goal/context data, and
compare the complete view on the same proof states. The native target-only
experiment establishes neither this coverage nor replacement readiness. The
maintainer has not chosen replacement or coexistence; no context-model or
renderer change is implied by this requirement.

### Problem statement

> When working inside Iris proof mode, authors need a compact view that mirrors
> Iris's persistent/spatial mental model so they can find resources and the
> current target without decoding a flat text block.

### Key technical finding

The generic VIR `Surface` flattens goal rendering too early for reliable Iris
classification. General Lean/Iris syntax is extensible, so reconstructing an
`IrisGoal` from that text would be both incomplete and coupled to presentation.
VIR's native RPC path avoids this limitation: Iris can map the original
typed server goal to its own display domain before the browser boundary.

## 3. Users and jobs to be done

### Regular Iris proof author

- Scan available resources before choosing the next proof-mode tactic.
- Distinguish reusable hypotheses from spatial resources immediately.
- Keep long propositions readable without losing the hypothesis name.
- Move among multiple goals without losing context.

### Iris learner

- Learn that `□` means persistent/reusable and `∗` means spatial.
- See proof-mode state organized like the documentation.
- Receive no distracting panel outside Iris proof mode.

### Library maintainer

- Evolve Iris syntax without updating a text parser.
- Test the typed mapping independently of the browser.
- Version the server/widget data contract explicitly.
- Pin the VIR library, package, and runtime as one compatible unit.

## 4. Goals, non-goals, and success criteria

### Goals

- Separate persistent and spatial hypotheses into labeled groups.
- Preserve the same order and duplicate-name behavior as Iris's delaborator.
- Give the target a stable, prominent position below both contexts.
- Support empty contexts, multiple goals, Unicode, multiline propositions,
  narrow panels, and VS Code themes.
- Render nothing when no typed Iris goal is present.
- Keep application logic and UI code Lean-native.
- Keep the display domain independent of Iris internals and React internals.

### Non-goals for the prototype

- Replacing or hiding Lean's built-in goal display.
- Tactic suggestions, tactic insertion, drag-and-drop, or proof-state mutation.
- Parsing canonical display text or arbitrary user syntax.
- Subexpression hover popups, click-to-highlight, jump-to-definition, or
  selected-expression integration.
- Persisting UI preferences across editor sessions.
- A generic separation-logic widget framework.

### Acceptance criteria

- Every mapped hypothesis appears exactly once in the correct context.
- Mapping begins from `IrisGoal`/`Hyps`, never from formatted text.
- Non-Iris goals do not produce partial or guessed contexts.
- The target remains readable at a 280 px panel width without page-level
  horizontal scrolling.
- All controls are keyboard reachable and expose accessible names and state.
- Selecting a tagged subterm reveals its expression and type in the saved
  elaboration context without mutating the proof.
- Multiple goal cards have stable keys and independent collapse state.
- The custom RPC payload round-trips through JSON and mounts in the VIR browser
  runtime.

## 5. Design principles

1. **Typed structure before presentation.** Classify goals and resources from
   Iris datatypes; format only leaf propositions.
2. **A companion, not a second infoview.** Show Iris-specific state, not a copy
   of ordinary Lean locals.
3. **Fail closed.** A target that `parseIrisGoal?` does not recognize contributes
   no widget content; the UI never guesses from similar-looking text.
4. **Stable under motion.** Goal and hypothesis identities come from metavariable
   and Iris-variable ids, not display strings.
5. **Theme-native and accessible.** Structure and labels carry meaning; color
   only reinforces it.
6. **Progressive capability.** `RenderedTerm` carries canonical tagged Lean
   rendering. Mathematical layout may enrich it without changing context
   classification or inventing semantic references.

## 6. Information architecture

Ordinary Lean hypotheses remain in Lean's standard goal view.

```text
Iris proof mode region (visually headerless; the panel already has a title)
├─ Goal summary: case/name, compact □/∗ counts
├─ Persistent context (□, semantic label)
│  └─ zero or more persistent hypothesis rows
├─ Spatial context (∗, semantic label)
│  └─ zero or more spatial hypothesis rows
└─ judgment rule followed by target (⊢)
```

For multiple Iris goals, the region contains one keyed goal card per goal. The
first card starts expanded; later cards start collapsed. Each card owns its
collapse state.

## 7. Target display domain

The RPC and browser share a deliberately small, JSON-serializable model:

```lean
inductive ContextKind
  | persistent
  | spatial

structure RenderedTerm where
  id : String
  text : String
  typeText : String
  summary : String
  code : Lean.Widget.TaggedText Nat

structure DisplayHypothesis where
  id : String
  kind : ContextKind
  name : String
  proposition : RenderedTerm

structure DisplayGoal where
  id : String
  index : Nat
  title : String
  persistent : Array DisplayHypothesis
  spatial : Array DisplayHypothesis
  target : RenderedTerm

structure WidgetState where
  version : Nat := 3
  goals : Array DisplayGoal
```

The domain contains only facts the display needs. Each tag index addresses a
saved contextual expression in the associated snapshot. The tree retains all
tag nesting; the current renderer uses innermost-tagged leaves to avoid nested
buttons. Untagged text remains readable. Repeated spellings have distinct
occurrence indices.

`WidgetState.version` is `3` and makes incompatible future wire-format changes
explicit. The server and widget package are currently built together, so the
prototype needs no migration path.

## 8. Typed mapping contract

The mapper consumes `Iris.ProofMode.IrisGoal`, not syntax and not delaborated
goal text.

1. At the requested cursor, obtain `InteractiveGoals` from Lean's file worker.
2. For each goal, enter its saved metavariable context and instantiate its
   target metavariables.
3. Call `Iris.ProofMode.parseIrisGoal?` on the target expression.
4. If recognition fails, omit that goal.
5. Traverse the typed `Hyps` tree. Read persistence from the typed boolean and
   the proposition from the hypothesis node.
6. Preserve Iris's existing display order and duplicate-name convention.
7. Pretty-print each already-classified proposition with `delabIProp`; do not
   inspect the resulting text.
8. Preserve the tagged pretty-printer tree and retain each term's expression,
   local context and elaboration context in the server snapshot. Metavariable/
   `IVarId` names identify display rows only.
9. Partition the mapped rows into persistent and spatial arrays.

`Iris.ProofMode.parseIrisGoal?` is the appropriate existing interface here. It
is Iris's public, non-mutating structural decoder for an already-active
`Entails'` goal, and Iris's own proof-state delaborator uses the same function.
Unlike `startProofMode`, it does not transform the proof; unlike
`parseEntails?`, it retains the typed `Hyps` tree needed by the widget. The RPC
keeps the required metavariable-context entry and target instantiation adjacent
to this call so the provenance of every accepted `DisplayGoal` is visible.

The mapper calls `ppExprTagged`. `stripTags` supplies canonical fallback text,
while the tagged tree is also retained, replacing term-info tags with
snapshot-relative indices. The internal delaborator info types are consumed
only by this adapter; neither raw expressions nor info nodes enter JSON.
`SnapshotReply` contains the versioned display JSON string plus a native
`WithRpcRef Snapshot`. VIR passes the exact client-registered reference back
to `inspect`; it never routes it through the legacy recursive `RpcJson` bridge.

## 9. Interaction design

### Primary flow

1. The user moves the cursor into a proof.
2. VIR supplies its native `Surface` and position-specific RPC session.
3. A Lean-authored React effect calls `Iris.ProofMode.Widget.state` and receives
   versioned display data plus an opaque snapshot reference.
4. The client decodes the display data and constructs one view for that
   snapshot. The native reference is retained unchanged alongside the session.
5. The Lean-authored React component renders persistent and spatial rows above
   a judgment rule and target.
6. The user may independently collapse or expand each goal card.
7. Selecting a tagged span calls `inspect` with its owning snapshot and index,
   then shows the saved expression/type. Closing, reselecting, replacing the
   snapshot, or unmounting retires the corresponding response handler. Both
   late success and late failure are ignored. Pending requests are not aborted.

New snapshots conservatively reset term selection and goal collapse state;
there is no guessed correspondence across snapshots based on names or text.

### Outside proof mode

If the typed mapper finds no Iris goals, `WidgetState.goals` is empty and the
component renders an empty fragment. It does not show an inactive placeholder.

### Mapping or RPC failure

Unrecognized goals are normal and are omitted. Unexpected server, decoder, or
runtime failures remain visible through VIR's existing widget error surface and
the Iris-specific runtime setup hint. There is no raw-goal fallback because it
would reintroduce presentation coupling and duplicate Lean's normal goal view.

### Multiple goals

- The region has no visible header because the infoview panel already names it.
- First goal expanded by default.
- Later goals collapsed by default, showing title and resource counts.
- Expanding one goal does not collapse another.

## 10. Low-fidelity wireframes

### Single expanded goal

```text
┌─ goal 1                          □ 2 · ∗ 2  [−] ─┐
│ □  HR    R                                            │
│ □  HRΦ   R -∗ ∃ x, Φ x                               │
│ ∗  HP    P                                            │
│ ∗  HQ    Q                                            │
│ ─────────────────────────────────────────────────────── │
│ ⊢ ∃ x, Φ x ∗ P ∗ Q                                   │
│   PROP · WidgetDemo.lean:12:3                       │
└───────────────────────────────────────────────────────┘
```

### Multiple goals

```text
┌─ case left                            □ 1 · ∗ 2 [−] ─┐
│   ...expanded content...                             │
├───────────────────────────────────────────────────────┤
│ case right                           □ 1 · ∗ 1 [+] │
├───────────────────────────────────────────────────────┤
│ goal 3                               □ 0 · ∗ 0 [+] │
└───────────────────────────────────────────────────────┘
```

## 11. Visual and responsive design

- Use a one-column grid with no fixed content width.
- Use 4 px section gaps, 2 px outer padding, 3–5 px card padding, and 1–3 px
  hypothesis-row padding for normal working density.
- Render hypothesis rows as a min-content name plus flexible proposition.
- Use the editor monospace font for names, propositions, and targets.
- Preserve line breaks and use `overflow-wrap: anywhere` for generated names.
- Let header counts wrap before controls are squeezed.
- Do not set a page-level minimum width or depend on hover.
- Make terms look like code rather than buttons; retain native button focus and
  activation behavior.

VS Code theme variables are used for foreground, background, muted text,
borders, code surfaces, and section accents, with conservative light-theme
fallbacks. Every accented section also has a label and glyph.

## 12. Component inventory

- `App : React.Component WidgetState`
  - renders an empty fragment for an empty state;
  - otherwise delegates to the proof-mode region.
- `ProofModeRegion : Component (Array DisplayGoal)`
  - owns the headerless semantic region and keyed goal list.
- `GoalCard : Component GoalCardProps`
  - owns collapse state and summary counts.
- `ContextSection : Component ContextSectionProps`
  - renders a labeled semantic section and hypothesis list.
- `HypothesisRow : Component DisplayHypothesis`
  - renders glyph, name, and proposition.
- `TargetSection : Component RenderedTerm`
  - renders the judgment rule, turnstile, and target.
- `InteractiveTerm : Component InteractiveTermProps`
  - owns selected/detail state and inspects snapshot-bound contextual subterms.

Goal cards are keyed by metavariable id. Hypothesis rows are keyed by
`IVarId`; display names alone are not assumed unique.

## 13. State and edge-case matrix

| State | Presentation |
| --- | --- |
| VIR loading | Existing VIR shell loading message |
| VIR/RPC/runtime error | Existing shell error plus Iris setup hint |
| No goals | Empty fragment |
| Goals, none recognized as Iris | Empty fragment |
| One Iris goal | Expanded card |
| Multiple Iris goals | First expanded; remaining collapsed |
| No persistent hypotheses | `0 persistent` summary; section omitted |
| No spatial hypotheses | `0 spatial` summary; section omitted |
| Empty Iris context | Target-only expanded card |
| Multiline proposition | Preserve line breaks and wrap safely |
| Duplicate user names | Use Iris's disambiguated display names and distinct ids |
| Very long name | Wrap without overlapping proposition |
| Cursor-only update | Re-render data; stable keys retain matching card state |
| Selected subterm | Inline expression/type from its retained elaboration context |
| Widget-code update | VIR package revision reload; local UI state may reset |

## 14. Accessibility

- Outer element: `role="region"`, `aria-label="Iris proof mode"`.
- Each goal is an `article` with a real heading.
- Contexts use labeled `section` elements and `ul`/`li` lists.
- Decorative `□`, `∗`, and `⊢` glyphs are `aria-hidden`; text labels provide
  the meaning.
- Collapse controls are native buttons with `aria-expanded`, `aria-controls`,
  a title, and an accessible name.
- Proposition controls are native buttons with term-specific labels and expose
  their expandable detail line through `aria-expanded`/`aria-controls`.
- Focus indicators remain theme-controlled and are never disabled.
- Meaning is never encoded only through color or position.

## 15. Technical architecture

```text
Lean file worker / InteractiveGoal
              │ target Expr + metavariable context
              ▼
 Iris.ProofMode.parseIrisGoal? : Expr → Option IrisGoal
              │ typed IrisGoal / Hyps
              ▼
      toDisplayGoal : IrisGoal → DisplayGoal
              │ versioned display JSON + opaque native snapshot reference
              ▼
        Lean-authored native-RPC client (VIR Surface session)
              │ decoded WidgetState + retained semantic context
              ▼
      Lean-authored VIR/React components
              │
              ▼
          Infoview DOM
```

All Iris-specific server and application logic stays in Lean. JavaScript is the
generic shell supplied by VIR.

### Alternatives considered

1. **Typed Iris server payload.** Selected. It preserves structural truth,
   supports extensible syntax, and cleanly separates Iris internals from the
   display domain.
2. **Parse canonical delaborated target text.** Implemented briefly for the
   first visual prototype, then removed. Even a strict parser is coupled to
   formatting and cannot scale to extensible general syntax.
3. **Build an Iris-specific JavaScript widget shell.** Rejected because VIR's
   generic Surface shell already provides the boundary and the application is
   intended to remain Lean-authored.
4. **Encode Iris resources as ordinary Lean locals.** Rejected because it would
   distort the proof state and expose proof-mode implementation machinery.

### Module layout

```text
Iris/Iris/ProofMode/Widget.lean          -- Lean/VIR components and activation
Iris/Iris/ProofMode/Widget/Model.lean    -- versioned display/RPC domain
Iris/Iris/ProofMode/Widget/Client.lean   -- native RPC, decoding, effect lifetimes
Iris/Iris/ProofMode/Widget/Rpc.lean      -- IrisGoal-to-domain mapper and RPC
Iris/Iris/ProofMode/Widget/Style.lean    -- VS Code token helpers/styles
Iris/IrisTest/ProofMode/Widget.lean      -- JSON and elaborated-goal mapping tests
Iris/IrisTest/ProofMode/WidgetDemo.lean  -- presentation-focused proof fixture
```

The application remains opt-in: `Iris.ProofMode.Widget` is not imported by the
ordinary `Iris.ProofMode` entry point.

### Activation

```lean
show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.widgetProps]
```

This keeps the experimental runtime and packaging cost local to a fixture or
demo. Default-on registration waits for the production asset path and editor
acceptance.

## 16. Toolchain and asset decisions

- Keep Iris on Lean 4.32.2.
- Keep VIR pinned to an exact compatible checkpoint rather than a moving
  branch. The current `8032fd3` pin is published on `fix/iris-widget-errors`;
  `ea9ba047` is the previous published pin. Source availability does not replace
  building the matching runtime.
- Build the VIR Lean library, IR package, JavaScript shell, and WASM runtime from
  compatible revisions.
- Do not check generated JavaScript or WASM binaries into Iris.
- Keep Lake's artifact cache enabled. The earlier downloader failure was a weak
  network connection, not evidence that the cache policy needed changing.

The prototype currently loads
`.lake/packages/lean_vir/web/public/vir-upstream.wasm`. Production integration
needs a VIR-supported downstream target or an Iris Lake target that stages the
matching runtime at a deterministic workspace path.

## 17. Validation strategy and current evidence

The historical checks below describe the version-2 prototype and PR checkpoint.
The native-RPC migration is recorded in [the migration note](widget-native-rpc.md).
The [2026-09-09 refresh record](vir-v432-refresh.md) records the new format-11
runtime/package build, downstream tests, and remaining manual acceptance.

### Pure and Lean integration checks

- JSON round-trip for a representative `WidgetState`.
- Widget metadata selects the typed `RpcJson` bridge and the Iris state RPC.
- A representative elaborated proof calls `parseIrisGoal?` and `toDisplayGoal`
  in its real metavariable context.
- The mapped result contains persistent `HP : P`, spatial `HQ : Q`, and target
  `P ∗ Q` in the expected groups.
- Lean Beam checkpoints report no diagnostics for the changed modules.
- `lake build IrisTest.ProofMode.Widget` succeeds.
- `lake test` succeeds across all 342 jobs with the configured artifact cache.
- The static `:vir` facet closes a 32-member module package set containing 945
  declarations (863 Lean IR and 82 native externs) and two interface exports.

### Live RPC and browser checks

- A real `lake serve` session called `Iris.ProofMode.Widget.state` at the proof
  cursor and returned the expected versioned JSON state.
- The same session generated a module package set rooted at `createComponent`
  and `mount` with no package diagnostics.
- The Lean 4.32 VIR runtime loaded all 32 package-set members, decoded a typed
  `WidgetState`, and rendered the Lean-authored React tree; malformed input
  exercised the Lean-side decoder error.
- Before the module-system refresh, a headless Chromium pass covered semantic
  region/article/section structure, context counts, proposition/target content,
  two goal cards, default collapsed state, expansion of the second goal, and
  whole-term detail activation.
- That earlier 360 px browser rendering fit two persistent rows, two spatial
  rows, and the target in approximately 160 px, or 174 px with one term-detail
  line expanded. The current package-set runtime smoke preserves the same Lean
  component tree; manual VS Code acceptance remains a rollout check.

### Remaining checks before default-on rollout

- Manual VS Code acceptance with long propositions, duplicate names, multiple
  goals, narrow width, and light/dark/high-contrast themes.
- Verify the standard infoview remains usable and the widget does not steal
  editor focus or input.

## 18. Rollout plan

1. Complete the opt-in typed mapper, component, and automated checks.
2. Publish and pin the VIR module-system revision. (Done for this checkpoint.)
3. Establish a deterministic downstream runtime asset target.
4. Complete manual editor and accessibility acceptance.
5. Measure import/build/runtime cost before considering global registration.
6. Preserve contextual tags and support read-only subterm inspection. Version 3
   implements the first slice; richer hover/navigation and selective state
   preservation across snapshots remain separate work.
7. Explore mathematical typesetting through a reusable VIR KaTeX component or
   an extended renderer, guided by the
   [paper notation showcase](iris-notation-showcase.md). Preserve semantic
   references and the canonical Lean rendering through this extension.

### Design work while VIR settles (2026-09-08)

Keep the current VIR checkpoint during its cleanup. The agreed design work is:

- Select representative proof sequences with the Iris authors, including long
  resources, binders/modalities, and multiple goals.
- Review layout and retained UI state across successive proof states.
- Specify semantic subexpression spans and snapshot-bound references before
  implementing richer hover, selection, or navigation.
- Use published Iris notation as a showcase for an eventual mathematical
  renderer. Compare paper typography, current Lean notation, and proposed
  interactive presentation on a small set of attributed examples.

The showcase can include manually authored design specimens. Mark those as
such; live fixtures must name the corresponding Lean declarations and derive
their state through the existing typed mapper. Selecting a paper does not
assume its development is available in iris-lean.

The first [offline notation gallery](notation-gallery/index.html) now provides
four manually authored studies, including a two-position resource split. The
[presentation contract proposal](iris-term-presentation.md) separates visual
nodes, semantic occurrences, source copying, and snapshot-bound references.
Neither changes the production Lean widget, wire version, or VIR pin.

## 19. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Iris internal representation changes | Keep recognition at `parseIrisGoal?` and projection localized to `toDisplayGoal`; test both on elaborated goals |
| RPC/model drift | Version `WidgetState`; derive JSON codecs; build server and client together |
| Widget duplicates infoview content | Render only Iris contexts and target |
| Global widget adds noise | Empty fragment outside proof mode; opt-in rollout first |
| Missing/mismatched WASM | Pin compatible revisions and add a deterministic asset target |
| Term control overpromises infoview parity | Label it as contextual inspection; defer hover popups and navigation |
| Long contexts become too tall | Compact rows and per-goal collapse |
| React state churn | Stable keys within a snapshot; conservative reset on replacement |

## 20. Review decisions

1. Version 3 is a companion panel with contextual, read-only subterm controls.
2. Structural input is the typed `IrisGoal`; the text parser and raw fallback
   are removed.
3. The target domain is versioned and independent of both `Hyps` and React.
4. Pretty-printed strings are leaf render data only, never parser input.
5. The prototype stays opt-in on Lean 4.32.2 with VIR's module-system support.
6. Persistent/spatial glyphs, a judgment rule, target prominence, multi-goal
   cards, stable identities, theme use, and accessibility follow the reviewed
   wireframes.
7. The next design iteration uses real proof sequences and a paper-notation
   showcase. Mathematical typesetting is a future rendering extension; the
   choice between KaTeX and a richer renderer remains open.

Staging the runtime deterministically and completing manual editor acceptance
remain rollout work rather than changes to the interaction model.
