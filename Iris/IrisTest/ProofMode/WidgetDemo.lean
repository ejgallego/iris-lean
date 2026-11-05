/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.ProofMode.Widget
public meta import Iris.ProofMode.Widget
import Iris.ProofMode
public meta import Iris.ProofMode
import IrisTest.ProofMode.WidgetTour
public meta import IrisTest.ProofMode.WidgetTour
import Iris.HeapLang.ProofMode
import Iris.HeapLang.Lib.SpinLock

namespace IrisTest.ProofMode.WidgetDemo

open Iris

-- Instances sharing a loader are displayed last-added first: tour above goals.
show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.panelProps,
  local IrisTest.ProofMode.WidgetTour.widget with IrisTest.ProofMode.WidgetTour.panelProps]

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

section Heap

open HeapLang

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF]
variable {s : Stuckness} {E : CoPset}

/--
Write a cell, read its new value, and preserve a second cell's ownership.
Adapted from the framed-store and store/load examples in
`IrisTest/HeapLang/HeapTactics.lean`, with a complete proof and widget pause points.

Follow `Hl` from `v` to `v'`; `Hframe` remains `l' ↦ some w` throughout.
The postcondition binds the returned value `r` before any tactic introduces it.
-/
example {l l' : Loc} {v v' w : Val} :
    (l ↦ some v) ∗ (l' ↦ some w) ⊢
      WP hl(v(#l) ← &v'; !v(#l)) @ s ; E
        {{ r, ⌜r = v'⌝ ∗ (l ↦ some v') ∗ (l' ↦ some w) }} := by
  iintro ⟨Hl, Hframe⟩
  -- widget-position-heap-store
  wp_store
  -- widget-position-heap-load
  wp_load
  imodintro
  -- widget-position-heap-post
  iframe
  itrivial

end Heap

section Lock

open HeapLang HeapLang.SpinLock

variable {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF] [SpinLockG GF]
local bi (IProp GF)

/--
The complete `SpinLock.release_spec` proof, with pause points around the store
inside the opened invariant. `Hinv` is persistent; `Hl` and `HR` supply the
ghost token and protected resource needed to restore the unlocked invariant.
-/
example (γ : GName) (lk : Val) (R : IProp GF) :
    {{ isLock γ lk R ∗ locked γ ∗ R }} hl(&release &lk)
    {{ RET hl_val(#()); True }} := by
  iintro %Φ ⟨#Hlock, Hl, HR⟩ Hcont
  wp_rec
  unfold isLock
  icases Hlock with ⟨%l, %Heq, #Hinv⟩
  subst Heq
  iinv Hinv with G1
  unfold lockInv
  icases G1 with ⟨%b, Hpt, Hcond⟩
  -- widget-position-spin-open
  wp_store
  -- widget-position-spin-stored
  imodintro
  -- widget-position-spin-frame
  iframe Hpt
  simp only [Bool.false_eq_true, ↓reduceIte]; iframe
  iapply Hcont; itrivial

end Lock

-- widget-position-how-vir
#check Iris.ProofMode.Widget.View.app

-- widget-position-feedback
#check Iris.ProofMode.parseIrisGoal?

-- Check all nine references against this complete source, including the pause points above.
check_widget_tour

end IrisTest.ProofMode.WidgetDemo
