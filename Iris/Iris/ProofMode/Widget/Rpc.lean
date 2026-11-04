/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.GoalChanges
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

private def displayComparison (tactic : String) (comparison : GoalChanges.Comparison)
    (codes : Array CodeWithInfos) : IO (DisplayComparison × Array CodeWithInfos) := do
  let before := comparison.before
  let oldText ← before.context.runMetaM {} <| before.id.withContext do
    before.resources.mapM fun resource => do
      return (resource.id, toString (← ppExprTagged resource.proposition delabIProp).stripTags)
  let mut codes := codes
  let mut branches := #[]
  for branch in comparison.branches do
    let mut hypotheses := #[]
    if let some after := branch.after? then
      let ((_, values), nextCodes) ← after.context.runMetaM {} <| after.id.withContext do
        (displayHypotheses after.iris.hyps).run codes
      hypotheses := values
      codes := nextCodes
    let resources ← branch.resources.mapM fun change => do
      let some resource := change.after?.orElse (fun _ => change.before?) | throw <| IO.userError "resource change has neither side"
      return {
        id := toString resource.id.name
        name := toString resource.name
        status := change.status
        after? := (hypotheses.find? (·.id == toString resource.id.name)).map fun h =>
          { h.proposition with id := s!"iris-change-{before.id.name}-{branch.id.name}-{resource.id.name}" }
        before? := (oldText.find? (·.1 == resource.id)).map (·.2)
      : DisplayResourceChange }
    branches := branches.push { id := toString branch.id.name, resources, unavailable? := branch.unavailable? }
  return ({
    tactic, beforeId := toString before.id.name, branches
    closed := comparison.closed, unavailable? := comparison.unavailable?
  }, codes)

/-- Use Lean's goal selection once for both the current view and the comparison.
Trailing whitespace retains the ordinary view but is not a tactic-under-cursor comparison. -/
@[server_rpc_method]
def state (params : StateRequest) : RequestM (RequestTask SnapshotReply) := do
  let doc ← RequestM.readDoc
  let pos := doc.meta.text.lspPosToUtf8Pos params.pos
  RequestM.mapTaskCostly (FileWorker.findGoalsAt? doc pos) fun results? => do
    RequestM.checkCancelled
    let mut displayGoals := #[]
    let mut codes := #[]
    for result in results?.getD [] do
      let ti := result.tacticInfo
      let ci := { result.ctxInfo with mctx := if result.useAfter then ti.mctxAfter else ti.mctxBefore }
      let goalIds := if result.useAfter then ti.goalsAfter else ti.goalsBefore
      let goals ← ci.runMetaM {} <| goalIds.toArray.mapM Lean.Widget.goalToInteractive
      let start := displayGoals.size
      for goal in goals do
        RequestM.checkCancelled
        let (displayGoal?, nextCodes) ← displayIrisGoalAt? goal displayGoals.size codes
        codes := nextCodes
        if let some displayGoal := displayGoal? then
          displayGoals := displayGoals.push displayGoal
      if !result.hangingBy && ti.stx.getRange?.any (fun range => range.start ≤ pos && pos < range.stop) then
        let comparisons ← GoalChanges.compareTactic result.ctxInfo ti
        for comparison in comparisons do
          RequestM.checkCancelled
          -- One before-goal owns ALL its outcomes. On the after side, attach the group
          -- once to its first visible descendant, without discarding the other branches.
          let owner? := (displayGoals.toList.drop start).find? fun goal =>
            goal.id == toString comparison.before.id.name ||
              comparison.branches.any (fun branch => goal.id == toString branch.id.name)
          let ownerId ← if let some owner := owner? then pure owner.id else do
            -- In particular, preserve a closed goal as a closed card, not a list of removals.
            let before := comparison.before
            let (goal, nextCodes) ← before.context.runMetaM {} <| before.id.withContext do
              (toDisplayGoal before.iris before.id displayGoals.size none).run codes
            codes := nextCodes
            displayGoals := displayGoals.push goal
            pure goal.id
          let label := (ti.stx.getRange?.map fun range =>
            String.Pos.Raw.extract doc.meta.text.source range.start range.stop).getD (toString ti.stx.getKind)
          let (display, nextCodes) ← displayComparison label comparison codes
          codes := nextCodes
          displayGoals := displayGoals.map fun goal =>
            if goal.id == ownerId then { goal with comparison? := some display } else goal
    RequestM.checkCancelled
    return { display := (toJson ({ goals := displayGoals } : WidgetState)).compress, codes }

end Iris.ProofMode.Widget
