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
  context : Client.Context
  term : RenderedTerm
  ariaLabel : String
  target : Bool := false

/-- The exact upstream component receives the original tagged-code object. Stale
    snapshots render plain text, unmounting all native popups and semantic handlers. -/
def interactiveTerm : RuntimeM (Client.Component InteractiveTermProps) := do
  let native ← Lean.Vir.Infoview.interactiveCode
  Client.Component.ofLean (fun props => do
    let enabled := props.context.enabled && (← props.context.active.get)
    let value ← if enabled then do
      let code ← Js.Object.get props.context.codes (← JsValue.ofString (toString props.term.codeIndex))
      let nativeProps ← Js.Object.empty
      Js.Object.set nativeProps (← JsValue.ofString "fmt") code
      Node.functionComponent native nativeProps (← Js.Array.empty)
    else Html.text props.term.text
    return ← jsx%{<span style={(← Style.interactiveTerm)}><span data-term-id={(← JsValue.ofString props.term.id)}
      data-term-active={(← JsValue.ofBool enabled)} aria-label={(← JsValue.ofString props.ariaLabel)}
      style={(← Style.termCode props.target)}>{value}</span></span>})

structure HypothesisProps where
  context : Client.Context
  hypothesis : DisplayHypothesis

def hypothesisRow : RuntimeM (Client.Component HypothesisProps) := do
  let term ← interactiveTerm
  Client.Component.ofLean (fun props => do
    let hypothesis := props.hypothesis
    let name ← jsx%{<span><span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>
      {Html.text (kindGlyph hypothesis.kind)}</span><strong style={(← Style.hypothesisName)}>
      {Html.text hypothesis.name}</strong>{Html.text ": "}</span>}
    let value ← Client.Component.render term {
      context := props.context
      term := hypothesis.proposition
      ariaLabel := kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
    } (some (← JsValue.ofString (toString props.context.epoch)))
    return ← jsx%{<li role="listitem" style={(← Style.hypothesis)}>{name}{value}</li>})

structure ContextProps where
  context : Client.Context
  id : Js String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis

def contextSection : RuntimeM (Client.Component ContextProps) := do
  let row ← hypothesisRow
  Client.Component.ofLean (fun props => do
    let label := kindLabel props.kind
    let values ← props.hypotheses.mapM fun hypothesis => do
      Client.Component.render row { hypothesis, context := props.context } (some (← JsValue.ofString hypothesis.id))
    let values : Js.Array Node ← Js.Array.ofArray values
    return ← jsx%{<section id={props.id} aria-label={(← JsValue.ofString label)}
      style={(← Style.contextSection (props.kind == .persistent))}><ul role="list"
      aria-label={(← JsValue.ofString (label ++ " hypotheses"))} style={(← Style.hypothesisList)}>{values}</ul></section>})

structure TargetProps where
  context : Client.Context
  term : RenderedTerm

def targetSection : RuntimeM (Client.Component TargetProps) := do
  let term ← interactiveTerm
  Client.Component.ofLean (fun props => do
    let value ← Client.Component.render term {
      context := props.context
      term := props.term, ariaLabel := "Target", target := true
    } (some (← JsValue.ofString (toString props.context.epoch)))
    return ← jsx%{<section aria-label="Target" style={(← Style.targetSection)}><div style={(← Style.target)}>
      <span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>⊢</span>{value}</div></section>})

structure GoalProps where
  context : Client.Context
  goal : DisplayGoal
  initiallyExpanded : Bool

def goalCard : RuntimeM (Client.Component GoalProps) := do
  let contextView ← contextSection
  let targetView ← targetSection
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
        context := props.context
        id := persistentId, kind := .persistent, hypotheses := goal.persistent
      } (some (← js#"persistent")))
    if !goal.spatial.isEmpty then
      children := children.push (← Client.Component.render contextView {
        context := props.context
        id := spatialId, kind := .spatial, hypotheses := goal.spatial
      } (some (← js#"spatial")))
    children := children.push (← Client.Component.render targetView { term := goal.target, context := props.context }
      (some (← js#"target")))
    let contents : Js.Array Node ← if expanded then
      let nativeChildren : Js.Array Node ← Js.Array.ofArray children
      Js.Array.ofArray #[← jsx%{<div key="content" id={contentId} style={(← Style.goalContent)}>{nativeChildren}</div>}]
    else Js.Array.empty
    return ← jsx%{<article id={cardId} aria-labelledby={headingId}
      data-goal-id={(← JsValue.ofString goal.id)} style={(← Style.goalCard)}>{header}{contents}</article>})

def region : RuntimeM (Client.Component Client.ViewProps) := do
  let card ← goalCard
  Client.Component.ofLean (fun props => do
    let regionId ← Hooks.useId
    let cards ← props.state.goals.zipIdx.mapM fun (goal, index) => do
      Client.Component.render card { goal, initiallyExpanded := index == 0, context := props.context }
        (some (← JsValue.ofString s!"{props.scope}:{props.keys[index]!}"))
    let cards : Js.Array Node ← Js.Array.ofArray cards
    return ← jsx%{<section id={regionId}
      data-iris-proof-mode-widget={(← JsValue.ofString "true")} role="region" aria-label="Iris proof mode"
      style={(← Style.region)}>
      <div style={(← Style.goalList)}>{cards}</div></section>})

def snapshotView : RuntimeM (Client.Component Client.ViewProps) := do
  let display ← region
  Client.Component.ofLean (fun props => do
    if props.state.goals.isEmpty then do
      let props ← Js.Object.empty
      let children : Js.Array Node ← Js.Array.empty
      Node.fragment props children
    else
      Client.Component.render display props)

def app : RuntimeM (FunctionComponent PanelWidgetProps) := do
  Client.application (← snapshotView)

end Iris.ProofMode.Widget.View
