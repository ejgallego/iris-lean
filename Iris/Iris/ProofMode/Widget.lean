/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.View
public meta import Iris.ProofMode.Widget.Rpc
public import Vir.Attributes
public meta import Vir.Attributes
public import Vir.Infoview
public meta import Vir.Infoview

/-! Entrypoint and package configuration for the Iris proof-mode panel. The
rendering module stays independent of the meta RPC registration. -/

public section

namespace Iris.ProofMode.Widget

open Lean.Vir
open Lean.Vir.Infoview (WidgetProps)

def runtimeWasmPath : String :=
  ".lake/packages/lean_vir/web/public/vir-upstream.wasm"

vir_proof_widget View.app

-- Also expose the factory to the standalone `:vir` package smoke test.
attribute [vir_export] createComponent

/-- The generated package identity with the runtime path relative to the Iris workspace. -/
def panelProps : WidgetProps := { widgetProps with
  wasmPath := runtimeWasmPath
  setupHint :=
    "This widget uses the Lean 4.35 VIR runtime. See docs/vir-demo-runbook.md for setup; restart the Lean server after changing dependencies." }

end Iris.ProofMode.Widget
