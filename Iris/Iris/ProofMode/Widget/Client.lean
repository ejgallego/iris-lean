/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public import Vir.Infoview.Panel
public import Vir.Infoview.Client
public import Vir.React
public import Vir.Browser

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

private def mkDependencyList (deps : Array (Js α)) : RuntimeM (Js React.DependencyList) := do
  Js.Array.ofArray (deps.map Js.erase)

/-- Build a React effect from Lean setup and cleanup actions without revoking the runtime. -/
private def useEffect
    (setup : RuntimeM (JSL α))
    (cleanup : JSL α → RuntimeM Unit)
    (deps : Array (Js β)) : ReactM Unit := do
  let effect ← Js.Function.ofLean0 do
    let lease ← setup
    let release ← Js.Function.ofLean0Void (cleanup lease)
    pure (Js.UndefinedOr.ofJs release)
  Hooks.useEffect effect (Js.UndefinedOr.ofJs (← mkDependencyList deps))

/-- A Lean-valued component uses VIR's explicit native `data` props wrapper. -/
abbrev Component (α : Type) : Type :=
  FunctionComponent (Props.WithData α)

namespace Component

def ofLean (render : α → ReactM (Js Node)) : RuntimeM (Component α) :=
  FunctionComponent.ofLean fun props => do
    render (← LeanRef.fromJSL (← Props.WithData.data props))

def render (component : Component α) (props : α)
    (key : Option (Js String) := none) : ReactM (Js Node) := do
  let nativeProps ← Props.WithData.make (← LeanRef.toJSL props)
  if let some key := key then
    Js.Object.set (Props.WithData.asProps nativeProps) (← JsValue.ofString "key") key
  Node.functionComponent component nativeProps (← Js.Array.empty)

end Component

/-- Observe a native Promise, including exceptions in its fulfillment callback.
    Cleanup suppresses both late success and late failure without disposing the runtime. -/
def observe (active : RuntimeRef Bool) (pending : Js.Promise α)
    (success : Js α → RuntimeM Unit) (failure : Js.Any → RuntimeM Unit) : RuntimeM Unit := do
  let onSuccess ← Js.Function.ofLeanVoid fun value => do
    if ← active.get then success value
  let settled ← Js.Promise.thenVoid pending onSuccess
  let ignored ← Js.Function.ofLeanVoid fun (_ : Js Js.Undefined.Value) => pure ()
  let onFailure ← Js.Function.ofLeanVoid fun error => do
    if ← active.get then failure error
  let _ ← Js.Promise.thenVoidWithRejection settled ignored onFailure
  pure ()

/-- A request owns its controller; retiring it prevents publication before signalling cancellation. -/
private structure RequestLease where
  active : RuntimeRef Bool
  controller : Js Browser.AbortController

private def RequestLease.create : RuntimeM RequestLease := do
  return { active := ← RuntimeRef.new true
           controller := ← Browser.DomM.toRuntime Browser.AbortController.create }

private def RequestLease.options (lease : RequestLease) : RuntimeM (Js ClientRequestOptions) := do
  let options ← ClientRequestOptions.empty
  ClientRequestOptions.setAbortSignal options
    (← Browser.DomM.toRuntime (Browser.AbortController.getSignal lease.controller))
  return options

private def retire (value : JSL RequestLease) : RuntimeM Unit := do
  let lease ← LeanRef.fromJSL value
  lease.active.set false
  Browser.DomM.toRuntime (Browser.AbortController.abort lease.controller)

/-- Format only checked native string/number fields. Unknown values never become `[object Object]`.
    The original RPC error remains native until this display boundary. -/
private def errorText (error : Js.Any) : RuntimeM (Js String) := do
  let fallback ← JsValue.ofString "Unknown RPC error"
  if ← JsValue.toBool (← Js.Nullable.isNull (← Js.Nullable.ofJs error)) then return fallback
  if ← JsValue.toBool (← Js.UndefinedOr.isUndefined (Js.UndefinedOr.ofJs error)) then return fallback
  if let some text ← Js.cast? (target := String) error then return text
  let message ← Js.cast? (target := String) (← Js.Object.get error (← JsValue.ofString "message"))
  let message := message.getD fallback
  let code ← Js.Object.get error (← JsValue.ofString "code")
  let code? : Option (Js String) ← match ← Js.cast? (target := String) code with
    | some code => pure (some code)
    | none => do
      match ← Js.cast? (target := Float) code with
      | some code => pure (some (← Js.Number.toString code (← Js.UndefinedOr.undefined)))
      | none => pure none
  match code? with
  | none => return message
  | some code =>
    Js.String.concat (← Js.String.concat (← Js.String.concat message (← JsValue.ofString " (")) code)
      (← JsValue.ofString ")")

private def failureText (label : String) (error : Js.Any) : RuntimeM (Js String) := do
  Js.String.concat (← JsValue.ofString (label ++ ": ")) (← errorText error)

/-- Send a snapshot-relative index with the exact native reference, never its JSON copy. -/
def inspect (context : Context) (reference : Nat) (options : Js ClientRequestOptions) :
    RuntimeM (Js.Promise String) := do
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "snapshot") context.snapshot
  Js.Object.set params (← JsValue.ofString "reference") (← JsValue.ofFloat reference.toFloat)
  RpcSession.callWithOptions context.session (← JsValue.ofString "Iris.ProofMode.Widget.inspect")
    (Js.erase params) options

private inductive InspectionResult where
  | text (value : Js String)
  | failed (error : Js.Any)

