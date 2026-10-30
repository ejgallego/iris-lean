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

/-! Native React view for the typed Iris display domain. The browser rendering
layer is independent of the server's meta RPC implementation. -/

public section

namespace Iris.ProofMode.Widget.View

open Lean.Vir
open Lean.Vir.Infoview (PanelWidgetProps)
open Lean.Vir.React
open Lean.Vir.ProofWidgets
open scoped Lean.Vir.Js
open scoped Lean.Vir.ProofWidgets.Jsx

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
  ariaLabel : String
  target : Bool := false

def interactiveTerm (context : Client.Context) : RuntimeM (Client.Component InteractiveTermProps) :=
  Client.Component.ofLean (fun props => do
    let inspection ← Client.useInspection context
    let detailId ← Hooks.useId
    let nodes ← (termParts props.term.code).zipIdx.mapM fun (part, index) =>
      match if part.text.trimAscii.toString.isEmpty then none else part.reference with
      | none => Html.text part.text
      | some reference => do
        let select ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => inspection.select reference
        return ← jsx%{<button key={(← JsValue.ofString (toString index))}
            type="button" title={(← JsValue.ofString ("Inspect " ++ part.text))}
            aria-label={(← JsValue.ofString (props.ariaLabel ++ ": " ++ part.text))}
            aria-expanded={(← JsValue.ofBool (inspection.selected == some reference))}
            aria-controls={detailId} data-term-ref={(← JsValue.ofString (toString reference))}
            onClick={select} style={(← Style.termButton props.target)}>{Html.text part.text}</button>}
    let nodes : Js.Array Node ← Js.Array.ofArray nodes
    let details : Js.Array Node ← if inspection.selected.isSome then
      let detail ← Node.text inspection.detail
      Js.Array.ofArray #[← jsx%{<span key="inspection" id={detailId} role="status" style={(← Style.termDetails)}>
        {detail}<button type="button" aria-label="Close term inspection"
        onClick={← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => inspection.close}
        style={(← Style.collapseButton)}>×</button></span>}]
    else Js.Array.empty
    return ← jsx%{<span style={(← Style.interactiveTerm)}><span data-term-id={(← JsValue.ofString props.term.id)}
      aria-label={(← JsValue.ofString props.ariaLabel)} style={(← Style.termCode props.target)}>{nodes}</span>{details}</span>})

structure HypothesisProps where
  hypothesis : DisplayHypothesis

def hypothesisRow (context : Client.Context) : RuntimeM (Client.Component HypothesisProps) := do
  let term ← interactiveTerm context
  Client.Component.ofLean (fun props => do
    let hypothesis := props.hypothesis
    let name ← jsx%{<span><span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>
      {Html.text (kindGlyph hypothesis.kind)}</span><strong style={(← Style.hypothesisName)}>
      {Html.text hypothesis.name}</strong></span>}
    let value ← Client.Component.render term {
      term := hypothesis.proposition
      ariaLabel := "Inspect " ++ kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
    }
    return ← jsx%{<li role="listitem" style={(← Style.hypothesis)}>{name}{value}</li>})

structure ContextProps where
  id : Js String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis

def contextSection (context : Client.Context) : RuntimeM (Client.Component ContextProps) := do
  let row ← hypothesisRow context
  Client.Component.ofLean (fun props => do
    let label := kindLabel props.kind
    let values ← props.hypotheses.mapM fun hypothesis => do
      Client.Component.render row { hypothesis } (some (← JsValue.ofString hypothesis.id))
    let values : Js.Array Node ← Js.Array.ofArray values
    return ← jsx%{<section id={props.id} aria-label={(← JsValue.ofString label)}
      style={(← Style.contextSection (props.kind == .persistent))}><ul role="list"
      aria-label={(← JsValue.ofString (label ++ " hypotheses"))} style={(← Style.hypothesisList)}>{values}</ul></section>})

structure TargetProps where
  term : RenderedTerm

def targetSection (context : Client.Context) : RuntimeM (Client.Component TargetProps) := do
  let term ← interactiveTerm context
  Client.Component.ofLean (fun props => do
    let value ← Client.Component.render term {
      term := props.term, ariaLabel := "Inspect target", target := true
    }
    return ← jsx%{<section aria-label="Target" style={(← Style.targetSection)}><div style={(← Style.target)}>
      <span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>⊢</span>{value}</div></section>})

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
    let cardId ← Hooks.useId
    let headingId ← Hooks.useId
    let contentId ← Hooks.useId
    let toggleId ← Hooks.useId
    let persistentId ← Hooks.useId
    let spatialId ← Hooks.useId
    let toggle ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => expandedState.set (!expanded)
    let summary := s!"□ {goal.persistent.size} · ∗ {goal.spatial.size}"
    let summaryLabel := countLabel goal.persistent.size "persistent" ++ ", " ++ countLabel goal.spatial.size "spatial"
    let header ← jsx%{<header style={(← Style.goalHeader)}><h3 id={headingId}
      style={(← Style.goalHeading)}>{Html.text goal.title}</h3><p aria-label={(← JsValue.ofString summaryLabel)}
      style={(← Style.goalSummary)}>{Html.text summary}</p><button id={toggleId}
      type="button" title={(← JsValue.ofString (if expanded then "Collapse goal" else "Expand goal"))}
      aria-label={(← JsValue.ofString (if expanded then "Collapse " ++ goal.title else "Expand " ++ goal.title))}
      aria-expanded={(← JsValue.ofBool expanded)} aria-controls={contentId} onClick={toggle}
      style={(← Style.collapseButton)}>{Html.text (if expanded then "−" else "+")}</button></header>}
    let mut children : Array (Js Node) := #[]
    if !goal.persistent.isEmpty then
      children := children.push (← Client.Component.render contextView {
        id := persistentId, kind := .persistent, hypotheses := goal.persistent
      } (some (← js#"persistent")))
    if !goal.spatial.isEmpty then
      children := children.push (← Client.Component.render contextView {
        id := spatialId, kind := .spatial, hypotheses := goal.spatial
      } (some (← js#"spatial")))
    children := children.push (← Client.Component.render targetView { term := goal.target }
      (some (← js#"target")))
    let contents : Js.Array Node ← if expanded then
      let nativeChildren : Js.Array Node ← Js.Array.ofArray children
      Js.Array.ofArray #[← jsx%{<div key="content" id={contentId} style={(← Style.goalContent)}>{nativeChildren}</div>}]
    else Js.Array.empty
    return ← jsx%{<article id={cardId} aria-labelledby={headingId}
      data-goal-id={(← JsValue.ofString goal.id)} style={(← Style.goalCard)}>{header}{contents}</article>})

def region (context : Client.Context) : RuntimeM (Client.Component (Array DisplayGoal)) := do
  let card ← goalCard context
  Client.Component.ofLean (fun goals => do
    let regionId ← Hooks.useId
    let cards ← goals.zipIdx.mapM fun (goal, index) => do
      Client.Component.render card { goal, initiallyExpanded := index == 0 }
        (some (← JsValue.ofString goal.id))
    let cards : Js.Array Node ← Js.Array.ofArray cards
    return ← jsx%{<section id={regionId}
      data-iris-proof-mode-widget={(← JsValue.ofString "true")} role="region" aria-label="Iris proof mode"
      style={(← Style.region)}>
      <div style={(← Style.goalList)}>{cards}</div></section>})

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
