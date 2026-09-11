/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Iris.ProofMode.Widget.Client
public import Iris.ProofMode.Widget.Style
public meta import Iris.ProofMode.Widget.Rpc
public import Vir.Attributes
public meta import Vir.Attributes
public import Vir.Infoview
public meta import Vir.Infoview
public import Vir.ProofWidgets

/-!
# Iris proof-mode view

Read `Model.lean` for the display domain and `Rpc.lean` for its typed Iris
provenance. This module owns presentation only; `Client.lean` owns native RPC
and hook lifetimes. `Vir.ProofWidgets.Html` constructs client-side React nodes,
not the serialized server-side `ProofWidgets.Html` type.
-/

public section

namespace Iris.ProofMode.Widget

open Lean.Vir
open Lean.Vir.Browser (DomM)
open Lean.Vir.ProofWidgets

/-- DOM identity is presentation-local, separate from semantic/display IDs. -/
private def goalDomId (goal : DisplayGoal) : String :=
  "iris-proof-mode-goal-" ++ toString goal.index

private def kindLabel : ContextKind → String
  | .persistent => "Persistent"
  | .spatial => "Spatial"

private def kindGlyph : ContextKind → String
  | .persistent => "□"
  | .spatial => "∗"

private def hypothesisCountLabel (count : Nat) (kind : String) : String :=
  s!"{count} {kind} " ++ if count == 1 then "hypothesis" else "hypotheses"

structure InteractiveTermProps where
  term : RenderedTerm
  domId : String
  ariaLabel : String
  target : Bool := false

/-- Contextual subexpression controls. Each selection owns a separate effect lease. -/
def InteractiveTerm (context : Client.Context) : RuntimeM (Component InteractiveTermProps) :=
  Component.ofLean fun ctx => do
  let props := ctx.props
  let term := props.term
  let inspection ← Client.useInspection context
  let termId := props.domId
  let detailId := termId ++ "-detail"
  let parts : Array Html := (termParts term.code).mapIdx fun occurrence part =>
    match if part.text.trimAscii.toString.isEmpty then none else part.reference with
    | none => Html.text part.text
    | some reference =>
      let key := toString reference
      Html.elementWithProps "button" #[
        Lean.Vir.React.Props.id (termId ++ "-" ++ toString occurrence),
        Lean.Vir.React.Props.type "button",
        Lean.Vir.React.Props.title ("Inspect " ++ part.text),
        Lean.Vir.React.Props.ariaLabel (props.ariaLabel ++ ": " ++ part.text),
        Lean.Vir.React.Props.ariaExpanded (inspection.selected == some reference),
        Lean.Vir.React.Props.ariaControls detailId,
        Lean.Vir.React.Props.data "term-ref" key,
        Lean.Vir.React.Props.onClick (inspection.select reference),
        Style.termButton props.target
      ] #[Html.text part.text]
  let details : Array Html := if inspection.selected.isSome then #[
    Html.elementWithProps "span" #[
      Lean.Vir.React.Props.id detailId,
      Lean.Vir.React.Props.role "status",
      Style.termDetails
    ] #[Html.text inspection.detail,
      Html.elementWithProps "button" #[
        Lean.Vir.React.Props.type "button",
        Lean.Vir.React.Props.ariaLabel "Close term inspection",
        Lean.Vir.React.Props.onClick inspection.close,
        Style.collapseButton
      ] #[Html.text "×"]]
  ] else #[]
  Html.elementWithProps "span" #[Style.interactiveTerm]
    (#[Html.elementWithProps "span" #[
      Lean.Vir.React.Props.data "term-id" term.id,
      Lean.Vir.React.Props.ariaLabel props.ariaLabel,
      Style.termCode props.target
    ] parts] ++ details)

structure HypothesisRowProps where
  hypothesis : DisplayHypothesis
  domId : String

