/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget
public meta import Iris.ProofMode.Widget.Rpc

/-! Experimental comparison only: production still uses the existing Iris renderer. -/

namespace IrisTest.ProofMode.WidgetCompare

open Lean Lean.Vir Lean.Vir.React Lean.Vir.Infoview

/-- The current Lean-authored renderer, with its normal native RPC path. -/
@[vir_export] public def current : RuntimeM (FunctionComponent PanelWidgetProps) :=
  Iris.ProofMode.Widget.View.app

/-- Compose the exact upstream component with the original native `fmt` object. -/
@[vir_export] public def native : RuntimeM (FunctionComponent Props) := do
  let component ← interactiveCode
  FunctionComponent.ofLean fun props => do
    Node.functionComponent component props (← Js.Array.empty)

open Lean.Server Lean.Meta Lean.Widget Iris.ProofMode in
/-- A native tagged target for the same typed Iris goal used by the current renderer. -/
@[server_rpc_method] public meta def target (params : Iris.ProofMode.Widget.StateRequest) :
    RequestM (RequestTask (Option Lean.Widget.CodeWithInfos)) := do
  let task ← FileWorker.getInteractiveGoals {
    textDocument := { uri := (← RequestM.readDoc).meta.uri }, position := params.pos }
  RequestM.mapRequestTaskCostly task fun goals? => do
    RequestM.checkCancelled
    if let some goals := goals? then
      for goal in goals.goals do
        let code? ← goal.ctx.val.runMetaM {} do
          goal.mvarId.withContext do
            let some irisGoal := parseIrisGoal? (← instantiateMVars (← goal.mvarId.getType))
              | return none
            return some (← ppExprTagged irisGoal.goal delabIProp)
        if code?.isSome then return code?
    return none

end IrisTest.ProofMode.WidgetCompare
