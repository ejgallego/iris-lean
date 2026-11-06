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
    let expanded ← Client.useState false
    let enabled := props.context.enabled && (← props.context.active.get)
    let codeNode (id text : String) (index : Nat) : RuntimeM (Js Node) := do
      let value ← if enabled then do
        let code ← Js.Object.get props.context.codes (← JsValue.ofString (toString index))
        let nativeProps ← Js.Object.empty
        Js.Object.set nativeProps (← JsValue.ofString "fmt") code
        -- Only presentation survives; native semantics belong to this snapshot.
        Js.Object.set nativeProps (← JsValue.ofString "key") (← JsValue.ofString s!"{props.context.epoch}:{id}")
        Node.functionComponent native nativeProps (← Js.Array.empty)
      else Html.text text
      return ← jsx%{<span data-term-id={(← JsValue.ofString id)}
        data-term-active={(← JsValue.ofBool enabled)} aria-label={(← JsValue.ofString props.ariaLabel)}
        style={(← Style.termCode props.target)}>{value}</span>}
    let value ← if let some inv := props.term.invariant? then do
      let name ← codeNode (props.term.id ++ "-name") inv.name.text inv.name.codeIndex
      let toggle ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => expanded.set (!expanded.value)
      let body : Js.Array Node ← if expanded.value then
        Js.Array.ofArray #[← jsx%{<div key="body" style={(← Style.invariantBody)}>
          {← codeNode (props.term.id ++ "-body") inv.body.text inv.body.codeIndex}</div>}]
      else Js.Array.empty
      jsx%{<div data-invariant-open={(← JsValue.ofBool expanded.value)}>
        <div style={(← Style.invariantHeading)}><span>inv</span>{name}
          <button type="button" aria-label="Invariant body" aria-expanded={(← JsValue.ofBool expanded.value)}
            onClick={toggle} style={(← Style.invariantDisclosure)}>{Html.text (if expanded.value then "⟨−⟩" else "⟨…⟩")}</button></div>{body}</div>}
    else codeNode props.term.id props.term.text props.term.codeIndex
    return ← jsx%{<span style={(← Style.interactiveTerm)}>{value}</span>})

structure AnnotationProps where
  context : Client.Context
  annotation : Annotation
  resourceName : String := ""

