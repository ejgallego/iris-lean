/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.Data.Json.FromToJson

namespace Iris.ProofMode.GoalChanges

/-- Syntactic changes to instantiated propositions, not logical equivalence or usage. -/
public inductive ResourceStatus where
  | changed | preserved | added | removed
  deriving Repr, BEq, Lean.ToJson, Lean.FromJson

end Iris.ProofMode.GoalChanges
