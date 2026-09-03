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
#guard widgetProps.rpcMethod == "Iris.ProofMode.Widget.state"
#guard sampleState.version == 2

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
      let displayGoal ← toDisplayGoal irisGoal mvarId 0 none
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
  isplitr [HQ]
  · iexact HP
  · iexact HQ

end Preview

end IrisTest.ProofMode.Widget