def annotationRow : RuntimeM (Client.Component AnnotationProps) := do
  let term ← interactiveTerm
  Client.Component.ofLean (fun props => do
    let annotation := props.annotation
    let value : Js.Array Node ← if let some after := annotation.term? then
      Js.Array.ofArray #[← Client.Component.render term {
        context := props.context, term := after
        ariaLabel := if annotation.kind == .target then "Target after tactic"
          else props.resourceName ++ " after tactic"
      } (some (← js#"term"))]
    else Js.Array.empty
    return ← jsx%{<div data-annotation-kind={(← JsValue.ofString annotation.kind.label)}
      data-resource-name={(← JsValue.ofString props.resourceName)}
      data-after-goal-id={(← JsValue.ofString (annotation.branchId?.getD ""))}
      style={(← Style.annotation annotation.term?.isSome)}>
      <span style={(← Style.annotationLead)}>{Html.text ("↳ " ++ annotation.lead)}</span>{value}</div>})

structure HypothesisProps where
  context : Client.Context
  hypothesis : DisplayHypothesis
  annotations : Array Annotation := #[]

def hypothesisRow : RuntimeM (Client.Component HypothesisProps) := do
  let term ← interactiveTerm
  let annotation ← annotationRow
  Client.Component.ofLean (fun props => do
    let hypothesis := props.hypothesis
    let name ← jsx%{<span><span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>
      {Html.text (kindGlyph hypothesis.kind)}</span><strong style={(← Style.hypothesisName)}>
      {Html.text hypothesis.name}</strong>{Html.text ": "}</span>}
    let value ← Client.Component.render term {
      context := props.context
      term := hypothesis.proposition
      ariaLabel := kindLabel hypothesis.kind ++ " hypothesis " ++ hypothesis.name
    } (some (← js#"term"))
    let annotations ← props.annotations.zipIdx.mapM fun (entry, index) => do
      Client.Component.render annotation {
        context := props.context, annotation := entry, resourceName := hypothesis.name
      } (some (← JsValue.ofString s!"annotation-{index}"))
    let annotations : Js.Array Node ← Js.Array.ofArray annotations
    return ← jsx%{<li role="listitem" data-hypothesis-name={(← JsValue.ofString hypothesis.name)}
      style={(← Style.hypothesis)}>{name}{value}{annotations}</li>})

structure ContextProps where
  context : Client.Context
  id : Js String
  kind : ContextKind
  hypotheses : Array DisplayHypothesis
  comparison? : Option DisplayComparison

def contextSection : RuntimeM (Client.Component ContextProps) := do
  let row ← hypothesisRow
  let annotation ← annotationRow
  Client.Component.ofLean (fun props => do
    let label := kindLabel props.kind
    let slots ← Client.useState ({} : PresentationKeys)
    let ids := props.hypotheses.map (·.id)
    let keys := slots.value.update ids
    if slots.value.ids != ids then slots.set keys
    let mut values ← props.hypotheses.zipIdx.mapM fun (hypothesis, index) => do
      Client.Component.render row {
        hypothesis, context := props.context
        annotations := props.comparison?.map (·.hypothesisAnnotations hypothesis) |>.getD #[]
      } (some (← JsValue.ofString (toString keys.keys[index]!)))
    for (hypothesis, entry) in props.comparison?.map (·.additions props.kind) |>.getD #[] do
      let value ← Client.Component.render annotation {
        context := props.context, annotation := entry, resourceName := hypothesis.name }
      values := values.push (← jsx%{<li key={(← JsValue.ofString s!"added-{entry.branchId?}-{hypothesis.id}")}
        role="listitem">{value}</li>})
    let nativeValues : Js.Array Node ← Js.Array.ofArray values
    return ← jsx%{<section id={props.id} aria-label={(← JsValue.ofString label)}
      style={(← Style.contextSection (props.kind == .persistent))}><ul role="list"
      aria-label={(← JsValue.ofString (label ++ " hypotheses"))} style={(← Style.hypothesisList)}>{nativeValues}</ul></section>})

structure TargetProps where
  context : Client.Context
  term : RenderedTerm
  annotations : Array Annotation := #[]

def targetSection : RuntimeM (Client.Component TargetProps) := do
  let term ← interactiveTerm
  let annotation ← annotationRow
  Client.Component.ofLean (fun props => do
    let value ← Client.Component.render term {
      context := props.context
      term := props.term, ariaLabel := "Target", target := true
    } (some (← js#"term"))
    let annotations ← props.annotations.zipIdx.mapM fun (entry, index) => do
      Client.Component.render annotation { context := props.context, annotation := entry }
        (some (← JsValue.ofString s!"target-{index}"))
    let annotations : Js.Array Node ← Js.Array.ofArray annotations
    return ← jsx%{<section aria-label="Target" style={(← Style.targetSection)}><div style={(← Style.target)}>
      <span aria-hidden={(← JsValue.ofBool true)} style={(← Style.glyph)}>⊢</span>{value}</div>{annotations}</section>})

structure GoalProps where
  context : Client.Context
  goal : DisplayGoal
  initiallyExpanded : Bool

def goalCard : RuntimeM (Client.Component GoalProps) := do
  let contextView ← contextSection
  let targetView ← targetSection
  let termView ← interactiveTerm
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
    let mask : Js.Array Node ← if let some part := goal.mask? then do
      let value ← Client.Component.render termView {
        context := props.context, ariaLabel := "Current mask"
        term := { id := "mask", text := part.text, codeIndex := part.codeIndex, typeText := "CoPset", summary := "current mask" } }
      Js.Array.ofArray #[← jsx%{<span key="mask" data-mask-chip="true" style={(← Style.maskChip)}><span>mask</span>{value}</span>}]
    else Js.Array.empty
    let header ← jsx%{<header style={(← Style.goalHeader)}><h3 id={headingId}
      style={(← Style.goalHeading)}>{Html.text goal.title}</h3>{mask}<p aria-label={(← JsValue.ofString summaryLabel)}
      style={(← Style.goalSummary)}>{Html.text summary}</p><button id={toggleId}
      type="button" title={(← JsValue.ofString (if expanded then "Collapse goal" else "Expand goal"))}
      aria-label={(← JsValue.ofString (if expanded then "Collapse " ++ goal.title else "Expand " ++ goal.title))}
      aria-expanded={(← JsValue.ofBool expanded)} aria-controls={contentId} onClick={toggle}
      style={(← Style.collapseButton)}>{Html.text (if expanded then "−" else "+")}</button></header>}
    let mut children : Array (Js Node) := #[]
    if let some comparison := goal.comparison?.filter (!·.quiet) then
      let summary := goal.changeSummary comparison
      children := children.push (← jsx%{<div key="comparison" data-comparison-summary="true"
        data-tactic={(← JsValue.ofString comparison.tactic)}
        data-comparison-outcome={(← JsValue.ofString (if comparison.closed then "closed"
          else if comparison.unavailable.isSome then "unavailable" else "ready"))}
        title={(← JsValue.ofString summary)} style={(← Style.changeSummary)}>{Html.text summary}</div>})
    if !goal.persistent.isEmpty || (goal.comparison?.map (·.additions .persistent) |>.getD #[]).size > 0 then
      children := children.push (← Client.Component.render contextView {
        context := props.context, comparison? := goal.comparison?
        id := persistentId, kind := .persistent, hypotheses := goal.persistent
      } (some (← js#"persistent")))
    if !goal.spatial.isEmpty || (goal.comparison?.map (·.additions .spatial) |>.getD #[]).size > 0 then
      children := children.push (← Client.Component.render contextView {
        context := props.context, comparison? := goal.comparison?
        id := spatialId, kind := .spatial, hypotheses := goal.spatial
      } (some (← js#"spatial")))
    children := children.push (← Client.Component.render targetView {
      term := goal.target, context := props.context
      annotations := goal.comparison?.map (·.targetAnnotations) |>.getD #[] }
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
