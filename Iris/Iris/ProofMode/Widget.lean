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
open Lean.Vir.Infoview (IRPackage PanelWidgetProps WidgetProps)
open Lean.Vir.React

def runtimeWasmPath : String :=
  ".lake/packages/lean_vir/web/public/vir-upstream.wasm"

@[vir_export]
def createComponent : RuntimeM (FunctionComponent PanelWidgetProps) :=
  View.app

def irPackage : IRPackage :=
  { roots := #["Iris.ProofMode.Widget.createComponent"] }

def widgetProps : WidgetProps where
  wasmPath := runtimeWasmPath
  irPackage
  componentEntry := "Iris.ProofMode.Widget.createComponent"
  autoReloadMs := 1000
  setupHint :=
    "This widget uses the Lean 4.32 VIR runtime. Check the VIR error above; after rebuilding VIR or changing dependencies, restart the Lean server."

end Iris.ProofMode.Widget
