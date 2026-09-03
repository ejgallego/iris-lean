/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Iris.ProofMode.Widget.Style
public meta import Iris.ProofMode.Widget.Rpc
public import Vir.Attributes
public meta import Vir.Attributes
public import Vir.Infoview
public meta import Vir.Infoview
public import Vir.ProofWidgets

public section

namespace Iris.ProofMode.Widget

open Lean.Vir
open Lean.Vir.Browser (DomM)
open Lean.Vir.ProofWidgets

private def safeId (id : String) : String :=
  id.map fun char =>
    if char.isAlphanum || char == '-' || char == '_' then char else '-'

private def goalDomId (goal : DisplayGoal) : String :=
  let suffix := if goal.id.isEmpty then toString goal.index else safeId goal.id
  "iris-proof-mode-goal-" ++ suffix

private def kindLabel : ContextKind → String
  | .persistent => "Persistent"
  | .spatial => "Spatial"

private def kindGlyph : ContextKind → String
  | .persistent => "□"
  | .spatial => "∗"

private def hypothesisCountLabel (count : Nat) (kind : String) : String :=
  s!"{count} {kind} " ++ if count == 1 then "hypothesis" else "hypotheses"

private def resolvedTermDetail (info : ResolvedRef) : String :=
  let typeText := if info.typeText.isEmpty then "expression" else info.typeText
  if info.position.isEmpty then typeText else typeText ++ " · " ++ info.position

structure InteractiveTermProps where
  term : RenderedTerm
  ariaLabel : String
  target : Bool := false

/-- A term-sized, keyboard-accessible entry point to VIR's expression-ref RPC. -/
def InteractiveTerm : RuntimeM (Component InteractiveTermProps) :=
  Component.ofLean fun ctx => do
  let props := ctx.props
  let term := props.term
  let initialExpanded ← JsValue.ofBool false
  let expandedState ← Lean.Vir.React.StateTuple.toState
    (← Lean.Vir.React.Hooks.useState initialExpanded)
  let expanded ← JsValue.toBool expandedState.value
  let initialDetail ← JsValue.ofString term.typeText
  let detailState ← Lean.Vir.React.StateTuple.toState
    (← Lean.Vir.React.Hooks.useState initialDetail)
  let detail ← JsValue.toString detailState.value
  let termId := "iris-term-" ++ safeId term.id
  let detailId := termId ++ "-detail"
  let rpcTerm := ExprWithCtx.save term.id term.text term.typeText term.summary
  let typeSuffix := if term.typeText.isEmpty then "" else " : " ++ term.typeText
  let toggleDetails : DomM Unit := do
    if expanded then
      Lean.Vir.React.State.set expandedState (← JsValue.ofBool false)
    else
      Lean.Vir.React.State.set expandedState (← JsValue.ofBool true)
      Lean.Vir.React.State.set detailState (← JsValue.ofString "resolving…")
      let available ← Rpc.resolve rpcTerm fun info => do
        Lean.Vir.React.State.set detailState (← JsValue.ofString (resolvedTermDetail info))
      if !available then
        let fallback := if term.typeText.isEmpty then "term details unavailable" else term.typeText
        Lean.Vir.React.State.set detailState (← JsValue.ofString fallback)
  let button : Html := Html.elementWithProps "button" #[
    Lean.Vir.React.Props.id termId,
    Lean.Vir.React.Props.type "button",
    Lean.Vir.React.Props.title (term.summary ++ typeSuffix ++ " — click for details"),
    Lean.Vir.React.Props.ariaLabel props.ariaLabel,
    Lean.Vir.React.Props.ariaExpanded expanded,
    Lean.Vir.React.Props.ariaControls detailId,
    Lean.Vir.React.Props.data "term-ref" term.id,
    Lean.Vir.React.Props.onClick toggleDetails,
    Style.termButton props.target
  ] #[Html.text term.text]
  let details : Array Html := if expanded then #[
    Html.elementWithProps "span" #[
      Lean.Vir.React.Props.id detailId,
      Lean.Vir.React.Props.role "status",
      Style.termDetails
    ] #[Html.text detail]
  ] else #[]
  Html.elementWithProps "span" #[Style.interactiveTerm] (#[button] ++ details)

