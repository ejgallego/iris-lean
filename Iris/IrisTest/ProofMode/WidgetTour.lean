/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import IrisTest.ProofMode.WidgetTour.Model
public meta import IrisTest.ProofMode.WidgetTour.Model
public import Vir.Attributes
public meta import Vir.Attributes
public import Iris.ProofMode.Widget.Client
public import Vir.Infoview
public meta import Vir.Infoview
public import Vir.ProofWidgets.Jsx
public meta import Lean.Server.FileWorker.RequestHandling

/-! A demo-only guided tour. Production Iris modules never import this module.
Marker references are checked against the whole source at build time and resolved
again against the current editor buffer for navigation. -/
public section
namespace IrisTest.ProofMode.WidgetTour

open Lean Lean.Vir Lean.Vir.React Lean.Vir.Infoview Lean.Vir.ProofWidgets
open scoped Lean.Vir.Js Lean.Vir.ProofWidgets.Jsx
open Iris.ProofMode.Widget

meta section

/-- Native DocumentPosition shape consumed directly by EditorConnection.revealPosition. -/
structure Destination where
  uri : String
  line : Nat
  character : Nat
  deriving Server.RpcEncodable

structure Reply where
  selection : String
  destinations : Array Destination
  deriving Server.RpcEncodable

structure Request where
  pos : Lsp.Position
  deriving Server.RpcEncodable

@[server_rpc_method]
def state (params : Request) : Server.RequestM (Server.RequestTask Reply) := do
  let doc ← Server.RequestM.readDoc
  Server.RequestM.asTask do
    Server.RequestM.checkCancelled
    let positions ← match resolve doc.meta.text.source with
      | .ok positions => pure positions
      | .error message => throw (Server.RequestError.invalidParams message)
    let selection := select positions { line := params.pos.line, character := params.pos.character }
    return {
      selection := (toJson selection).compress
      destinations := positions.map fun pos => { uri := doc.meta.uri, line := pos.line, character := pos.character }
    }

end

opaque NativeReply : Type

private structure Loaded where
  selection : Selection
  destinations : Js.Array PanelPosition
  epoch : Nat
  active : RuntimeRef Bool

private structure State where
  loaded : Option Loaded := none
  error : Option String := none

private def deps (values : Array Js.Any) : RuntimeM (Js React.DependencyList) := Js.Array.ofArray values

private def panelStyle (exact : Bool) : RuntimeM Js.Object := js%{
  "fontFamily" := js#"var(--vscode-font-family, sans-serif)",
  "fontSize" := js#"var(--vscode-font-size, 13px)",
  "color" := js#"var(--vscode-descriptionForeground, #777)",
  "borderBottom" := js#"1px solid var(--vscode-panel-border, #888)",
  "padding" := js#"3px 2px 5px", "marginBottom" := js#"4px",
  "opacity" := (← JsValue.ofString (if exact then "1" else "0.7")),
  "overflowWrap" := js#"anywhere"
}

