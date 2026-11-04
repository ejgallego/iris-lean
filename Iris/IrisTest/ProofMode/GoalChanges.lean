/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.HeapLang.ProofMode
import Iris.HeapLang.Lib.SpinLock
public meta import Iris.ProofMode.GoalChanges

/-! Widget-independent resource correspondence checks on complete HeapLang proofs. -/
namespace IrisTest.ProofMode.GoalChanges
open Iris
open Lean Elab Tactic
open Iris.ProofMode.GoalChanges

elab "check_changes" expected:str " in " tactic:tactic : tactic => do
  let before ← getMCtx
  let goalsBefore ← getGoals
  evalTactic tactic
  let context : ContextInfo := { (← CommandContextInfo.save) with }
  let info : TacticInfo := {
    elaborator := `check_changes, stx := tactic
    mctxBefore := before, goalsBefore
    mctxAfter := ← getMCtx, goalsAfter := ← getGoals
  }
  let comparisons ← compareTactic context info
  unless comparisons.size == 1 do throwError "expected one before-goal, got {comparisons.size}"
  let mut summaries : Array String := #[]
  for comparison in comparisons do
    if let some reason := comparison.unavailable? then throwError "unavailable: {reason}"
    if comparison.closed then
      unless comparison.branches.isEmpty do throwError "closed goal has resource outcomes"
      summaries := summaries.push "closed"
    for branch in comparison.branches do
      if let some reason := branch.unavailable? then throwError "unavailable: {reason}"
      let rows ← branch.resources.mapM fun change => do
        let some resource := change.after?.orElse (fun _ => change.before?)
          | throwError "missing resource"
        -- Names label the assertion; the implementation pairs only by IVarId.
        let status := match change.status with
          | .changed => "changed" | .preserved => "preserved"
          | .added => "added" | .removed => "removed"
        if change.status == .changed || change.status == .preserved then
          unless change.before?.map (·.id) == change.after?.map (·.id) do
            throwError "paired resource identity changed"
        return s!"{resource.name}:{status}"
      summaries := summaries.push (String.intercalate " " rows.toList)
  let actual := String.intercalate " | " summaries.toList
  unless actual == expected.getString do throwError "expected {expected.getString}, got {actual}"

example [BI PROP] (P Q : PROP) : ⊢ P -∗ Q -∗ P ∗ Q := by
  istart
  check_changes "HP:added HQ:added" in iintro HP HQ
  check_changes "HP:preserved HQ:removed | HQ:preserved HP:removed" in isplitr [HQ]
  · check_changes "closed" in iexact HP
  · iexact HQ


/-- Refuse ambiguous identity; changing a printed name cannot establish correspondence. -/
example [BI PROP] (P : PROP) : P ⊢ P := by
  iintro HP
  run_tac do
    let id ← getMainGoal
    let context : ContextInfo := { (← CommandContextInfo.save) with }
    let some saved ← readGoal? context id | throwError "expected Iris goal"
    let some resource := saved.resources[0]? | throwError "expected one resource"
    let renamed := { saved with resources := #[{ resource with name := `renamed }] }
    let .ok changes := compareResources saved renamed | throwError "rename should compare"
    unless changes.map (·.status) == #[.preserved] do throwError "names affected identity"
    let fresh := { saved with resources := #[{ resource with id.name := `different }] }
    let .ok changes := compareResources saved fresh | throwError "fresh identity should compare"
    unless changes.map (·.status) == #[.added, .removed] do throwError "text paired different identities"
    let duplicate := { saved with resources := #[resource, resource] }
    unless (compareResources saved duplicate).toOption.isNone do throwError "duplicate identity accepted"
    let changedBinding := { saved with bindings := saved.bindings.map fun (id, type, _) =>
      (id, type, some (.const ``Nat [])) }
    unless (compareResources saved changedBinding).toOption.isNone do throwError "changed local context accepted"
    -- Two predecessors referring to the same successor are not a one-parent correspondence.
    id.withContext do
      let type ← id.getType
      let left ← Meta.mkFreshExprMVar type
      let right ← Meta.mkFreshExprMVar type
      let child ← Meta.mkFreshExprMVar type
      let before ← getMCtx
      left.mvarId!.assign child
      right.mvarId!.assign child
      let info : TacticInfo := {
        elaborator := `test, stx := ← getRef
        mctxBefore := before, goalsBefore := [left.mvarId!, right.mvarId!]
        mctxAfter := ← getMCtx, goalsAfter := [child.mvarId!]
      }
      let groups ← compareTactic context info
      unless groups.size == 2 && groups.all (·.unavailable?.isSome) do
        throwError "ambiguous predecessor was silently selected"
  iexact HP


section Heap

open HeapLang

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF]
variable {s : Stuckness} {E : CoPset}

/--
Write a cell, read its new value, and preserve a second cell's ownership.
Adapted from the framed-store and store/load examples in
`IrisTest/HeapLang/HeapTactics.lean`, with a complete proof and widget pause points.

Follow `Hl` from `v` to `v'`; `Hframe` remains `l' ↦ some w` throughout.
The postcondition binds the returned value `r` before any tactic introduces it.
-/
example {l l' : Loc} {v v' w : Val} :
    (l ↦ some v) ∗ (l' ↦ some w) ⊢
      WP hl(v(#l) ← &v'; !v(#l)) @ s ; E
        {{ r, ⌜r = v'⌝ ∗ (l ↦ some v') ∗ (l' ↦ some w) }} := by
  iintro ⟨Hl, Hframe⟩
  check_changes "Hframe:preserved Hl:changed" in wp_store
  check_changes "Hframe:preserved Hl:preserved" in wp_load
  imodintro
  iframe
  itrivial

end Heap

section Lock

open HeapLang HeapLang.SpinLock

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF] [SpinLockG GF]
local bi (IProp GF)

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
  check_changes "Hl:preserved HR:preserved Hcont:preserved Hinv:preserved Hcond:changed Hpt:changed" in wp_store
  check_changes "Hl:preserved HR:preserved Hcont:preserved Hinv:preserved Hcond:preserved Hpt:preserved" in imodintro
  check_changes "Hl:preserved HR:preserved Hcont:preserved Hinv:preserved Hcond:preserved Hpt:removed" in iframe Hpt
  check_changes "Hcont:preserved Hinv:preserved Hcond:preserved Hl:removed HR:removed" in
    (simp only [Bool.false_eq_true, ↓reduceIte]; iframe)
  iapply Hcont; itrivial

end Lock


end IrisTest.ProofMode.GoalChanges