/-- Renderer-facing inspection state. Semantic indices never pass through strings. -/
structure Inspection where
  selected : Option Nat
  detail : Js String
  select : Nat → RuntimeM Unit
  close : RuntimeM Unit

/-- One effect per selection, retired on reselection or unmount. The enclosing
    snapshot has its own lifetime, checked before applying either RPC outcome. -/
def useInspection (context : Context) : ReactM Inspection := do
  let selected ← useState (none : Option Nat)
  let detail ← useState (.text (← JsValue.ofString "") : InspectionResult)
  useEffect
    (do
      let lease ← RequestLease.create
      if let some reference := selected.value then
        detail.set (.text (← JsValue.ofString "Inspecting…"))
        if ← context.active.get then
          let pending ← inspect context reference (← lease.options)
          observe lease.active pending (fun value => do if ← context.active.get then detail.set (.text value))
            (fun error => do if ← context.active.get then detail.set (.failed error))
      else
        detail.set (.text (← JsValue.ofString ""))
      LeanRef.toJSL lease)
    retire #[selected.dependency]
  let text ← match detail.value with
    | .text value => pure value
    | .failed error => failureText "Inspection unavailable" error
  return {
    selected := selected.value
    detail := text
    select := fun reference =>
      if selected.value == some reference then pure () else selected.set (some reference)
    close := selected.set none
  }

private def request (session : Js RpcSession) (position : Js PanelPosition) (options : Js ClientRequestOptions) :
    RuntimeM (Js.Promise Reply) := do
  let params ← Js.Object.empty
  Js.Object.set params (← JsValue.ofString "pos") position
  RpcSession.callWithOptions session (← JsValue.ofString "Iris.ProofMode.Widget.state")
    (Js.erase params) options

structure Loaded where
  state : WidgetState
  view : Component WidgetState

inductive LoadError where
  | invalid (message : String)
  | rpc (error : Js.Any)

abbrev LoadState := Except LoadError (Option Loaded)

private def errorNode (message : Js String) : ReactM (Js Node) := do
  let props ← Js.Object.empty
  Js.Object.set props (← JsValue.ofString "role") (← JsValue.ofString "alert")
  let style ← Js.Object.empty
  Js.Object.set style (← JsValue.ofString "whiteSpace") (← JsValue.ofString "pre-wrap")
  Js.Object.set style (← JsValue.ofString "overflowWrap") (← JsValue.ofString "anywhere")
  Js.Object.set props (← JsValue.ofString "style") style
  let children ← Js.Array.ofArray #[← Node.text message]
  Node.createElement (← ElementType.tag (← JsValue.ofString "pre")) props children

/-- Follow document edits and native session replacement as well as panel props.
    Each successful snapshot constructs
    its view once, so a new snapshot resets selection rather than matching names. -/
def application (makeView : Context → RuntimeM (Component WidgetState)) :
    RuntimeM (FunctionComponent PanelWidgetProps) :=
  FunctionComponent.ofLean fun input => do
    let session ← useRpcSession
    let position ← PanelWidgetProps.pos input
    let uri ← PanelPosition.uri position
    let revision ← Hooks.useState (α := Nat) (← JsValue.ofNat 0)
    let revisionValue ← Js.Tuple2.first revision
    let revisionSetter ← Js.Tuple2.second revision
    let one ← JsValue.ofNat 1
    let changed ← Js.Function.ofLeanVoid fun (params : Js.Any) => do
      let document ← Js.Object.get params (← JsValue.ofString "textDocument")
      let changedUri ← Js.String.fromAny (← Js.Object.get document (← JsValue.ofString "uri"))
      if ← JsValue.toBool (← Js.String.equal changedUri uri) then
        let update ← Js.Function.ofLean fun previous => Js.Nat.add previous one
        Js.Function.callVoid revisionSetter (React.SetStateAction.ofUpdater update)
    useClientNotificationEffect (← JsValue.ofString "textDocument/didChange") changed
      (← Js.UndefinedOr.undefined)
    let loading : LoadState := .ok none
    let state ← useState loading
    useEffect
      (do
        let lease ← RequestLease.create
        state.set loading
        let pending ← request session position (← lease.options)
        observe lease.active pending (fun reply => do
          let display ← JsValue.toString (← Js.String.fromAny
            (← Js.Object.get reply (← JsValue.ofString "display")))
          let decoded := Lean.Json.parse display >>= Lean.fromJson? (α := WidgetState)
          let result ← match decoded with
            | .error error => pure (.error (.invalid ("Invalid Iris snapshot: " ++ error)) : LoadState)
            | .ok payload =>
              if payload.version != 3 then
                pure (.error (.invalid "Unsupported Iris widget snapshot version") : LoadState)
              else do
                let snapshot ← Js.Object.get reply (← JsValue.ofString "snapshot")
                let view ← makeView { session, snapshot, active := lease.active }
                pure (.ok (some { state := payload, view }) : LoadState)
          state.set result)
          (fun error => state.set (.error (.rpc error)))
        LeanRef.toJSL lease)
      retire #[Js.erase input, Js.erase session, Js.erase revisionValue]
    match state.value with
    | .ok none => Node.text (← JsValue.ofString "Loading Iris goals…")
    | .ok (some loaded) => Component.render loaded.view loaded.state
    | .error (.invalid error) => errorNode (← JsValue.ofString error)
    | .error (.rpc error) => errorNode (← failureText "Iris snapshot unavailable" error)

end Iris.ProofMode.Widget.Client
