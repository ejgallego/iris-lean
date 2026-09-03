# Iris Proof-Mode Widget Design

- Status: opt-in typed-RPC prototype implemented; editor acceptance pending
- Task id: `proof-mode-widget`
- Branch: `feat/proof-mode-widget`
- Date: 2026-09-03

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

Version 2 adds a deliberately narrow interaction: each complete rendered Iris
proposition is a keyboard-focusable term control. Selecting it resolves VIR
reference metadata at the current editor position and reveals a compact type
and source-position detail line. It does not add tactic buttons, replace Lean's
normal goal view, or claim subterm hover support that the typed-RPC bridge does
not yet preserve.

The opt-in prototype targets Lean 4.32.2 and pins the published VIR 4.32
module-system checkpoint `ea9ba047`, based on PR #166 at `e88f98d`. The
matching VIR runtime and exact widget package build locally. Production rollout
still needs a deterministic
downstream location for the matching WASM runtime; that packaging concern does
not alter the widget design.

## 2. Discovery and problem definition

### Current Iris display

`Iris.ProofMode.Display` already recognizes an `Entails'` goal and delaborates
its proof-mode state into a flat goal display:

```text
□persistentName : persistent proposition
∗spatialName : spatial proposition
⊢ target proposition
```

The information is correct, but the two contexts remain one visual block. As
the number and size of resources grows, users must repeatedly scan the leading
symbol instead of seeing the persistent/spatial structure directly.

Relevant sources:

- [`Iris/Iris/ProofMode/Display.lean`](../Iris/Iris/ProofMode/Display.lean)
- [`Iris/Iris/ProofMode/Expr.lean`](../Iris/Iris/ProofMode/Expr.lean)
- [`Iris/IrisTest/Display.lean`](../Iris/IrisTest/Display.lean)
- [`Iris/proofmode.md`](../Iris/proofmode.md)

### Problem statement

> When working inside Iris proof mode, authors need a compact view that mirrors
> Iris's persistent/spatial mental model so they can find resources and the
> current target without decoding a flat text block.

### Key technical finding

The generic VIR `Surface` flattens goal rendering too early for reliable Iris
classification. General Lean/Iris syntax is extensible, so reconstructing an
`IrisGoal` from that text would be both incomplete and coupled to presentation.
VIR's typed RPC widget path avoids this limitation: Iris can map the original
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
- Selecting a rendered proposition reveals its server-rendered type and current
  source position without mutating the proof.
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
6. **Progressive capability.** `RenderedTerm` carries whole-term reference
   metadata and can later gain semantic spans without changing context
   classification.

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
  version : Nat := 2
  goals : Array DisplayGoal
```

The domain contains only facts the display needs. `RenderedTerm` is a structure,
rather than a bare string, so whole propositions can be resolved through VIR
now and a future version can add tagged subexpression spans without changing
`DisplayHypothesis` and `DisplayGoal` conceptually.

`WidgetState.version` is `2` and makes incompatible future wire-format changes
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
8. Render each proposition's type and attach a stable whole-term reference id
   derived from the metavariable/`IVarId` name.
9. Partition the mapped rows into persistent and spatial arrays.

`Iris.ProofMode.parseIrisGoal?` is the appropriate existing interface here. It
is Iris's public, non-mutating structural decoder for an already-active
`Entails'` goal, and Iris's own proof-state delaborator uses the same function.
Unlike `startProofMode`, it does not transform the proof; unlike
`parseEntails?`, it retains the typed `Hyps` tree needed by the widget. The RPC
keeps the required metavariable-context entry and target instantiation adjacent
to this call so the provenance of every accepted `DisplayGoal` is visible.

The current proposition payload calls `ppExprTagged` and strips tags before
serialization. This is an intentional leaf-formatting boundary, not parsing.
The whole-term id/type/summary supports a small reference interaction today; a
later revision can retain normalized tagged subexpression references.

## 9. Interaction design

### Primary flow

1. The user moves the cursor into a proof.
2. VIR calls `Iris.ProofMode.Widget.state` with the cursor position.
3. The Lean server returns a versioned `WidgetState` derived from typed goals.
4. The VIR shell converts that JSON value to `RpcJson`, creates the exported
   Lean component once, and passes the component and input to the exported
   Lean mount function.
5. The Lean-authored React component renders persistent and spatial rows above
   a judgment rule and target.
6. The user may independently collapse or expand each goal card.
7. Selecting any proposition asks VIR to resolve its reference at the current
   editor position and expands an inline `type · file:line:column` detail.

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
  - owns selected/detail state and resolves the whole-term VIR reference.

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
| Selected proposition | Inline server-rendered type and current source position |
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
              │ versioned JSON through custom server RPC
              ▼
        VIR ReactRpcWidget shell
              │ decoded WidgetState
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
   generic typed-RPC shell already provides the boundary and the application is
   intended to remain Lean-authored.
4. **Encode Iris resources as ordinary Lean locals.** Rejected because it would
   distort the proof state and expose proof-mode implementation machinery.

### Module layout

```text
Iris/Iris/ProofMode/Widget.lean          -- Lean/VIR components and activation
Iris/Iris/ProofMode/Widget/Model.lean    -- versioned display/RPC domain
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
- Keep VIR pinned to the published `ea9ba047` checkpoint rather than a moving
  branch.
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
6. Extend `RenderedTerm` from whole-term references to semantic subexpression
   spans only when the RPC and VIR rendering APIs preserve them end-to-end.

## 19. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Iris internal representation changes | Keep recognition at `parseIrisGoal?` and projection localized to `toDisplayGoal`; test both on elaborated goals |
| RPC/model drift | Version `WidgetState`; derive JSON codecs; build server and client together |
| Widget duplicates infoview content | Render only Iris contexts and target |
| Global widget adds noise | Empty fragment outside proof mode; opt-in rollout first |
| Missing/mismatched WASM | Pin compatible revisions and add a deterministic asset target |
| Term control overpromises infoview parity | Label it as whole-term details; defer hover popups and subexpression refs |
| Long contexts become too tall | Compact rows and per-goal collapse |
| React state churn | Stable goal/hypothesis ids and keyed components |

## 20. Review decisions

1. Version 2 is a companion panel with whole-term, read-only detail controls.
2. Structural input is the typed `IrisGoal`; the text parser and raw fallback
   are removed.
3. The target domain is versioned and independent of both `Hyps` and React.
4. Pretty-printed strings are leaf render data only, never parser input.
5. The prototype stays opt-in on Lean 4.32.2 with VIR's module-system support.
6. Persistent/spatial glyphs, a judgment rule, target prominence, multi-goal
   cards, stable identities, theme use, and accessibility follow the reviewed
   wireframes.

Staging the runtime deterministically and completing manual editor acceptance
remain rollout work rather than changes to the interaction model.
