/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.Data.Json.FromToJson

namespace Iris.ProofMode.Widget

/-- The two Iris proof-mode contexts shown by the widget. -/
public inductive ContextKind where
  | persistent
  | spatial
  deriving Repr, BEq, DecidableEq, Lean.ToJson, Lean.FromJson

/--
A proposition rendered by Lean on the server. The wrapper leaves room for
transporting tagged spans without changing the goal model or its React
components. The reference metadata lets VIR resolve a selected term at the
current editor position.
-/
public structure RenderedTerm where
  id : String
  text : String
  typeText : String
  summary : String
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

/-- A single Iris hypothesis extracted from the typed proof-mode state. -/
public structure DisplayHypothesis where
  id : String
  kind : ContextKind
  name : String
  proposition : RenderedTerm
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

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
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

/-- Versioned payload transported from the Lean server to the VIR component. -/
public structure WidgetState where
  version : Nat := 2
  goals : Array DisplayGoal
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

end Iris.ProofMode.Widget
