/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public meta import Iris.ProofMode.ResourceStatus
public meta import Iris.ProofMode.Expr
public meta import Lean.Elab.InfoTree.Main

namespace Iris.ProofMode.GoalChanges

public meta section

open Lean Meta Elab Qq Iris.BI

/-- A resource in one saved tactic state. Names are labels, never correspondence keys. -/
structure Resource where
  id : IVarId
  name : Name
  persistent : Bool
  proposition : Expr

structure SavedGoal where
  id : MVarId
  context : ContextInfo
  iris : IrisGoal
  resources : Array Resource
  bindings : Array (FVarId × Expr × Option Expr)

private partial def collect {u prop bi e} (hyps : @Hyps u prop bi e) : MetaM (Array Resource) := do
  match hyps with
  | .emp _ => return #[]
  | .sep _ _ _ _ lhs rhs => return (← collect lhs) ++ (← collect rhs)
  | .hyp _ name id persistent proposition _ =>
    return #[{ id, name, persistent := isTrue persistent, proposition := ← instantiateMVars proposition }]

/-- Decode in the side's own saved metavariable and local contexts. -/
def readGoal? (context : ContextInfo) (id : MVarId) : IO (Option SavedGoal) :=
  context.runMetaM {} <| id.withContext do
    let some iris := parseIrisGoal? (← instantiateMVars (← id.getType)) | return none
    let bindings ← (← getLCtx).getFVarIds.mapM fun fvar => do
      let decl ← fvar.getDecl
      return (fvar, ← instantiateMVars decl.type, ← decl.value?.mapM instantiateMVars)
    return some { id, context, iris, resources := ← collect iris.hyps, bindings }

structure ResourceChange where
  status : ResourceStatus
  before? : Option Resource
  after? : Option Resource

structure Branch where
  id : MVarId
  after? : Option SavedGoal
  resources : Array ResourceChange := #[]
  unavailable? : Option String := none

structure Comparison where
  before : SavedGoal
  branches : Array Branch := #[]
  closed : Bool := false
  unavailable? : Option String := none

private def uniqueIds (resources : Array Resource) : Bool := Id.run do
  let mut seen := #[]
  for resource in resources do
    if seen.contains resource.id then return false
    seen := seen.push resource.id
  return true

/-- Compare only within one tactic's identity domain. No pretty printing or unification. -/
def compareResources (before after : SavedGoal) : Except String (Array ResourceChange) := do
  unless uniqueIds before.resources && uniqueIds after.resources do
    throw "duplicate resource identities"
  unless before.iris.prop == after.iris.prop && before.iris.bi == after.iris.bi do
    throw "the proposition domain changed"
  -- An identical Expr is meaningful only while its shared local bindings still mean
  -- the same thing. Refuse comparison across rewritten local declarations.
  for (id, type, value) in before.bindings do
    if let some (_, newType, newValue) := after.bindings.find? (·.1 == id) then
      unless type == newType && value == newValue do
        throw "a shared local declaration changed"
  let mut changes := #[]
  for resource in after.resources do
    let old? := before.resources.find? (·.id == resource.id)
    let status := match old? with
      | none => .added
      | some old => if old.proposition == resource.proposition && old.persistent == resource.persistent
          then .preserved else .changed
    changes := changes.push { status, before? := old?, after? := some resource }
  for resource in before.resources do
    unless after.resources.any (·.id == resource.id) do
      changes := changes.push { status := .removed, before? := some resource, after? := none }
  return changes

/--
Use the same assignment reachability as Lean's `diffInteractiveGoals`, in `mctxAfter`.
Unlike its single-match display heuristic, retain every descendant and reject ambiguous
parents. A solved goal is closed; it does not imply that all its resources were consumed.
The caller must supply a single `TacticInfo`, never states from separate elaborations.
-/
def compareTactic (context : ContextInfo) (tactic : TacticInfo) : IO (Array Comparison) := do
  let beforeContext := { context with mctx := tactic.mctxBefore }
  let afterContext := { context with mctx := tactic.mctxAfter }
  let beforeIds := tactic.goalsBefore.toArray
  let afterIds := tactic.goalsAfter.toArray
  let descendants ← afterContext.runMetaM {} <| beforeIds.mapM fun id => getMVars (.mvar id)
  let parents := afterIds.map fun id => beforeIds.zipIdx.filterMap fun (parent, index) =>
    if parent == id || descendants[index]!.contains id then some parent else none
  let unpaired := parents.any (·.isEmpty)
  let mut result := #[]
  for (id, index) in beforeIds.zipIdx do
    let some before ← readGoal? beforeContext id | continue
    let children := afterIds.zipIdx.filterMap fun (child, index) =>
      if parents[index]!.contains id then some child else none
    if unpaired || parents.any (fun ps => ps.contains id && ps.size != 1) then
      result := result.push { before, unavailable? := some "goal correspondence is ambiguous" }
    else if children.isEmpty then
      if descendants[index]!.isEmpty then
        result := result.push { before, closed := true }
      else
        result := result.push { before, unavailable? := some "open descendants are absent from the tactic's result" }
    else
      let branches ← children.mapM fun child => do
        let after? ← readGoal? afterContext child
        let some after := after?
          | return { id := child, after?, unavailable? := some "the resulting goal is not in Iris proof mode" : Branch }
        match compareResources before after with
        | .ok resources => return { id := child, after?, resources : Branch }
        | .error reason => return { id := child, after?, unavailable? := some reason : Branch }
      result := result.push { before, branches }
  return result

end
end Iris.ProofMode.GoalChanges
