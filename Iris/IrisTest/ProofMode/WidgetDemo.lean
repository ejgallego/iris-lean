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
  -- widget-position-ordinary
  rfl

/--
Demo state:

* pause after `iintro` to show two persistent and two spatial hypotheses;
* pause after `isplitr` to show two independently collapsible Iris goals.
-/
example [BI PROP] (P Q R S : PROP) :
    □ P ∗ □ (Q -∗ R) ⊢ Q -∗ S -∗ P ∗ R ∗ S := by
  iintro ⟨#HP, #HQR⟩ HQ HS
  -- widget-position-contexts
  isplitr [HQ HS]
  -- widget-position-split
  · iexact HP
  · isplitr [HS]
    · iapply HQR
      iexact HQ
    · iexact HS

/-- Inspect `n` and `m` inside the binder bodies, before introducing them. -/
example [BI PROP] (A : Nat → Nat → PROP) :
    ⊢ (∀ n : Nat, ∀ m : Nat, A n m -∗ A n m) := by
  istart
  -- widget-position-binders
  iintro %n %m H
  iexact H

end IrisTest.ProofMode.WidgetDemo
