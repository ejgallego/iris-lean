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
#guard widgetProps.componentEntry == "Iris.ProofMode.Widget.createComponent"
#guard widgetProps.autoReloadMs == 1000
#guard sampleState.version == 3
#guard termParts (.tag 0 (.append #[.text "(", .tag 1 (.text "P"), .text ")"])) ==
  #[{ text := "(", reference := some 0 }, { text := "P", reference := some 1 },
    { text := ")", reference := some 0 }]
#guard termParts (.text "unknown notation") == #[{ text := "unknown notation", reference := none }]

show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.widgetProps]

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
      let (displayGoal, references) ← (toDisplayGoal irisGoal mvarId 0 none).run #[]
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
      unless displayGoal.target.code.stripTags == displayGoal.target.text do
        throwError "tag projection changed canonical text"
      let parts := termParts displayGoal.target.code
      for name in #["P", "Q"] do
        let some part := parts.find? (fun part => part.text == name)
          | throwError "missing tagged subterm {name}"
        let some index := part.reference | throwError "subterm {name} has no contextual reference"
        let some saved := references[index]? | throwError "reference index outside its snapshot"
        let detail ← inspectSavedTerm saved
        unless detail == name ++ " : PROP" do
          throwError "wrong contextual inspection: {detail}"
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
      let (goal, refs) ← (toDisplayGoal irisGoal mvarId 0 none).run #[]
      unless goal.target.code.stripTags == goal.target.text do
        throwError "tagged fallback changed canonical source"
      let parts := termParts goal.target.code
      for name in #["n", "m"] do
        let occurrences := parts.filter (fun part => part.text == name)
        unless occurrences.size >= 2 do
          throwError "expected repeated occurrences of {name}"
        let indices := occurrences.filterMap (·.reference)
        unless indices.size == occurrences.size && indices.toList.eraseDups.length == indices.size do
          throwError "repeated spelling lost occurrence identity"
        for index in indices do
          let some saved := refs[index]? | throwError "bad reference"
          let detail ← inspectSavedTerm saved
          unless detail == name ++ " : Nat" do
            throwError "binder context was not retained: {detail}"
  iintro %n %m H
  iexact H

end Preview

end IrisTest.ProofMode.Widget
