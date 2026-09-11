/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Vir.Infoview.Surface
public import Vir.React

/-!
# Browser adapter

Keep JavaScript values, native RPC calls and effect lifetimes here. The renderer
uses `useState` and `useInspection` with ordinary Lean values; server-side Iris
recognition belongs in `Rpc.lean`, not in this module.

The helpers below compose VIR's native React bindings. They do not introduce a
second state store, reference registry, or Promise implementation.
-/

public section

namespace Iris.ProofMode.Widget.Client

open Lean.Vir

/-- A native response object, including a reference registered by the infoview client. -/
opaque Reply : Type

/-- Exact session and snapshot identity; the flag retires all snapshot interactions. -/
structure Context where
  session : Js Infoview.RpcSession
  snapshot : Js.Any
  active : RuntimeRef Bool

/-- Observe a native Promise, including exceptions in its fulfillment callback.
    Cleanup suppresses both late success and late failure without disposing the runtime. -/
def observe (active : RuntimeRef Bool) (pending : Js.Promise α)
    (success : Js α → RuntimeM Unit) (failure : RuntimeM Unit) : RuntimeM Unit := do
  let onSuccess ← Js.Function.ofLeanVoid fun value => do
    if ← active.get then success value
  let settled ← Js.Promise.thenVoid pending onSuccess
  let ignored ← Js.Function.ofLeanVoid fun (_ : Js Js.Undefined.Value) => pure ()
  let onFailure ← Js.Function.ofLeanVoid fun (_ : Js.Any) => do
    if ← active.get then failure
  let _ ← Js.Promise.thenVoidWithRejection settled ignored onFailure
  pure ()

def retire (lease : JSL (RuntimeRef Bool)) : Browser.DomM Unit := do
  (← LeanRef.fromJSL lease).set false

/-- React state containing a Lean value. `dependency` is the exact retained JSL
    object, not a fresh wrapper manufactured on every render. -/
structure State (α : Type) where
  value : α
  set : α → RuntimeM Unit
  dependency : JSL α

/-- Call unconditionally inside a component render, just like React's `useState`.
    Lean values are wrapped explicitly; native RPC references must not use this
    as a wire encoder. -/
def useState (initial : α) : React.ReactM (State α) := do
  let state ← React.StateTuple.toState (← React.Hooks.useState (← LeanRef.toJSL initial))
  return {
    value := ← LeanRef.fromJSL state.value
    set := fun value => do React.State.set state (← LeanRef.toJSL value)
    dependency := state.value
  }

/-- Send a snapshot-relative index with the exact native reference, never its JSON copy. -/
def inspect (context : Context) (reference : Nat) : RuntimeM (Js.Promise String) := do
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "snapshot") context.snapshot
  -- At this VIR pin, `ofNat` produces bigint (not JSON-serializable).
  -- Array indices and LSP positions below use actual JavaScript numbers.
  Js.Object.set params (← JsValue.ofString "reference") (← JsValue.ofFloat reference.toFloat)
  Infoview.RpcSession.call context.session (← JsValue.ofString "Iris.ProofMode.Widget.inspect") params

/-- Renderer-facing inspection state. Semantic indices never pass through strings. -/
structure Inspection where
  selected : Option Nat
  detail : String
  select : Nat → RuntimeM Unit
  close : RuntimeM Unit

/-- One effect per selection, retired on reselection or unmount. The enclosing
    snapshot has its own lifetime, checked before applying either RPC outcome. -/
def useInspection (context : Context) : React.ReactM Inspection := do
  let selected ← useState (none : Option Nat)
  let detail ← useState ""
  React.Hooks.useLeanEffectWithArrayDeps
    (do
      let active ← RuntimeRef.new true
      if let some reference := selected.value then
        detail.set "Inspecting…"
        if ← context.active.get then
          let pending ← inspect context reference
          observe active pending (fun value => do
            if ← context.active.get then detail.set (← JsValue.toString value))
            (do
              if ← context.active.get then
                detail.set "Inspection unavailable (expired snapshot or RPC error).")
      else
        detail.set ""
      LeanRef.toJSL active)
    retire #[selected.dependency]
  return {
    selected := selected.value
    detail := detail.value
    select := fun reference =>
      if selected.value == some reference then pure () else selected.set (some reference)
    close := selected.set none
  }

private def request (surface : Infoview.Surface) : RuntimeM (Js.Promise Reply) := do
  let pos ← Js.Object.empty
  Js.Object.set pos (← JsValue.ofString "line") (← JsValue.ofFloat surface.cursor.line.toFloat)
  Js.Object.set pos (← JsValue.ofString "character") (← JsValue.ofFloat surface.cursor.character.toFloat)
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "pos") pos
  Infoview.RpcSession.call surface.rpcSession (← JsValue.ofString "Iris.ProofMode.Widget.state") params

structure Loaded where
  state : WidgetState
  view : Js (React.Component WidgetState)

abbrev LoadState := Except String (Option Loaded)

/-- One effect per actual Surface prop object. Each successful snapshot constructs
    its view once, so a new snapshot resets selection rather than matching names. -/
def application (makeView : Context → RuntimeM (Js (React.Component WidgetState))) :
    RuntimeM (Js (React.Component Infoview.Surface)) :=
  React.Component.ofLeanJs fun input => do
    let surface ← LeanRef.fromJSL input
    let loading : LoadState := .ok none
    let state ← useState loading
    React.Hooks.useLeanEffectWithArrayDeps
      (do
        let active ← RuntimeRef.new true
        state.set loading
        let pending ← request surface
        observe active pending (fun reply => do
          let display ← JsValue.toString (← Js.String.fromAny
            (← Js.Object.get reply (← JsValue.ofString "display")))
          let decoded := Lean.Json.parse display >>= Lean.fromJson? (α := WidgetState)
          let result ← match decoded with
            | .error error => pure (.error ("Invalid Iris snapshot: " ++ error) : LoadState)
            | .ok payload =>
              if payload.version != 3 then
                pure (.error "Unsupported Iris widget snapshot version" : LoadState)
              else do
                let snapshot ← Js.Object.get reply (← JsValue.ofString "snapshot")
                let view ← makeView { session := surface.rpcSession, snapshot, active }
                pure (.ok (some { state := payload, view }) : LoadState)
          state.set result)
          (state.set (.error "Iris snapshot unavailable; check the Lean server and refresh."))
        LeanRef.toJSL active)
      retire #[input]
    match state.value with
    | .ok none => React.Node.spanText "Loading Iris goals…"
    | .ok (some loaded) => React.Node.component loaded.view loaded.state
    | .error error => do
      React.Node.elementWith "pre" #[React.Props.role "alert"] #[← React.Node.text error]

end Iris.ProofMode.Widget.Client