def HypothesisRow (context : Client.Context) : RuntimeM (Component HypothesisRowProps) := do
  let interactiveTerm ← InteractiveTerm context
  Component.ofLean fun ctx =>
  let hypothesis := ctx.props.hypothesis
  let nameCell : Html := Html.elementWithProps "span" #[] #[
    Html.elementWithProps "span" #[
      Lean.Vir.React.Props.ariaHidden true,
      Style.glyph
    ] #[Html.text (kindGlyph hypothesis.kind)],
    Html.elementWithProps "strong" #[Style.hypothesisName] #[Html.text hypothesis.name]
  ]
  Html.elementWithProps "li" #[
    Lean.Vir.React.Props.role "listitem",
    Style.hypothesis
  ] #[
    nameCell,
    Html.keyedOfComponent
      ("term-" ++ hypothesis.proposition.id)
      interactiveTerm {
        term := hypothesis.proposition
        domId := ctx.props.domId
        ariaLabel := "Inspect " ++ kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
      }
  ]

structure ContextSectionProps where
  id : String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis

def ContextSection (context : Client.Context) : RuntimeM (Component ContextSectionProps) := do
  let hypothesisRow ← HypothesisRow context
  Component.ofLean fun ctx =>
  let props := ctx.props
  let label := kindLabel props.kind
  let rows : Array Html := props.hypotheses.mapIdx fun index hypothesis =>
    Html.keyedOfComponent
      (props.id ++ "-" ++ hypothesis.id)
      hypothesisRow
      { hypothesis, domId := props.id ++ "-hyp-" ++ toString index }
  Html.elementWithProps "section" #[
    Lean.Vir.React.Props.id props.id,
    Lean.Vir.React.Props.ariaLabel label,
    Style.contextSection (props.kind == .persistent)
  ] #[
    Html.elementWithProps "ul" #[
      Lean.Vir.React.Props.role "list",
      Lean.Vir.React.Props.ariaLabel (label ++ " hypotheses"),
      Style.hypothesisList
    ] rows
  ]

structure TargetSectionProps where
  term : RenderedTerm
  domId : String

def TargetSection (context : Client.Context) : RuntimeM (Component TargetSectionProps) := do
  let interactiveTerm ← InteractiveTerm context
  Component.ofLean fun ctx =>
  Html.elementWithProps "section" #[
    Lean.Vir.React.Props.ariaLabel "Target",
    Style.targetSection
  ] #[
    Html.elementWithProps "div" #[Style.target] #[
      Html.elementWithProps "span" #[
        Lean.Vir.React.Props.ariaHidden true,
        Style.glyph
      ] #[Html.text "⊢"],
      Html.keyedOfComponent
        ("target-" ++ ctx.props.term.id)
        interactiveTerm {
          term := ctx.props.term
          domId := ctx.props.domId
          ariaLabel := "Inspect target"
          target := true
        }
    ]
  ]

structure GoalCardProps where
  goal : DisplayGoal
  initiallyExpanded : Bool

