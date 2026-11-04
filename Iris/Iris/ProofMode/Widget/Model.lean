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

/-- New-side native terms; old-side text was printed in its own saved context. -/
public structure DisplayResourceChange where
  id : String
  name : String
  status : GoalChanges.ResourceStatus
  after? : Option RenderedTerm := none
  before? : Option String := none
  deriving Repr, BEq, ToJson, FromJson

public structure DisplayBranchChange where
  id : String
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

/-- Shared by the server payload default and the browser compatibility check. -/
public def widgetStateVersion : Nat := 5

/-- Versioned payload transported from the Lean server to the VIR component. -/
public structure WidgetState where
  version : Nat := widgetStateVersion
  goals : Array DisplayGoal
  deriving Repr, BEq, ToJson, FromJson

end Iris.ProofMode.Widget
