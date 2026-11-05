/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.HeapLang.ProofMode
import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.Widget.Rpc

namespace IrisTest.ProofMode.WidgetDetails
open Iris HeapLang Lean Meta Elab Tactic Iris.ProofMode Iris.ProofMode.Widget

elab "check_details" kind:str : tactic => do
  let id ← getMainGoal
  id.withContext do
    let some iris := parseIrisGoal? (← instantiateMVars (← id.getType)) | throwError "not Iris"
    let (goal, codes) ← (toDisplayGoal iris id 0 none).run #[]
    unless goal.target.text == (← Lean.Widget.ppExprTagged iris.goal delabIProp).stripTags do
      throwError "canonical target changed"
    let verify (part : NativePart) := do
      unless codes[part.codeIndex]!.stripTags == part.text do throwError "native fragment mismatch"
    if kind.getString == "inv" then
      let some inv := goal.spatial[0]?.bind (·.proposition.invariant?) | throwError "missing fold"
      verify inv.name; verify inv.body
      unless goal.mask?.isNone do throwError "invariant is not an outer mask"
      let (fallback, original) ← Details.invariant? iris.goal codes fun e iprop =>
        if iprop then throwError "body print failed" else Details.printPart e iprop
      unless fallback.isNone && original.size == codes.size do throwError "partial invariant codes leaked"
    else if kind.getString == "plain" then
      unless goal.mask?.isNone && goal.target.invariant?.isNone && codes.size == 2 do
        throwError "unknown shape did not fall back"
    else
      let some mask := goal.mask? | throwError "missing outer mask"
      verify mask
      unless mask.text == "E" && goal.target.invariant?.isNone do throwError "wrong outer mask"
      let (fallback, original) ← Details.mask? iris.goal codes (fun _ _ => throwError "mask print failed")
      unless fallback.isNone && original.size == codes.size do throwError "mask failure did not roll back"

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF]
variable {s : Stuckness} {E : CoPset}
example {l : Loc} {v : Val} : l ↦ some v ⊢ WP hl(!v(#l)) @ s ; E {{ r, ⌜r = v⌝ }} := by
  iintro Hl
  check_details "wp"
  wp_load
  imodintro
  itrivial
example (P : IProp GF) : P ⊢ |={E}=> P := by
  iintro HP
  check_details "fupd"
  imodintro
  iexact HP
example (N : Namespace) (P : IProp GF) : inv N P ⊢ inv N P := by
  iintro Hinv
  check_details "inv"
  iexact Hinv
example (P : IProp GF) : P ⊢ P := by
  iintro HP
  check_details "plain"
  iexact HP

-- Surviving IVarIds win over positional fallback, even when rows reorder.
def slots := ({} : PresentationKeys).update #["a", "b"]
#guard (slots.update #["b", "a"]).keys == #[1, 0]
#guard (slots.update #["fresh", "a"]).keys == #[2, 0]
#guard (slots.update #["fresh-a", "fresh-b"]).keys == #[0, 1]
#guard (slots.update #["b"]).keys == #[1]
#guard (slots.update #["a", "b"]).next == 2

end IrisTest.ProofMode.WidgetDetails
