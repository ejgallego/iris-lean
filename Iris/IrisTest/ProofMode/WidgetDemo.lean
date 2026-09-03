/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.ProofMode.Widget
public meta import Iris.ProofMode.Widget
import Iris.ProofMode
public meta import Iris.ProofMode

namespace IrisTest.ProofMode.WidgetDemo

open Iris

show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.widgetProps]

/-- Outside Iris proof mode, the widget deliberately renders nothing. -/
example (n : Nat) : n = n := by
  rfl

/--
Demo state:

* pause after `iintro` to show two persistent and two spatial hypotheses;
* pause after `isplitr` to show two independently collapsible Iris goals.
-/
example [BI PROP] (P Q R S : PROP) :
    □ P ∗ □ (Q -∗ R) ⊢ Q -∗ S -∗ P ∗ R ∗ S := by
  iintro ⟨#HP, #HQR⟩ HQ HS
  isplitr [HQ HS]
  · iexact HP
  · isplitr [HS]
    · iapply HQR
      iexact HQ
    · iexact HS

end IrisTest.ProofMode.WidgetDemo
