/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public meta import Iris.ProofMode.Widget.Rpc
public meta import Iris.HeapLang.ProofMode

/-! Browser-only cancellation probe. Imported into the harness's in-memory
document, never by the demo or production widget. -/

public meta section

namespace IrisTest.ProofMode.WidgetRpc

open Lean.Server
open Iris.ProofMode.Widget (StateRequest)

run_meta do
  for (source, expected) in [
    ("iapply wp_par (fun _ => P) (fun _ => Q) $$ [Hl1] [Hl2] [K]", "iapply wp_par…"),
    ("iapply\n  -- label ignores comments\n  wp_par (fun _ => P)", "iapply wp_par…"),
    ("iapply «lemma with spaces»", "iapply «lemma with spaces»"),
    ("wp_cmpxchg with hsuc hfail", "wp_cmpxchg…"), ("imodintro", "imodintro"),
    ("iframe Hpt", "iframe Hpt"), ("imod Hclose", "imod Hclose"),
    ("isplitr [HQ HS]", "isplitr…"), ("iintro HP HQ", "iintro HP…"),
    ("simp only [foo]", "simp only…"),
    ("iapply aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "iapply aaaaaaaaaaaaaaaaaaaaaa…")
  ] do
    let .ok stx := Lean.Parser.runParserCategory (← Lean.getEnv) `tactic source
      | throwError "could not parse label fixture: {source}"
    let actual := Iris.ProofMode.Widget.tacticLabel stx
    unless actual == expected && actual.length ≤ 30 do
      throwError "expected label {expected}, got {actual}"

initialize started : IO.Ref Nat ← IO.mkRef 0
initialize cancelled : IO.Ref Nat ← IO.mkRef 0

@[server_rpc_method]
def waitForCancellation (_ : StateRequest) : RequestM (RequestTask String) :=
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
