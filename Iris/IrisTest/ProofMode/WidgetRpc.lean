/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public meta import Iris.ProofMode.Widget.Rpc

/-! Browser-only cancellation probe. Imported into the harness's in-memory
document, never by the demo or production widget. -/

public meta section

namespace IrisTest.ProofMode.WidgetRpc

open Lean.Server
open Iris.ProofMode.Widget (InspectRequest)

initialize started : IO.Ref Nat ← IO.mkRef 0
initialize cancelled : IO.Ref Nat ← IO.mkRef 0

@[server_rpc_method]
def waitForCancellation (_ : InspectRequest) : RequestM (RequestTask String) :=
  RequestM.asTask do
    started.modify (· + 1)
    let context ← readThe RequestContext
    for _ in [:1000] do
      if ← context.cancelTk.wasCancelledByCancelRequest then
        cancelled.modify (· + 1)
        throw .requestCancelled
      IO.sleep 10
    throw (RequestError.invalidParams "Cancellation probe timed out")

@[server_rpc_method]
def counts (_ : Unit) : RequestM (RequestTask (Nat × Nat)) :=
  RequestM.asTask do return (← started.get, ← cancelled.get)

end IrisTest.ProofMode.WidgetRpc
