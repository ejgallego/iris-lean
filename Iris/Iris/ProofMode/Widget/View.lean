/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Iris.ProofMode.Widget.Client
public import Iris.ProofMode.Widget.Style
public import Vir.Infoview
public import Vir.ProofWidgets.Jsx

/-! Native React view for the typed Iris display domain. Keeping this JSX-only
module separate from the meta RPC registration avoids the upstream widget-parser
scope while retaining the native panel component contract. -/

public section

namespace Iris.ProofMode.Widget.View

open Lean.Vir
open Lean.Vir.Infoview (PanelWidgetProps)
open Lean.Vir.React
open Lean.Vir.ProofWidgets
open scoped Lean.Vir.Js
open scoped Lean.Vir.ProofWidgets.Jsx

private def goalDomId (goal : DisplayGoal) : String :=
  "iris-proof-mode-goal-" ++ toString goal.index

private def kindLabel : ContextKind → String
  | .persistent => "Persistent"
  | .spatial => "Spatial"

private def kindGlyph : ContextKind → String
  | .persistent => "□"
  | .spatial => "∗"

private def countLabel (count : Nat) (kind : String) : String :=
  s!"{count} {kind} " ++ if count == 1 then "hypothesis" else "hypotheses"

structure InteractiveTermProps where
  term : RenderedTerm
  domId : String
  ariaLabel : String
  target : Bool := false

def interactiveTerm (context : Client.Context) : RuntimeM (Client.Component InteractiveTermProps) :=
  Client.Component.ofLean (fun props => do
    let inspection ← Client.useInspection context
    let detailId := props.domId ++ "-detail"
    let nodes ← (termParts props.term.code).mapIdxM fun index part =>
      match if part.text.trimAscii.toString.isEmpty then none else part.reference with
      | none => Html.text part.text
      | some reference => do
        let select ← Js.Function.ofLeanVoid fun (_ : Js Browser.Event) => inspection.select reference
        return ← <button id={(← JsValue.ofString (props.domId ++ "-" ++ toString index))}
            type="button" title={(← JsValue.ofString ("Inspect " ++ part.text))}
            aria-label={(← JsValue.ofString (props.ariaLabel ++ ": " ++ part.text))}
            aria-expanded={(← JsValue.ofBool (inspection.selected == some reference))}
            aria-controls={(← JsValue.ofString detailId)} data-term-ref={(← JsValue.ofString (toString reference))}
            onClick={select} style={(← Style.termButton props.target)}>{Html.text part.text}</button>
    let nodes : Js.Array Node ← Js.Array.ofArray nodes
    let details : Js.Array Node ← if inspection.selected.isSome then
      Js.Array.ofArray #[← <span id={(← JsValue.ofString detailId)} role="status" style={(← Style.termDetails)}>
        {Html.text inspection.detail}<button type="button" aria-label="Close term inspection"
        onClick={← Js.Function.ofLeanVoid fun (_ : Js Browser.Event) => inspection.close}
        style={(← Style.collapseButton)}>×</button></span>]
    else Js.Array.empty
    return ← <span style={(← Style.interactiveTerm)}><span data-term-id={(← JsValue.ofString props.term.id)}
      aria-label={(← JsValue.ofString props.ariaLabel)} style={(← Style.termCode props.target)}>{nodes}</span>{details}</span>)

structure HypothesisProps where
  hypothesis : DisplayHypothesis
  domId : String

def hypothesisRow (context : Client.Context) : RuntimeM (Client.Component HypothesisProps) := do
  let term ← interactiveTerm context
  Client.Component.ofLean (fun props => do
    let hypothesis := props.hypothesis
    let name ← <span><span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>
      {Html.text (kindGlyph hypothesis.kind)}</span><strong style={(← Style.hypothesisName)}>
      {Html.text hypothesis.name}</strong></span>
    let value ← Client.Component.render term {
      term := hypothesis.proposition
      domId := props.domId
      ariaLabel := "Inspect " ++ kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
    }
    return ← <li role="listitem" style={(← Style.hypothesis)}>{name}{value}</li>)

structure ContextProps where
  id : String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis

def contextSection (context : Client.Context) : RuntimeM (Client.Component ContextProps) := do
  let row ← hypothesisRow context
  Client.Component.ofLean (fun props => do
    let label := kindLabel props.kind
    let values ← props.hypotheses.mapIdxM fun index hypothesis =>
      Client.Component.render row { hypothesis, domId := props.id ++ "-hyp-" ++ toString index }
    let values : Js.Array Node ← Js.Array.ofArray values
    return ← <section id={(← JsValue.ofString props.id)} aria-label={(← JsValue.ofString label)}
      style={(← Style.contextSection (props.kind == .persistent))}><ul role="list"
      aria-label={(← JsValue.ofString (label ++ " hypotheses"))} style={(← Style.hypothesisList)}>{values}</ul></section>)

