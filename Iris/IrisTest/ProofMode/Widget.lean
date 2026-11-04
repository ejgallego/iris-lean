/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.ProofMode.Widget
public meta import Iris.ProofMode.Widget
import Iris.ProofMode
public meta import Iris.ProofMode

namespace IrisTest.ProofMode.Widget

open Lean Lean.Meta
open Iris.ProofMode.Widget

private def sampleState : WidgetState := {
  goals := #[{
    id := "goal-1"
    index := 0
    title := "case preview"
    persistent := #[{
      id := "hyp-p"
      kind := .persistent
      name := "HP"
      proposition := {
        id := "term-p"
        text := "P"
        typeText := "PROP"
        summary := "persistent hypothesis HP"
      }
    }]
    spatial := #[{
      id := "hyp-q"
      kind := .spatial
      name := "HQ"
      proposition := {
        id := "term-q"
        text := "Q"
        typeText := "PROP"
        summary := "spatial hypothesis HQ"
      }
    }]
    target := {
      id := "term-target"
      text := "P ∗ Q"
      typeText := "PROP"
      summary := "target of case preview"
    }
  }]
}

#guard match (Lean.fromJson? (Lean.toJson sampleState) : Except String WidgetState) with
  | .ok state => state == sampleState
  | .error _ => false
#guard panelProps.irPackage.entry == "Iris.ProofMode.Widget.createComponent"
#guard !panelProps.irPackage.fingerprint.isEmpty
#guard sampleState.version == widgetStateVersion

/-- Check the native tags and saved binder contexts, without the retired inspector RPC. -/
partial def checkNativeTags (code : Lean.Widget.CodeWithInfos)
    (name expectedType : String) : MetaM (Array Nat) := do
  match code with
  | .text _ => return #[]
  | .append children => return (← children.mapM (checkNativeTags · name expectedType)).flatten
  | .tag tag body =>
    let positions ← checkNativeTags body name expectedType
    if body.stripTags != name then return positions
    let info := tag.info.val
    let term? := match info.info with
      | .ofTermInfo term => some term
      | .ofDelabTermInfo term => some term.toTermInfo
      | _ => none
    let some term := term? | return positions
    let detail ← info.ctx.runMetaM term.lctx do
      return s!"{← ppExpr term.expr} : {← ppExpr (← inferType term.expr)}"
    unless detail == name ++ " : " ++ expectedType do
      throwError "native tag lost its contextual expression: {detail}"
    return positions.push tag.subexprPos.asNat

show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.panelProps]

section Preview

open Iris

example [BI PROP] (P Q : PROP) : □ P ⊢ Q -∗ P ∗ Q := by
  iintro #HP HQ
  run_tac do
    let mvarId ← Lean.Elab.Tactic.getMainGoal
    mvarId.withContext do
      let target ← instantiateMVars (← mvarId.getType)
      let some irisGoal := Iris.ProofMode.parseIrisGoal? target
        | throwError "expected parseIrisGoal? to recognize the elaborated Iris goal"
      let (displayGoal, codes) ← (toDisplayGoal irisGoal mvarId 0 none).run #[]
      unless displayGoal.persistent.map (·.name) == #["HP"] do
        throwError "unexpected persistent context"
      unless displayGoal.spatial.map (·.name) == #["HQ"] do
        throwError "unexpected spatial context"
      unless displayGoal.persistent[0]?.map (·.proposition.text) == some "P" do
        throwError "unexpected persistent proposition"
      unless displayGoal.spatial[0]?.map (·.proposition.text) == some "Q" do
        throwError "unexpected spatial proposition"
      unless displayGoal.target.text == "P ∗ Q" do
        throwError "unexpected target: {displayGoal.target.text}"
      unless displayGoal.persistent[0]?.map (·.proposition.typeText) == some "PROP" do
        throwError "unexpected persistent proposition type"
      unless displayGoal.target.summary == "target of goal 1" do
        throwError "unexpected target summary: {displayGoal.target.summary}"
      let terms := ((displayGoal.persistent ++ displayGoal.spatial).map (·.proposition)).push displayGoal.target
      unless codes.size == terms.size &&
          (terms.map (·.codeIndex)).toList.eraseDups.length == terms.size do
        throwError "each proposition must have a separate native code slot"
      for term in terms do
        unless codes[term.codeIndex]!.stripTags == term.text do
          throwError "native code changed canonical text"
      for name in #["P", "Q"] do
        unless !(← checkNativeTags codes[displayGoal.target.codeIndex]! name "PROP").isEmpty do
          throwError "missing native tag for {name}"

  isplitr [HQ]
  · iexact HP
  · iexact HQ

example [BI PROP] (A : Nat → Nat → PROP) :
    ⊢ (∀ n : Nat, ∀ m : Nat, A n m -∗ A n m) := by
  istart
  run_tac do
    let mvarId ← Lean.Elab.Tactic.getMainGoal
    mvarId.withContext do
      let some irisGoal := Iris.ProofMode.parseIrisGoal? (← instantiateMVars (← mvarId.getType))
        | throwError "expected a quantified Iris goal"
      let (goal, codes) ← (toDisplayGoal irisGoal mvarId 0 none).run #[]
      let code := codes[goal.target.codeIndex]!
      unless code.stripTags == goal.target.text do
        throwError "native code changed canonical source"
      for name in #["n", "m"] do
        let positions ← checkNativeTags code name "Nat"
        unless positions.size >= 2 && positions.toList.eraseDups.length == positions.size do
          throwError "repeated spelling lost native occurrence identity"

  iintro %n %m H
  iexact H

end Preview

end IrisTest.ProofMode.Widget
