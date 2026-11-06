/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.GoalChanges
public meta import Iris.ProofMode.Display
public meta import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.Widget.Details
public meta import Iris.ProofMode.Widget.Diff
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
  let codeIndex ← modifyGet fun codes => (codes.size, codes.push code)
  let (invariant?, codes) ← Details.invariant? expr (← get)
  set codes
  return {
    id
    text := toString code.stripTags
    typeText := toString typeText
    summary
    codeIndex, invariant?
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
    (userName? : Option String) : ProjectionM DisplayGoal :=
  withOptions (pp.iris.quotations.set · false) do
  let (_, hypotheses) ← displayHypotheses irisGoal.hyps
  let hypotheses := hypotheses.reverse
  let title := match userName? with
    | some userName => "case " ++ userName
    | none => s!"goal {index + 1}"
  let (mask?, codes) ← Details.mask? irisGoal.goal (← get)
  set codes
  return {
    mask?
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
    (beforeDisplay : DisplayGoal) (codes : Array CodeWithInfos) : IO (DisplayComparison × Array CodeWithInfos) := do
  let before := comparison.before
  let mut codes := codes
  let mut branches := #[]
  for branch in comparison.branches do
    let mut hypotheses := #[]
    let mut target? := none
    if branch.unavailable?.isNone then
      if let some after := branch.after? then
        let (goal, nextCodes) ← after.context.runMetaM {} <| after.id.withContext do
          (toDisplayGoal after.iris after.id branch.index none).run codes
        hypotheses := goal.persistent ++ goal.spatial
        target? := some { goal.target with id := s!"iris-target-after-{before.id.name}-{branch.id.name}" }
        codes := nextCodes
        -- Pair by the already-validated IVarIds. Each side was independently
        -- printed at root in its saved context, including each target annotation.
        codes ← after.context.runMetaM {} <| after.id.withContext do
          let mut result := codes
          for change in branch.resources do
            if change.status != .changed then continue
            let some old := change.before? | continue
            let some new := change.after? | continue
            let some b := (beforeDisplay.persistent ++ beforeDisplay.spatial).find? (·.id == toString old.id.name)
              | continue
            let some a := hypotheses.find? (·.id == toString new.id.name) | continue
            result ← Diff.rendered old.proposition new.proposition b.proposition a.proposition result
          if branch.targetChanged then
            result ← Diff.rendered before.target after.target beforeDisplay.target goal.target result
          return result
    let resources ← branch.resources.mapM fun change => do
      let some resource := change.after?.orElse (fun _ => change.before?)
        | throw <| IO.userError "resource change has neither side"
      return {
        id := toString resource.id.name
        name := toString resource.name
        status := change.status
        after? := (hypotheses.find? (·.id == toString resource.id.name)).map fun h =>
          { h with proposition.id := s!"iris-change-{before.id.name}-{branch.id.name}-{resource.id.name}" }
      : DisplayResourceChange }
    -- Existing rows are annotated in the before-card's order. Additions follow the
    -- successor's display order, including its persistent/spatial grouping.
    let ordered := hypotheses.filterMap fun h => resources.find? (·.id == h.id)
    let resources := ordered ++ resources.filter (·.after?.isNone)
    branches := branches.push {
      id := toString branch.id.name, index := branch.index, target?, resources
      leanGoal := branch.after?.isNone && branch.unavailable?.isNone
      targetChanged := branch.targetChanged, unavailable? := branch.unavailable? }
  return ({
    tactic, beforeId := toString before.id.name, branches
    closed := comparison.closed, quiet := comparison.quiet, unavailable? := comparison.unavailable?
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
      let inTactic := !result.hangingBy &&
        ti.stx.getRange?.any (fun range => range.start ≤ pos && pos < range.stop)
      let comparisons ← if inTactic then GoalChanges.compareTactic result.ctxInfo ti else pure #[]
      if !comparisons.isEmpty then
        -- An annotation always reads forward from its own saved before-state,
        -- including at positions where the standard infoview selects the after side.
        for comparison in comparisons do
          RequestM.checkCancelled
          let before := comparison.before
          let (goal, nextCodes) ← before.context.runMetaM {} <| before.id.withContext do
            let userName := (← before.id.getDecl).userName
            (toDisplayGoal before.iris before.id displayGoals.size
              (if userName.isAnonymous then none else some (toString userName))).run codes
          codes := nextCodes
          let label := (ti.stx.getRange?.map fun range =>
            String.Pos.Raw.extract doc.meta.text.source range.start range.stop).getD (toString ti.stx.getKind)
          let (display, nextCodes) ← displayComparison label comparison goal codes
          codes := nextCodes
          displayGoals := displayGoals.push { goal with comparison? := some display }
      else
        let ci := { result.ctxInfo with mctx := if result.useAfter then ti.mctxAfter else ti.mctxBefore }
        let goalIds := if result.useAfter then ti.goalsAfter else ti.goalsBefore
        let goals ← ci.runMetaM {} <| goalIds.toArray.mapM Lean.Widget.goalToInteractive
        for goal in goals do
          RequestM.checkCancelled
          let (displayGoal?, nextCodes) ← displayIrisGoalAt? goal displayGoals.size codes
          codes := nextCodes
          if let some displayGoal := displayGoal? then
            displayGoals := displayGoals.push displayGoal
    RequestM.checkCancelled
    return { display := (toJson ({ goals := displayGoals } : WidgetState)).compress, codes }

end Iris.ProofMode.Widget