def GoalCard (context : Client.Context) : RuntimeM (Component GoalCardProps) := do
  let contextSection ← ContextSection context
  let targetSection ← TargetSection context
  Component.ofLean fun ctx => do
  let props := ctx.props
  let goal := props.goal
  let expandedState ← Client.useState props.initiallyExpanded
  let expanded := expandedState.value
  let cardId := goalDomId goal
  let contentId := cardId ++ "-content"
  let toggle : DomM Unit := expandedState.set (!expanded)
  let summary :=
    s!"□ {goal.persistent.size} · ∗ {goal.spatial.size}"
  let heading : Html := Html.elementWithProps "h3" #[
    Lean.Vir.React.Props.id (cardId ++ "-heading"),
    Style.goalHeading
  ] #[Html.text goal.title]
  let summaryLabel :=
    hypothesisCountLabel goal.persistent.size "persistent" ++ ", " ++
      hypothesisCountLabel goal.spatial.size "spatial"
  let summaryNode : Html := Html.elementWithProps "p" #[
    Lean.Vir.React.Props.ariaLabel summaryLabel,
    Style.goalSummary
  ] #[Html.text summary]
  let toggleNode : Html := Html.elementWithProps "button" #[
    Lean.Vir.React.Props.id (cardId ++ "-toggle"),
    Lean.Vir.React.Props.type "button",
    Lean.Vir.React.Props.title (if expanded then "Collapse goal" else "Expand goal"),
    Lean.Vir.React.Props.ariaLabel (if expanded then "Collapse " ++ goal.title else "Expand " ++ goal.title),
    Lean.Vir.React.Props.ariaExpanded expanded,
    Lean.Vir.React.Props.ariaControls contentId,
    Lean.Vir.React.Props.onClick toggle,
    Style.collapseButton
  ] #[Html.text (if expanded then "−" else "+")]
  let header : Html := Html.elementWithProps "header" #[Style.goalHeader] #[
    heading,
    summaryNode,
    toggleNode
  ]
  let contexts : Array Html :=
    (if goal.persistent.isEmpty then #[] else #[
      Html.ofComponent contextSection {
        id := cardId ++ "-persistent"
        kind := .persistent
        hypotheses := goal.persistent
      }
    ]) ++
    (if goal.spatial.isEmpty then #[] else #[
      Html.ofComponent contextSection {
        id := cardId ++ "-spatial"
        kind := .spatial
        hypotheses := goal.spatial
      }
    ])
  let content : Array Html :=
    if expanded then #[
      Html.elementWithProps "div" #[
        Lean.Vir.React.Props.id contentId,
        Style.goalContent
      ] (contexts ++ #[Html.ofComponent targetSection {
        term := goal.target
        domId := cardId ++ "-target"
      }])
    ] else #[]
  Html.elementWithProps "article" #[
    Lean.Vir.React.Props.id cardId,
    Lean.Vir.React.Props.ariaLabelledBy (cardId ++ "-heading"),
    Lean.Vir.React.Props.data "goal-id" goal.id,
    Style.goalCard
  ] (#[header] ++ content)

def ProofModeRegion (context : Client.Context) : RuntimeM (Component (Array DisplayGoal)) := do
  let goalCard ← GoalCard context
  Component.ofLean fun ctx =>
  let goals := ctx.props
  let cards : Array Html := goals.zipIdx.map fun (goal, index) =>
    Html.keyedOfComponent ("iris-" ++ goal.id) goalCard {
      goal
      initiallyExpanded := index == 0
    }
  Html.elementWithProps "section" #[
    Lean.Vir.React.Props.id "iris-proof-mode-widget",
    Lean.Vir.React.Props.role "region",
    Lean.Vir.React.Props.ariaLabel "Iris proof mode",
    Style.region
  ] #[Html.elementWithProps "div" #[Style.goalList] cards]

/-- The Lean-authored VIR component mounted by the Iris proof-mode widget. -/
def SnapshotView (context : Client.Context) : RuntimeM (Js (Lean.Vir.React.Component WidgetState)) := do
  let proofModeRegion ← ProofModeRegion context
  Lean.Vir.React.Component.ofLean fun state =>
  if state.goals.isEmpty then
    Lean.Vir.React.Node.fragment #[]
  else
    Lean.Vir.React.Node.component proofModeRegion (componentProps state.goals)

def App : RuntimeM (Js (Lean.Vir.React.Component Lean.Vir.Infoview.Surface)) :=
  Client.application SnapshotView

/-- Workspace-relative location of the VIR runtime built for Iris's Lean toolchain. -/
def runtimeWasmPath : String :=
  ".lake/packages/lean_vir/web/public/vir-upstream.wasm"

def widgetSpec : Lean.Vir.Infoview.ReactWidget where
  component := App
  componentName := "Iris.ProofMode.Widget.createComponent"
  mountName := "Iris.ProofMode.Widget.mount"
  wasmPath := runtimeWasmPath
  setupHint :=
    "This widget uses the Lean 4.32 VIR runtime. Check the VIR error above; after rebuilding VIR or changing dependencies, restart the Lean server."

@[vir_export]
def createComponent : RuntimeM
    (Js (Lean.Vir.React.Component Lean.Vir.Infoview.Surface)) :=
  widgetSpec.component

@[vir_export]
def mount :
    Js Lean.Vir.React.Root →
    Js (Lean.Vir.React.Component Lean.Vir.Infoview.Surface) →
    Lean.Vir.Infoview.Surface → DomM Unit :=
  Lean.Vir.React.Root.renderComponent

def irPackage : Lean.Vir.Infoview.IRPackage :=
  Lean.Vir.Infoview.ReactWidget.irPackage widgetSpec

def widgetProps : Lean.Vir.Infoview.WidgetProps :=
  Lean.Vir.Infoview.ReactWidget.props widgetSpec

end Iris.ProofMode.Widget
