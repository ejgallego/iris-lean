/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.Data.Json.FromToJson
public import Iris.ProofMode.ResourceStatus

namespace Iris.ProofMode.Widget

open Lean (FromJson ToJson)

/-- The two Iris proof-mode contexts shown by the widget. -/
public inductive ContextKind where
  | persistent
  | spatial
  deriving Repr, BEq, DecidableEq, ToJson, FromJson

/-- Display metadata for one proposition. `codeIndex` selects its original native
`CodeWithInfos` object in this reply; tagged code never round-trips through Lean JSON. -/
public structure RenderedTerm where
  id : String
  text : String
  typeText : String
  summary : String
  codeIndex : Nat := 0
  deriving Repr, BEq, ToJson, FromJson

/-- A single Iris hypothesis extracted from the typed proof-mode state. -/
public structure DisplayHypothesis where
  id : String
  kind : ContextKind
  name : String
  proposition : RenderedTerm
  deriving Repr, BEq, ToJson, FromJson

/-- Typed resource outcomes; the before-state row supplies the original proposition. -/
public structure DisplayResourceChange where
  id : String
  name : String
  status : GoalChanges.ResourceStatus
  after? : Option DisplayHypothesis := none
  deriving Repr, BEq, ToJson, FromJson

public structure DisplayBranchChange where
  id : String
  index : Nat := 0
  target? : Option RenderedTerm := none
  targetChanged : Bool := false
  resources : Array DisplayResourceChange := #[]
  unavailable? : Option String := none
  deriving Repr, BEq, ToJson, FromJson

/-- All outcomes of one before-goal, never a selected best-matching branch. -/
public structure DisplayComparison where
  tactic : String
  beforeId : String
  branches : Array DisplayBranchChange := #[]
  closed : Bool := false
  unavailable? : Option String := none
  deriving Repr, BEq, ToJson, FromJson

/--
The serializable projection of one typed `Iris.ProofMode.IrisGoal` recognized
by `Iris.ProofMode.parseIrisGoal?`. This is a display target, not an independent
source or textual reconstruction of the proof state.
-/
public structure DisplayGoal where
  id : String
  index : Nat
  title : String
  persistent : Array DisplayHypothesis
  spatial : Array DisplayHypothesis
  target : RenderedTerm
  comparison? : Option DisplayComparison := none
  deriving Repr, BEq, ToJson, FromJson

/-- One subordinate annotation; all terms refer to the current snapshot's native code. -/
public inductive AnnotationKind where
  | changed | gone | added | distributed | target
  deriving Repr, BEq

public def AnnotationKind.label : AnnotationKind → String
  | .changed => "changed" | .gone => "gone" | .added => "added"
  | .distributed => "distributed" | .target => "target"

public structure Annotation where
  kind : AnnotationKind
  lead : String
  term? : Option RenderedTerm := none
  branchId? : Option String := none
  deriving Repr, BEq

def glyph : ContextKind → String
  | .persistent => "□" | .spatial => "∗"

namespace DisplayComparison

/-- Compact source label only; never used for correspondence or tactic semantics. -/
public def label (comparison : DisplayComparison) : String :=
  ((comparison.tactic.trimAscii.toString.splitOn " ").head!).splitOn "\n" |>.head!

public def unavailable (comparison : DisplayComparison) : Option String :=
  comparison.unavailable?.orElse fun _ => comparison.branches.findSome? fun branch =>
    branch.unavailable?.map fun reason => s!"goal {branch.index + 1}: {reason}"

public def hypothesisAnnotations (comparison : DisplayComparison)
    (hypothesis : DisplayHypothesis) : Array Annotation := Id.run do
  if comparison.closed || comparison.unavailable.isSome then return #[]
  let outcomes := comparison.branches.filterMap fun branch =>
    (branch.resources.find? (·.id == hypothesis.id)).map (branch, ·)
  let surviving := outcomes.filter (·.2.after?.isSome)
  if surviving.isEmpty && !outcomes.isEmpty then
    return #[{ kind := .gone, lead := comparison.label ++ ": no longer in context" }]
  let split := comparison.branches.size > 1
  if outcomes.all (·.2.status == .preserved) then return #[]
  if split && surviving.all (·.2.status == .preserved) then
    return #[{ kind := .distributed, lead := comparison.label ++ ": " ++
      String.intercalate ", " (surviving.toList.map fun (branch, _) => s!"goal {branch.index + 1}") }]
  return surviving.filterMap fun (branch, change) => do
    let after ← change.after?
    if change.status == .preserved && !split then none else
      let destination := if split then s!"goal {branch.index + 1} " else ""
      let kind := if after.kind != hypothesis.kind then glyph after.kind ++ " " else ""
      some { kind := if change.status == .preserved then .distributed else .changed
             lead := comparison.label ++ ": " ++ destination ++ kind
             term? := if change.status == .preserved then none else some after.proposition
             branchId? := some branch.id }

/-- Append additions in each successor's display order, within their new context. -/
public def additions (comparison : DisplayComparison) (kind : ContextKind) :
    Array (DisplayHypothesis × Annotation) := Id.run do
  if comparison.closed || comparison.unavailable.isSome then return #[]
  return comparison.branches.flatMap fun branch =>
    branch.resources.filterMap fun change => do
      let after ← change.after?
      if change.status != .added || after.kind != kind then none else
        let destination := if comparison.branches.size > 1 then s!"goal {branch.index + 1} " else ""
        some (after, {
          kind := .added
          lead := comparison.label ++ " adds " ++ destination ++ glyph kind ++ after.name ++ ": "
          term? := some after.proposition, branchId? := some branch.id })

public def targetAnnotations (comparison : DisplayComparison) : Array Annotation := Id.run do
  if comparison.closed || comparison.unavailable.isSome then return #[]
  let split := comparison.branches.size > 1
  return comparison.branches.filterMap fun branch => do
    if !split && !branch.targetChanged then none else
      let target ← branch.target?
      some {
        kind := .target
        lead := comparison.label ++ ": " ++ (if split then s!"goal {branch.index + 1} ⊢ " else "")
        term? := some target, branchId? := some branch.id }

end DisplayComparison

def joinNames (names : List String) : String :=
  match names.reverse with
  | [] => ""
  | [name] => name
  | last :: rest => String.intercalate ", " rest.reverse ++ " and " ++ last

public def DisplayGoal.changeSummary (goal : DisplayGoal) (comparison : DisplayComparison) : String := Id.run do
  let projection := "before " ++ comparison.tactic ++ " · "
  if let some reason := comparison.unavailable then
    return projection ++ "comparison unavailable — " ++ reason
  if comparison.closed then return projection ++ "closes this goal"
  let existing := (goal.persistent ++ goal.spatial).filter fun h =>
    !(comparison.hypothesisAnnotations h).isEmpty
  let added := (comparison.additions .persistent ++ comparison.additions .spatial).map (·.1.name)
  let names := (existing.map (·.name)).toList ++ added.toList.eraseDups
  let targetChanged := !(comparison.targetAnnotations).isEmpty
  if names.isEmpty then
    return projection ++ if targetChanged then "only the goal changes" else "changes nothing in Iris"
  return projection ++ "changes " ++ joinNames (names ++ if targetChanged then ["the goal"] else [])

/-- Shared by the server payload default and the browser compatibility check. -/
public def widgetStateVersion : Nat := 6

/-- Versioned payload transported from the Lean server to the VIR component. -/
public structure WidgetState where
  version : Nat := widgetStateVersion
  goals : Array DisplayGoal
  deriving Repr, BEq, ToJson, FromJson

end Iris.ProofMode.Widget