def HypothesisRow : RuntimeM (Component DisplayHypothesis) := do
  let interactiveTerm ← InteractiveTerm
  Component.ofLean fun ctx =>
  let hypothesis := ctx.props
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
      ("term-" ++ hypothesis.proposition.id ++ "-" ++ hypothesis.proposition.text)
      interactiveTerm {
        term := hypothesis.proposition
        ariaLabel := "Inspect " ++ kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
      }
  ]

structure ContextSectionProps where
  id : String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis

def ContextSection : RuntimeM (Component ContextSectionProps) := do
  let hypothesisRow ← HypothesisRow
  Component.ofLean fun ctx =>
  let props := ctx.props
  let label := kindLabel props.kind
  let rows : Array Html := props.hypotheses.map fun hypothesis =>
    Html.keyedOfComponent
      (props.id ++ "-" ++ hypothesis.id)
      hypothesisRow
      hypothesis
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

def TargetSection : RuntimeM (Component RenderedTerm) := do
  let interactiveTerm ← InteractiveTerm
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
        ("target-" ++ ctx.props.id ++ "-" ++ ctx.props.text)
        interactiveTerm {
          term := ctx.props
          ariaLabel := "Inspect target"
          target := true
        }
    ]
  ]

structure GoalCardProps where
  goal : DisplayGoal
  initiallyExpanded : Bool

def GoalCard : RuntimeM (Component GoalCardProps) := do
  let contextSection ← ContextSection
  let targetSection ← TargetSection
  Component.ofLean fun ctx => do
  let props := ctx.props
  let goal := props.goal
  let initialExpanded ← JsValue.ofBool props.initiallyExpanded
  let expandedState ← Lean.Vir.React.StateTuple.toState
    (← Lean.Vir.React.Hooks.useState initialExpanded)
  let expanded ← JsValue.toBool expandedState.value
  let cardId := goalDomId goal
  let contentId := cardId ++ "-content"
  let toggle : DomM Unit := do
    let next ← JsValue.ofBool (!expanded)
    Lean.Vir.React.State.set expandedState next
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
      ] (contexts ++ #[Html.ofComponent targetSection goal.target])
    ] else #[]
  Html.elementWithProps "article" #[
    Lean.Vir.React.Props.id cardId,
    Lean.Vir.React.Props.ariaLabelledBy (cardId ++ "-heading"),
    Lean.Vir.React.Props.data "goal-id" goal.id,
    Style.goalCard
  ] (#[header] ++ content)

def ProofModeRegion : RuntimeM (Component (Array DisplayGoal)) := do
  let goalCard ← GoalCard
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
def App : RuntimeM (Js (Lean.Vir.React.Component WidgetState)) := do
  let proofModeRegion ← ProofModeRegion
  Lean.Vir.React.Component.ofLean fun state =>
  if state.goals.isEmpty then
    Lean.Vir.React.Node.fragment #[]
  else
    Lean.Vir.React.Node.component proofModeRegion (componentProps state.goals)

/-- Workspace-relative location of the VIR runtime built for Iris's Lean toolchain. -/
def runtimeWasmPath : String :=
  ".lake/packages/lean_vir/web/public/vir-upstream.wasm"

def widgetSpec : Lean.Vir.Infoview.ReactRpcWidget WidgetState where
  component := App
  componentName := "Iris.ProofMode.Widget.createComponent"
  mountName := "Iris.ProofMode.Widget.mount"
  wasmPath := runtimeWasmPath
  setupHint :=
    "This widget uses the Lean 4.32 VIR runtime. Check the VIR error above; after rebuilding VIR or changing dependencies, restart the Lean server."

@[vir_export]
def createComponent : RuntimeM
    (Js (Lean.Vir.React.Component Lean.Vir.Infoview.RpcJson)) :=
  Lean.Vir.Infoview.ReactRpcWidget.createComponent widgetSpec

@[vir_export]
def mount :
    Js Lean.Vir.React.Root →
    Js (Lean.Vir.React.Component Lean.Vir.Infoview.RpcJson) →
    Lean.Vir.Infoview.RpcJson → DomM Unit :=
  Lean.Vir.Infoview.ReactRpcWidget.mount

def irPackage : Lean.Vir.Infoview.IRPackage :=
  Lean.Vir.Infoview.ReactRpcWidget.irPackage widgetSpec

def widgetProps : Lean.Vir.Infoview.WidgetProps :=
  Lean.Vir.Infoview.ReactRpcWidget.rpcProps widgetSpec
    "Iris.ProofMode.Widget.state"

end Iris.ProofMode.Widget
