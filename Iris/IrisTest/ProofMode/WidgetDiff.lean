/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.HeapLang.ProofMode
import Iris.ProofMode
public meta import Iris.ProofMode
import Iris.HeapLang.Lib.SpinLock
public meta import Iris.ProofMode.GoalChanges
public meta import Iris.ProofMode.Widget.Diff

namespace IrisTest.ProofMode.WidgetDiff
open Iris HeapLang Lean Meta Elab Tactic Iris.ProofMode

private meta partial def markedText (code : Lean.Widget.CodeWithInfos) (active := false) : String :=
  match code with
  | .text text => if active then text else ""
  | .append children => String.join (children.toList.map (markedText · active))
  | .tag info body => markedText body (active || info.diffStatus?.isSome)

/-- Exact marked text, not merely the existence of some arbitrary root tag. -/
elab "check_expr_diff " before:term " against " after:term
    " marks " old:str " and " new:str : tactic => withMainContext do
  withOptions (pp.iris.quotations.set · false) do
    let b ← Term.elabTerm before none
    let a ← Term.elabTerm after (some (← inferType b))
    let b ← instantiateMVars b
    let a ← instantiateMVars a
    let bc ← Lean.Widget.ppExprTagged b delabIProp
    let ac ← Lean.Widget.ppExprTagged a delabIProp
    let (bd, ad) ← Widget.Diff.decorate b a bc ac
    unless bd.stripTags == bc.stripTags && ad.stripTags == ac.stripTags do
      throwError "diff changed the printed term"
    unless markedText bd == old.getString && markedText ad == new.getString do
      throwError "marked before '{markedText bd}', after '{markedText ad}'; expected '{old.getString}', '{new.getString}'"
    bd.forM fun info _ => do
      if let some tag := info.diffStatus? then
        unless (match tag with | .willChange | .willDelete | .willInsert => true | _ => false) do
          throwError "wrong before-side tag"
    ad.forM fun info _ => do
      if let some tag := info.diffStatus? then
        unless (match tag with | .wasChanged | .wasDeleted | .wasInserted => true | _ => false) do
          throwError "wrong after-side tag"

example [BI PROP] (P : PROP) : True := by
  check_expr_diff P against P marks "" and ""
  check_expr_diff iprop(▷ P) against P marks "▷ " and ""
  -- A hidden surviving argument must not invent a text split.
  run_tac do
    let a := mkNatLit 1
    let b ← mkAppM ``Nat.succ #[a]
    let repeated ← mkAppM ``Nat.add #[a, a]
    unless (Widget.Diff.strippedArgument? repeated a).isNone do
      throwError "ambiguous surviving argument"
    let (before, after) ← Widget.Diff.decorate b a (.text "opaque") (.text "Nat")
    unless before.stripTags == "opaque" && after.stripTags == "Nat" do throwError "fallback changed text"
  trivial

section Heap

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF]
variable {s : Stuckness} {E : CoPset}

example (P : IProp GF) : True := by
  check_expr_diff iprop(|={E}=> P) against P marks "|={E}=> " and ""
  -- These stripped applications are outside the specialized later/fupd printer.
  -- Their existential body's missing root tag must not trigger that printer.
  check_expr_diff iprop(|==> ∃ n : Nat, ⌜n = 0⌝ ∗ P)
    against iprop(∃ n : Nat, ⌜n = 0⌝ ∗ P)
    marks "|==> ∃ n, ⌜n = 0⌝ ∗ P" and "n"
  check_expr_diff iprop(P ∨ ∃ n : Nat, ⌜n = 0⌝ ∗ P)
    against iprop(∃ n : Nat, ⌜n = 0⌝ ∗ P)
    marks "P ∨ ∃ n, ⌜n = 0⌝ ∗ P" and "n"
  trivial

