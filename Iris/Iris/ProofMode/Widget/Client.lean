/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Vir.Infoview.Panel
public import Vir.Infoview.Client
public import Vir.React

/-!
# Browser adapter

Keep JavaScript values, native RPC calls and effect lifetimes here. The panel
component receives upstream `PanelWidgetProps` unchanged, obtains the current
position-specific RPC session through VIR's native hook, and keeps Iris display
state in explicit Lean-backed React props.
-/

public section

namespace Iris.ProofMode.Widget.Client

open Lean.Vir
open Lean.Vir.Infoview
open Lean.Vir.React

/-- A native response object, including a reference registered by the infoview client. -/
opaque Reply : Type

/-- Exact session and snapshot identity; the flag retires all snapshot interactions. -/
structure Context where
  session : Js RpcSession
  snapshot : Js.Any
  active : RuntimeRef Bool

/-- React state containing a Lean value and the exact native dependency object. -/
structure State (α : Type) where
  value : α
  set : α → RuntimeM Unit
  dependency : JSL α

/-- Call unconditionally inside a component render, just like React's `useState`. -/
def useState (initial : α) : ReactM (State α) := do
  let state ← Hooks.useState (← LeanRef.toJSL initial)
  let value ← LeanRef.fromJSL (← Js.Tuple2.first state)
  let set ← Js.Tuple2.second state
  return {
    value
    set := fun next => do
      let value ← LeanRef.toJSL next
      Js.Function.callVoid set (React.SetStateAction.ofValue value)
    dependency := ← Js.Tuple2.first state
  }

private def dependencyListCast (values : Js.Array α) : Js React.DependencyList := by
  unfold Lean.Vir.Js.Array at values
  unfold Lean.Vir.React.DependencyList
  unfold Lean.Vir.Js at *
  exact values

private def dependencyList (deps : Array (Js α)) : RuntimeM (Js React.DependencyList) := do
  let values ← Js.Array.ofArray deps
  pure (dependencyListCast values)

/-- Build a React effect from Lean setup and cleanup actions without revoking the runtime. -/
def useLeanEffectWithArrayDeps
    (setup : RuntimeM (JSL α))
    (cleanup : JSL α → RuntimeM Unit)
    (deps : Array (Js β)) : ReactM Unit := do
  let effect ← Js.Function.ofLean0 do
    let lease ← setup
    let release ← Js.Function.ofLean0Void (cleanup lease)
    pure (Js.UndefinedOr.ofJs release)
  Hooks.useEffect effect (Js.UndefinedOr.ofJs (← dependencyList deps))

/-- A Lean-valued component uses VIR's explicit native `data` props wrapper. -/
abbrev Component (α : Type) : Type :=
  FunctionComponent (Props.WithData α)

namespace Component

def ofLean (render : α → ReactM (Js Node)) : RuntimeM (Component α) :=
  FunctionComponent.ofLean fun props => do
    render (← LeanRef.fromJSL (← Props.WithData.data props))

def render (component : Component α) (props : α) : ReactM (Js Node) := do
  let nativeProps ← Props.WithData.make (← LeanRef.toJSL props)
  Node.functionComponent component nativeProps (← Js.Array.empty)

end Component

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

def retire (lease : JSL (RuntimeRef Bool)) : RuntimeM Unit := do
  (← LeanRef.fromJSL lease).set false

/-- Send a snapshot-relative index with the exact native reference, never its JSON copy. -/
def inspect (context : Context) (reference : Nat) : RuntimeM (Js.Promise String) := do
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "snapshot") context.snapshot
  Js.Object.set params (← JsValue.ofString "reference") (← JsValue.ofFloat reference.toFloat)
  RpcSession.call context.session (← JsValue.ofString "Iris.ProofMode.Widget.inspect") params

/-- Renderer-facing inspection state. Semantic indices never pass through strings. -/
structure Inspection where
  selected : Option Nat
  detail : String
  select : Nat → RuntimeM Unit
  close : RuntimeM Unit

/-- One effect per selection, retired on reselection or unmount. The enclosing
    snapshot has its own lifetime, checked before applying either RPC outcome. -/
def useInspection (context : Context) : ReactM Inspection := do
  let selected ← useState (none : Option Nat)
  let detail ← useState ""
  useLeanEffectWithArrayDeps
    (do
      let active ← RuntimeRef.new true
      if let some reference := selected.value then
        detail.set "Inspecting…"
        if ← context.active.get then
          let pending ← inspect context reference
          observe active pending (fun value => do
            if ← context.active.get then detail.set (← JsValue.toString value))
            (do if ← context.active.get then
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

private def request (session : Js RpcSession) (position : Js PanelPosition) :
    RuntimeM (Js.Promise Reply) := do
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "pos") position
  RpcSession.call session (← JsValue.ofString "Iris.ProofMode.Widget.state") params

structure Loaded where
  state : WidgetState
  view : Component WidgetState

abbrev LoadState := Except String (Option Loaded)

private def errorNode (message : String) : ReactM (Js Node) := do
  let props ← Js.Object.empty
  Js.Object.set props (← JsValue.ofString "role") (← JsValue.ofString "alert")
  let children ← Js.Array.ofArray #[← Node.text (← JsValue.ofString message)]
  Node.createElement (← ElementType.tag (← JsValue.ofString "pre")) props children

/-- One effect per actual upstream panel prop object. Each successful snapshot constructs
    its view once, so a new snapshot resets selection rather than matching names. -/
def application (makeView : Context → RuntimeM (Component WidgetState)) :
    RuntimeM (FunctionComponent PanelWidgetProps) :=
  FunctionComponent.ofLean fun input => do
    let session ← useRpcSession
    let position ← PanelWidgetProps.pos input
    let loading : LoadState := .ok none
    let state ← useState loading
    useLeanEffectWithArrayDeps
      (do
        let active ← RuntimeRef.new true
        state.set loading
        let pending ← request session position
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
                let view ← makeView { session, snapshot, active }
                pure (.ok (some { state := payload, view }) : LoadState)
          state.set result)
          (state.set (.error "Iris snapshot unavailable; check the Lean server and refresh."))
        LeanRef.toJSL active)
      retire #[input]
    match state.value with
    | .ok none => Node.text (← JsValue.ofString "Loading Iris goals…")
    | .ok (some loaded) => Component.render loaded.view loaded.state
    | .error error => errorNode error

end Iris.ProofMode.Widget.Client
