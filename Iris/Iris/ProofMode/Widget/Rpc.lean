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
open Lean.Widget (CodeWithInfos InteractiveGoal ppExprTagged)
open Iris.BI

/-- Cursor position supplied by VIR when refreshing the widget. -/
structure StateRequest where
  pos : Lsp.Position
  deriving RpcEncodable

/-- Iris metadata and native tagged terms travel separately. The infoview RPC client
registers references inside `codes`; the browser preserves these exact objects. -/
structure SnapshotReply where
  display : String
  codes : Array CodeWithInfos
  deriving RpcEncodable

abbrev ProjectionM := StateT (Array CodeWithInfos) MetaM

private def renderedIProp (id summary : String) (expr : Expr) : ProjectionM RenderedTerm := do
  let code ← ppExprTagged expr delabIProp
  let type ← instantiateMVars (← inferType expr)
  let typeText ← ppExpr type
  return {
    id
    text := toString code.stripTags
    typeText := toString typeText
    summary
    codeIndex := ← modifyGet fun codes => (codes.size, codes.push code)
  }

private partial def displayHypotheses
    {u : Level} {prop : Q(Type u)} {bi : Q(BI $prop)} {e : Q($prop)}
    (hyps : Hyps bi e)
    (names : NameMap Nat := {})
    (acc : Array DisplayHypothesis := #[]) :
    ProjectionM (NameMap Nat × Array DisplayHypothesis) := do
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
      let kind := if isTrue persistent then .persistent else .spatial
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
    (irisGoal : IrisGoal)
    (mvarId : MVarId)
    (index : Nat)
    (userName? : Option String) : ProjectionM DisplayGoal := do
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
    (goal : InteractiveGoal) (index : Nat) (codes : Array CodeWithInfos) :
    IO (Option DisplayGoal × Array CodeWithInfos) :=
  goal.ctx.val.runMetaM {} do
    goal.mvarId.withContext do
      let target ← instantiateMVars (← goal.mvarId.getType)
      let some irisGoal := parseIrisGoal? target
        | return (none, codes)
      let (display, codes) ← (toDisplayGoal irisGoal goal.mvarId index goal.userName?).run codes
      return (some display, codes)

/-- Return typed Iris proof-mode state for the goals at the requested cursor. -/
@[server_rpc_method]
def state (params : StateRequest) : RequestM (RequestTask SnapshotReply) := do
  let goalsTask ← FileWorker.getInteractiveGoals {
    textDocument := { uri := (← RequestM.readDoc).meta.uri }
    position := params.pos
  }
  RequestM.mapRequestTaskCostly goalsTask fun goals? => do
    RequestM.checkCancelled
    let mut displayGoals := #[]
    let mut codes := #[]
    if let some goals := goals? then
      for (goal, index) in goals.goals.zipIdx do
        -- Cancellation is cooperative: do not start another goal after retirement.
        RequestM.checkCancelled
        let (displayGoal?, nextCodes) ← displayIrisGoalAt? goal index codes
        codes := nextCodes
        if let some displayGoal := displayGoal? then
          displayGoals := displayGoals.push displayGoal
    RequestM.checkCancelled
    return {
      display := (toJson ({ goals := displayGoals } : WidgetState)).compress
      codes
    }

end Iris.ProofMode.Widget
