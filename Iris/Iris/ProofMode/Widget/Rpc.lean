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

/-- Only this adapter consumes delaborator info nodes; the wire never exposes them. -/
structure SavedTerm where
  ctx : Elab.ContextInfo
  lctx : LocalContext
  expr : Expr

/-- A retained elaboration snapshot, owned by Lean's native RPC session. -/
structure Snapshot where
  references : Array SavedTerm
  deriving TypeName

/-- Plain display data and its opaque semantic owner travel separately. -/
structure SnapshotReply where
  display : String
  snapshot : WithRpcRef Snapshot
  deriving RpcEncodable

abbrev ProjectionM := StateT (Array SavedTerm) MetaM

private partial def retainCode (code : Lean.Widget.CodeWithInfos) :
    ProjectionM (Lean.Widget.TaggedText Nat) := do
  match code with
  | .text text => return .text text
  | .append children => return .append (← children.mapM retainCode)
  | .tag tag body =>
    let info := tag.info.val
    let term? := match info.info with
      | .ofTermInfo term => some term
      | .ofDelabTermInfo term => some term.toTermInfo
      | _ => none
    match term? with
    | some term =>
      let index ← modifyGet fun refs =>
        (refs.size, refs.push { ctx := info.ctx, lctx := term.lctx, expr := term.expr })
      return .tag index (← retainCode body)
    | none => retainCode body

private def renderedIProp (id summary : String) (expr : Expr) : ProjectionM RenderedTerm := do
  let code ← Lean.Widget.ppExprTagged expr Iris.ProofMode.delabIProp
  let type ← instantiateMVars (← inferType expr)
  let typeText ← ppExpr type
  return {
    id
    text := toString code.stripTags
    typeText := toString typeText
    summary
    code := ← retainCode code
  }

private partial def displayHypotheses
    {u : Level} {prop : Q(Type u)} {bi : Q(BI $prop)} {e : Q($prop)}
    (hyps : Iris.ProofMode.Hyps bi e)
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
    (goal : Lean.Widget.InteractiveGoal) (index : Nat) (refs : Array SavedTerm) :
    IO (Option DisplayGoal × Array SavedTerm) :=
  goal.ctx.val.runMetaM {} do
    goal.mvarId.withContext do
      let target ← instantiateMVars (← goal.mvarId.getType)
      let some irisGoal := Iris.ProofMode.parseIrisGoal? target
        | return (none, refs)
      let (display, refs) ← (toDisplayGoal irisGoal goal.mvarId index goal.userName?).run refs
      return (some display, refs)

/-- Inspect the actual expression under its saved binder and metavariable context. -/
def inspectSavedTerm (term : SavedTerm) : IO String :=
  term.ctx.runMetaM term.lctx do
    let expr ← instantiateMVars term.expr
    let type ← instantiateMVars (← inferType expr)
    return s!"{← ppExpr expr} : {← ppExpr type}"

structure InspectRequest where
  snapshot : WithRpcRef Snapshot
  reference : Nat
  deriving RpcEncodable

@[server_rpc_method]
def inspect (params : InspectRequest) : RequestM (RequestTask String) :=
  RequestM.asTask do
    let some term := params.snapshot.val.references[params.reference]?
      | throw (RequestError.invalidParams "No such expression in this Iris snapshot")
    inspectSavedTerm term

/-- Return typed Iris proof-mode state for the goals at the requested cursor. -/
@[server_rpc_method]
def state (params : StateRequest) : RequestM (RequestTask SnapshotReply) := do
  let goalsTask ← Server.FileWorker.getInteractiveGoals {
    textDocument := { uri := (← RequestM.readDoc).meta.uri }
    position := params.pos
  }
  RequestM.mapRequestTaskCostly goalsTask fun goals? => do
    let mut displayGoals := #[]
    let mut references := #[]
    if let some goals := goals? then
      for (goal, index) in goals.goals.zipIdx do
        let (displayGoal?, refs) ← displayIrisGoalAt? goal index references
        references := refs
        if let some displayGoal := displayGoal? then
          displayGoals := displayGoals.push displayGoal
    return {
      display := (toJson ({ goals := displayGoals } : WidgetState)).compress
      snapshot := ← WithRpcRef.mk { references }
    }

end Iris.ProofMode.Widget
