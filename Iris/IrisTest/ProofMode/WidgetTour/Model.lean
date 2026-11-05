/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.Data.Json.FromToJson

public section
namespace IrisTest.ProofMode.WidgetTour
open Lean

structure Step where
  marker : String
  title : String
  look : String
  deriving Inhabited

/-- Presenter notes live with the checked demo, not in a separate JavaScript tour. -/
def steps : Array Step := #[
  { marker := "widget-position-heap-store", title := "wp_store updates Hl; Hframe untouched."
    look := "↳ under Hl and under ⊢." },
  { marker := "widget-position-heap-load", title := "wp_load only changes the goal."
    look := "No hypothesis annotations; ↳ under ⊢." },
  { marker := "widget-position-heap-post", title := "iframe discharges both cells."
    look := "Hl and Hframe leave the context; ⊢ reduces to the pure equality." },
  { marker := "widget-position-spin-open", title := "Store inside the opened invariant."
    look := "Hpt updated; ▷ stripped from Hpt and Hcond. The other four untouched." },
  { marker := "widget-position-spin-stored", title := "imodintro only changes the goal."
    look := "The update modality under ⊢." },
  { marker := "widget-position-spin-frame", title := "iframe Hpt."
    look := "Hpt leaves the context; ⊢ reduces." },
  { marker := "widget-position-contexts", title := "isplitr [HQ HS] distributes spatial ownership."
    look := "HQ and HS go to goal 2; HP and HQR remain in both goals." },
  { marker := "widget-position-how-vir", title := "Lean-authored React (VIR) and native InteractiveCode terms."
    look := "View.app below; the local show_panel_widgets at the top." },
  { marker := "widget-position-feedback", title := "Which changes matter: ownership, modalities, masks, invariants?"
    look := "Is per-goal resource distribution at splits useful? Which proof should we try next?" }
]

structure Position where
  line : Nat
  character : Nat
  deriving Repr, BEq, ToJson, FromJson

/-- Resolve exact marker-comment lines, then the first non-space position on the next
line. Reject ambiguous anchors rather than navigating to a plausible nearby line. -/
def resolve (source : String) : Except String (Array Position) := do
  let lines := source.splitOn "\n" |>.toArray
  let mut positions := #[]
  let mut seen := #[]
  for step in steps do
    if seen.contains step.marker then throw s!"Tour steps repeat marker {step.marker}"
    seen := seen.push step.marker
    let anchors := lines.zipIdx.filterMap fun (text, index) =>
      if text.trimAscii.toString == "-- " ++ step.marker then some index else none
    unless anchors.size == 1 do
      throw s!"Tour marker {step.marker}: expected exactly one marker, found {anchors.size}"
    let line := anchors[0]! + 1
    let some text := lines[line]? | throw s!"Tour marker {step.marker}: no following line"
    let trimmed := text.trimAsciiStart.toString
    if trimmed.isEmpty || trimmed.startsWith "--" then
      throw s!"Tour marker {step.marker}: expected code on the following line"
    positions := positions.push { line, character := text.length - trimmed.length }
  return positions

structure Selection where
  index : Option Nat := none
  exact : Bool := false
  deriving ToJson, FromJson

/-- Between steps, Prev returns to the displayed step before going further back. -/
def Selection.previous? (selection : Selection) : Option Nat :=
  match selection.index, selection.exact with
  | none, _ => none
  | some 0, true => none
  | some (i + 1), true => some i
  | some i, false => some i

/-- Select by source position, not by the order in which the user visited steps. -/
def select (positions : Array Position) (cursor : Position) : Selection := Id.run do
  let mut selected : Selection := {}
  let mut preceding : Option Position := none
  for (position, index) in positions.zipIdx do
    if position.line == cursor.line then return { index := some index, exact := true }
    if position.line < cursor.line && preceding.all (·.line < position.line) then
      selected := { index := some index }
      preceding := some position
  return selected


end IrisTest.ProofMode.WidgetTour