example (l : Loc) (b : Bool) (v v' : Val) : True := by
  check_expr_diff iprop(l ↦ some hl_val(#b)) against iprop(l ↦ some hl_val(#false))
    marks "b" and "false"
  check_expr_diff iprop(l ↦ some v) against iprop(l ↦ some v') marks "v" and "v'"
  check_expr_diff iprop(l ↦ some hl_val(#0)) against iprop(l ↦ some hl_val(#21))
    marks "0" and "21"
  check_expr_diff iprop(l ↦ some hl_val(#0)) against iprop(l ↦ some hl_val(#2))
    marks "0" and "2"
  trivial

example (P Q : Nat → IProp GF) (m n : Nat) : True := by
  check_expr_diff (P 2) against (P 1) marks "2" and "1"
  check_expr_diff (Q 2) against (Q 1) marks "2" and "1"
  check_expr_diff iprop(▷^[m + n + 6] |={E}=> P 0)
    against iprop(▷^[m + n + 3] |={E}=> P 0) marks "6" and "3"
  check_expr_diff iprop(▷^[m + n + 3] |={E}=> P 0)
    against iprop(▷^[m + n + 1] |={E}=> P 0) marks "3" and "1"
  check_expr_diff iprop(£ (m + n + 6) : IProp GF) against iprop(£ (m + n + 3) : IProp GF)
    marks "6" and "3"
  check_expr_diff iprop(£ (m + n + 3) : IProp GF) against iprop(£ (m + n + 1) : IProp GF)
    marks "3" and "1"
  trivial

example (l : Loc) (v : Val) (Φ : Val → IProp GF) : True := by
  check_expr_diff (WP hl(v(#l) ← &v; !v(#l)) @ s ; E {{ Φ }})
    against (WP hl(!v(#l)) @ s ; E {{ Φ }})
    marks "hl(#l ← v(&v); !#l)" and "hl(!#l)"
  trivial


end Heap

elab "check_tactic_diff " tactic:tactic : tactic => do
  let before ← getMCtx
  let goalsBefore ← getGoals
  evalTactic tactic
  let context : ContextInfo := { (← CommandContextInfo.save) with }
  let info : TacticInfo := {
    elaborator := `check_tactic_diff, stx := tactic
    mctxBefore := before, goalsBefore
    mctxAfter := ← getMCtx, goalsAfter := ← getGoals }
  let comparisons ← GoalChanges.compareTactic context info
  let mut checked := false
  for comparison in comparisons do
    for branch in comparison.branches do
      let some after := branch.after? | throwError "missing after state"
      for resource in branch.resources do
        let some old := resource.before? | continue
        let some new := resource.after? | continue
        unless old.name == `Hcond do continue
        checked := true
        let b ← comparison.before.context.runMetaM {} <| comparison.before.id.withContext do
          withOptions (pp.iris.quotations.set · false) <| Lean.Widget.ppExprTagged old.proposition delabIProp
        let a ← after.context.runMetaM {} <| after.id.withContext do
          withOptions (pp.iris.quotations.set · false) <| Lean.Widget.ppExprTagged new.proposition delabIProp
        let (bd, ad) ← after.context.runMetaM {} <| after.id.withContext do
          Widget.Diff.decorate old.proposition new.proposition b a
        unless (markedText bd).trimAscii.toString == "▷" && (markedText ad).isEmpty do
          throwError "Hcond: before '{markedText bd}', after '{markedText ad}'"
        unless bd.stripTags == b.stripTags && ad.stripTags == a.stripTags do
          throwError "saved-context wrapper repair changed text"
        -- A previous branch can already have marked this before term. The local
        -- printing repair must not erase that branch's diff.
        let (combined, _) ← after.context.runMetaM {} <| after.id.withContext do
          let prior ← Widget.Vendor.Lean435.addDiffTags false
            (Widget.Vendor.Lean435.ExprDiff.withChangePos .root .root) b
          Widget.Diff.decorate old.proposition new.proposition prior a
        unless markedText combined == b.stripTags do throwError "previous branch's diff lost"
  unless checked do throwError "Hcond comparison missing"

elab "check_frame_diff " tactic:tactic : tactic => do
  let before ← getMCtx
  let goalsBefore ← getGoals
  evalTactic tactic
  let context : ContextInfo := { (← CommandContextInfo.save) with }
  let info : TacticInfo := {
    elaborator := `check_frame_diff, stx := tactic
    mctxBefore := before, goalsBefore
    mctxAfter := ← getMCtx, goalsAfter := ← getGoals }
  let comparisons ← GoalChanges.compareTactic context info
  unless comparisons.size == 1 && comparisons.all (·.branches.size == 1) do
    throwError "expected one frame comparison"
  for comparison in comparisons do
    for branch in comparison.branches do
      let some after := branch.after? | throwError "missing after state"
      let b ← comparison.before.context.runMetaM {} <| comparison.before.id.withContext do
        Lean.Widget.ppExprTagged comparison.before.target delabIProp
      let a ← after.context.runMetaM {} <| after.id.withContext do
        Lean.Widget.ppExprTagged after.target delabIProp
      let (bd, ad) ← after.context.runMetaM {} <| after.id.withContext do
        Widget.Diff.decorate comparison.before.target after.target b a
      -- The existential/if roots lost their printer tags. Their printed later
      -- encloses the change; the unchanged continuation and hidden instances do not.
      unless markedText bd == "(▷ ∃ b, l ↦ some #b ∗ if b = true then True else locked γ ∗ R)" &&
          markedText ad == "(▷ if false = true then True else locked γ ∗ R)" do
        throwError "frame target diff: '{markedText bd}', '{markedText ad}'"
      unless bd.stripTags == b.stripTags && ad.stripTags == a.stripTags do
        throwError "frame target diff changed text"

section Lock

open HeapLang HeapLang.SpinLock

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF] [SpinLockG GF]
local bi (IProp GF)

set_option pp.iris.quotations false in
/--
The complete `SpinLock.release_spec` proof, with pause points around the store
inside the opened invariant. `Hinv` is persistent; `Hl` and `HR` supply the
ghost token and protected resource needed to restore the unlocked invariant.
-/
example (γ : GName) (lk : Val) (R : IProp GF) :
    {{ isLock γ lk R ∗ locked γ ∗ R }} hl(&release &lk)
    {{ RET hl_val(#()); True }} := by
  iintro %Φ ⟨#Hlock, Hl, HR⟩ Hcont
  wp_rec
  unfold isLock
  icases Hlock with ⟨%l, %Heq, #Hinv⟩
  subst Heq
  iinv Hinv with G1
  unfold lockInv
  icases G1 with ⟨%b, Hpt, Hcond⟩
  check_tactic_diff wp_store
  imodintro
  check_frame_diff iframe Hpt
  simp only [Bool.false_eq_true, ↓reduceIte]; iframe
  iapply Hcont; itrivial

end Lock

end IrisTest.ProofMode.WidgetDiff