structure TargetProps where
  term : RenderedTerm
  domId : String

def targetSection (context : Client.Context) : RuntimeM (Client.Component TargetProps) := do
  let term ← interactiveTerm context
  Client.Component.ofLean (fun props => do
    let value ← Client.Component.render term {
      term := props.term, domId := props.domId, ariaLabel := "Inspect target", target := true
    }
    return ← <section aria-label="Target" style={(← Style.targetSection)}><div style={(← Style.target)}>
      <span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>⊢</span>{value}</div></section>)

structure GoalProps where
  goal : DisplayGoal
  initiallyExpanded : Bool

def goalCard (context : Client.Context) : RuntimeM (Client.Component GoalProps) := do
  let contextView ← contextSection context
  let targetView ← targetSection context
  Client.Component.ofLean (fun props => do
    let goal := props.goal
    let expandedState ← Client.useState props.initiallyExpanded
    let expanded := expandedState.value
    let cardId := goalDomId goal
    let contentId := cardId ++ "-content"
    let toggle ← Js.Function.ofLeanVoid fun (_ : Js Browser.Event) => expandedState.set (!expanded)
    let summary := s!"□ {goal.persistent.size} · ∗ {goal.spatial.size}"
    let summaryLabel := countLabel goal.persistent.size "persistent" ++ ", " ++ countLabel goal.spatial.size "spatial"
    let header ← <header style={(← Style.goalHeader)}><h3 id={(← JsValue.ofString (cardId ++ "-heading"))}
      style={(← Style.goalHeading)}>{Html.text goal.title}</h3><p aria-label={(← JsValue.ofString summaryLabel)}
      style={(← Style.goalSummary)}>{Html.text summary}</p><button id={(← JsValue.ofString (cardId ++ "-toggle"))}
      type="button" title={(← JsValue.ofString (if expanded then "Collapse goal" else "Expand goal"))}
      aria-label={(← JsValue.ofString (if expanded then "Collapse " ++ goal.title else "Expand " ++ goal.title))}
      aria-expanded={(← JsValue.ofBool expanded)} aria-controls={(← JsValue.ofString contentId)} onClick={toggle}
      style={(← Style.collapseButton)}>{Html.text (if expanded then "−" else "+")}</button></header>
    let mut children : Array (Js Node) := #[]
    if !goal.persistent.isEmpty then
      children := children.push (← Client.Component.render contextView {
        id := cardId ++ "-persistent", kind := .persistent, hypotheses := goal.persistent
      })
    if !goal.spatial.isEmpty then
      children := children.push (← Client.Component.render contextView {
        id := cardId ++ "-spatial", kind := .spatial, hypotheses := goal.spatial
      })
    children := children.push (← Client.Component.render targetView { term := goal.target, domId := cardId ++ "-target" })
    let contents : Js.Array Node ← if expanded then
      let nativeChildren : Js.Array Node ← Js.Array.ofArray children
      Js.Array.ofArray #[← <div id={(← JsValue.ofString contentId)} style={(← Style.goalContent)}>{nativeChildren}</div>]
    else Js.Array.empty
    return ← <article id={(← JsValue.ofString cardId)} aria-labelledby={(← JsValue.ofString (cardId ++ "-heading"))}
      data-goal-id={(← JsValue.ofString goal.id)} style={(← Style.goalCard)}>{header}{contents}</article>)

def region (context : Client.Context) : RuntimeM (Client.Component (Array DisplayGoal)) := do
  let card ← goalCard context
  Client.Component.ofLean (fun goals => do
    let cards ← goals.zipIdx.mapM fun (goal, index) =>
      Client.Component.render card { goal, initiallyExpanded := index == 0 }
    let cards : Js.Array Node ← Js.Array.ofArray cards
    return ← <section id="iris-proof-mode-widget" role="region" aria-label="Iris proof mode" style={(← Style.region)}>
      <div style={(← Style.goalList)}>{cards}</div></section>)

def snapshotView (context : Client.Context) : RuntimeM (Client.Component WidgetState) := do
  let display ← region context
  Client.Component.ofLean (fun state => do
    if state.goals.isEmpty then do
      let props ← Js.Object.empty
      let children : Js.Array Node ← Js.Array.empty
      Node.fragment props children
    else
      Client.Component.render display state.goals)

def app : RuntimeM (FunctionComponent PanelWidgetProps) :=
  Client.application snapshotView

end Iris.ProofMode.Widget.View
