/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.Display
public meta import Iris.ProofMode.Widget.Model
public meta import Vir.Infoview

/-!
# Typed Iris goal ingress

This module is the widget's only proof-state ingress. It asks Lean for
`InteractiveGoal`s, reads each elaborated target through the canonical
`Iris.ProofMode.parseIrisGoal?` interface, and only then projects the resulting
typed `IrisGoal`/`Hyps` data into `DisplayGoal`. Rendered proposition text is a
leaf of that projection and is never parsed to recover proof-mode structure.
-/

public meta section

namespace Iris.ProofMode.Widget

open Lean Lean.Meta Lean.Server Qq
open Iris.BI

/-- Cursor position supplied by VIR when refreshing the widget. -/
structure StateRequest where
  pos : Lsp.Position
  deriving Server.RpcEncodable

private def renderedIProp (id summary : String) (expr : Expr) : MetaM RenderedTerm := do
  let code ← Lean.Widget.ppExprTagged expr Iris.ProofMode.delabIProp
  let type ← instantiateMVars (← inferType expr)
  let typeText ← ppExpr type
  return {
    id
    text := toString code.stripTags
    typeText := toString typeText
    summary
  }

private partial def displayHypotheses
    {u : Level} {prop : Q(Type u)} {bi : Q(BI $prop)} {e : Q($prop)}
    (hyps : Iris.ProofMode.Hyps bi e)
    (names : NameMap Nat := {})
    (acc : Array DisplayHypothesis := #[]) :
    MetaM (NameMap Nat × Array DisplayHypothesis) := do
  match hyps with
  | .emp _ => return (names, acc)
  | .sep _ _ _ _ lhs rhs =>
      let (names, acc) ← displayHypotheses rhs names acc
      displayHypotheses lhs names acc
  | .hyp _ name ivar persistent proposition _ =>
      let (nextIndex, displayName) := match names.find? name with
        | some index =>
            (index + 1, name.appendAfter <|
              if index == 0 then "✝" else "✝" ++ index.toSuperscriptString)
        | none => (0, name)
      let kind := if Iris.ProofMode.isTrue persistent then .persistent else .spatial
      let kindDescription := if kind == .persistent then "persistent" else "spatial"
      let hypothesis : DisplayHypothesis := {
        id := toString ivar.name
        kind
        name := toString displayName
        proposition := ← renderedIProp
          ("iris-hyp-" ++ toString ivar.name)
          (kindDescription ++ " hypothesis " ++ toString displayName)
          proposition
      }
      return (names.insert name nextIndex, acc.push hypothesis)

/--
Project the typed result of `Iris.ProofMode.parseIrisGoal?` into the stable
widget domain.
-/
def toDisplayGoal
    (irisGoal : Iris.ProofMode.IrisGoal)
    (mvarId : MVarId)
    (index : Nat)
    (userName? : Option String) : MetaM DisplayGoal := do
  let (_, hypotheses) ← displayHypotheses irisGoal.hyps
  let hypotheses := hypotheses.reverse
  let title := match userName? with
    | some userName => "case " ++ userName
    | none => s!"goal {index + 1}"
  return {
    id := toString mvarId.name
    index
    title
    persistent := hypotheses.filter (·.kind == .persistent)
    spatial := hypotheses.filter (·.kind == .spatial)
    target := ← renderedIProp
      ("iris-goal-" ++ toString mvarId.name)
      ("target of " ++ title)
      irisGoal.goal
  }

/--
Read one saved Lean goal through Iris's canonical typed goal decoder.

Entering the metavariable context and instantiating its target here makes the
provenance explicit: every `DisplayGoal` accepted by the widget originates in
`Iris.ProofMode.parseIrisGoal?`, never in delaborated infoview text.
-/
private def displayIrisGoalAt?
    (goal : Lean.Widget.InteractiveGoal) (index : Nat) : IO (Option DisplayGoal) :=
  goal.ctx.val.runMetaM {} do
    goal.mvarId.withContext do
      let target ← instantiateMVars (← goal.mvarId.getType)
      let some irisGoal := Iris.ProofMode.parseIrisGoal? target
        | return none
      return some (← toDisplayGoal irisGoal goal.mvarId index goal.userName?)

/-- Return typed Iris proof-mode state for the goals at the requested cursor. -/
@[server_rpc_method]
def state (params : StateRequest) : RequestM (RequestTask WidgetState) := do
  let goalsTask ← Server.FileWorker.getInteractiveGoals {
    textDocument := { uri := (← RequestM.readDoc).meta.uri }
    position := params.pos
  }
  RequestM.mapRequestTaskCostly goalsTask fun goals? => do
    let some goals := goals? | return { goals := #[] }
    let mut displayGoals := #[]
    for (goal, index) in goals.goals.zipIdx do
      if let some displayGoal ← displayIrisGoalAt? goal index then
        displayGoals := displayGoals.push displayGoal
    return { goals := displayGoals }

end Iris.ProofMode.Widget
