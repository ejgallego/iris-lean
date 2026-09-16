/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.Data.Json.FromToJson
public import Lean.Widget.TaggedText

namespace Iris.ProofMode.Widget

open Lean (FromJson ToJson)
open Lean.Widget (TaggedText)

/-- The two Iris proof-mode contexts shown by the widget. -/
public inductive ContextKind where
  | persistent
  | spatial
  deriving Repr, BEq, DecidableEq, ToJson, FromJson

/--
A proposition rendered by Lean on the server. Indices in `code` address saved
contextual expressions in the owning snapshot, never global handles or display IDs.
-/
public structure RenderedTerm where
  id : String
  text : String
  typeText : String
  summary : String
  code : TaggedText Nat := .text text
  deriving Repr, BEq, ToJson, FromJson

/-- Renderable leaves inherit their innermost semantic tag; buttons never nest. -/
public structure TermPart where
  text : String
  reference : Option Nat
  deriving Repr, BEq

public partial def termParts (code : TaggedText Nat)
    (reference : Option Nat := none) : Array TermPart :=
  match code with
  | .text text => if text.isEmpty then #[] else #[{ text, reference }]
  | .append children => children.flatMap (termParts · reference)
  | .tag index body => termParts body (some index)

/-- A single Iris hypothesis extracted from the typed proof-mode state. -/
public structure DisplayHypothesis where
  id : String
  kind : ContextKind
  name : String
  proposition : RenderedTerm
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
  deriving Repr, BEq, ToJson, FromJson

/-- Versioned payload transported from the Lean server to the VIR component. -/
public structure WidgetState where
  version : Nat := 3
  goals : Array DisplayGoal
  deriving Repr, BEq, ToJson, FromJson

end Iris.ProofMode.Widget