def app : RuntimeM (FunctionComponent PanelWidgetProps) := do
  let serial ← RuntimeRef.new 0
  FunctionComponent.ofLean fun input => do
    let connection ← Hooks.useContext (← editorContext)
    let session ← useRpcSession
    let position ← PanelWidgetProps.pos input
    let uri ← PanelPosition.uri position
    let revision ← Client.useState (0 : Nat)
    useClientNotificationEffect (← js#"textDocument/didChange")
      (← Js.Function.ofLeanVoid fun (params : Js.Any) => do
        let document ← Js.Object.get params (← js#"textDocument")
        let changedUri ← Js.String.fromAny (← Js.Object.get document (← js#"uri"))
        if ← JsValue.toBool (← Js.String.equal changedUri uri) then revision.set (revision.value + 1))
      (Js.UndefinedOr.ofJs (← deps #[Js.erase uri, Js.erase revision.dependency]))
    let state ← Client.useState ({} : State)
    let epoch ← LeanRef.fromJSL (← Hooks.useMemo (← Js.Function.ofLean0 do
      let next := (← serial.get) + 1
      serial.set next
      LeanRef.toJSL next) (← deps #[Js.erase input, Js.erase session, Js.erase revision.dependency]))
    Hooks.useEffect (← Js.Function.ofLean0 do
      let live ← RuntimeRef.new true
      let controller ← Browser.DomM.toRuntime Browser.AbortController.create
      let options ← ClientRequestOptions.empty
      ClientRequestOptions.setAbortSignal options (← Browser.DomM.toRuntime (Browser.AbortController.getSignal controller))
      let params ← js%{ "pos" := position }
      let pending ← RpcSession.callWithOptions (result := NativeReply) session
        (← js#"IrisTest.ProofMode.WidgetTour.state") (Js.erase params) options
      Client.observe live pending (fun reply => do
        let selection ← JsValue.toString (← Js.String.fromAny (← Js.Object.get reply (← js#"selection")))
        match Json.parse selection >>= fromJson? (α := Selection) with
        | .error message => state.set { error := some ("Invalid tour reply: " ++ message) }
        | .ok selection =>
          let native ← Js.Object.get reply (← js#"destinations")
          let destinations : Js.Array PanelPosition := by unfold Js.Array Js.Any Js at *; exact native
          state.set { loaded := some { selection, destinations, epoch, active := live } })
        (fun _ => state.set { error := some "Tour unavailable: check the marker errors in Lean's Messages." })
      return Js.UndefinedOr.ofJs (← Js.Function.ofLean0Void do
        live.set false
        Browser.DomM.toRuntime (Browser.AbortController.abort controller)))
      (Js.UndefinedOr.ofJs (← deps #[Js.erase input, Js.erase session, Js.erase revision.dependency]))
    let loaded := state.value.loaded
    let ready := loaded.any (·.epoch == epoch) && state.value.error.isNone &&
      (← loaded.mapM (·.active.get)).getD false
    let selection := loaded.map (·.selection) |>.getD {}
    let index := selection.index
    let exact := ready && selection.exact
    let navigate (index : Nat) : RuntimeM Unit := do
      if !ready then return
      let some loaded := loaded | return
      if !(← loaded.active.get) then return
      let destination ← Js.Array.get loaded.destinations (← JsValue.ofFloat index.toFloat)
      let pending ← EditorConnection.revealPosition connection destination
      Client.observe loaded.active pending (fun _ => pure ())
        (fun _ => state.set { state.value with error := some "Could not reveal the tour step in the editor." })
    let previous := selection.previous?
    let prev ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => do
      if let some index := previous then navigate index
    let next ← Js.Function.ofLeanVoid fun (_ : Js SyntheticEvent) => navigate (index.map (· + 1) |>.getD 0)
    let count := index.map (fun i => s!"Step {i + 1} of {steps.size}") |>.getD s!"Tour · {steps.size} steps"
    let content ← if let some i := index then do
      let step := steps[i]!
      jsx%{<div><strong>{Html.text step.title}</strong>
        <div>{Html.text step.look}</div></div>}
    else Html.text "Start with Next, or move to a tour marker in this file."
    let error : Js.Array Node ← match state.value.error with
      | none => Js.Array.empty
      | some message => Js.Array.ofArray #[← jsx%{<div key="error" role="alert">{Html.text message}</div>}]
    return ← jsx%{<aside data-iris-widget-tour="true" data-tour-step={(← JsValue.ofString (index.map toString |>.getD "none"))}
      data-tour-exact={(← JsValue.ofBool exact)} aria-label="Iris demo tour" aria-busy={(← JsValue.ofBool (!ready && state.value.error.isNone))}
      style={(← panelStyle exact)}><div><span>{Html.text count}</span>{Html.text " "}
        <button type="button" data-tour-prev="true" disabled={(← JsValue.ofBool (!ready || previous.isNone))} onClick={prev}>Prev</button>
        {Html.text " "}<button type="button" data-tour-next="true" disabled={(← JsValue.ofBool (!ready || index.any (· + 1 ≥ steps.size)))} onClick={next}>Next</button>
        {Html.text (if ready && index.isSome && !exact then " · between steps" else "")}</div>{content}{error}</aside>}

vir_proof_widget app
attribute [vir_export] createComponent

def panelProps : WidgetProps := { widgetProps with
  wasmPath := ".lake/packages/lean_vir/web/public/vir-upstream.wasm"
  setupHint := "Build +IrisTest.ProofMode.WidgetTour:vir and restart the Lean server. See docs/vir-demo-runbook.md." }

/-- Reuse VIR's loader with a distinct panel identity: infoview keys instances by
module name and range, so using the same name for both panels causes collisions. -/
meta def widget : Lean.Widget.Module := Lean.Vir.Infoview.widget

end IrisTest.ProofMode.WidgetTour
