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
  text : String
  look : String
  deriving Inhabited

/-- Presenter notes live with the checked demo, not in a separate JavaScript tour. -/
def steps : Array Step := #[
  { marker := "widget-position-heap-store", title := "A store changes one resource"
    text := "This complete HeapLang proof writes v' into l and then reads it. After wp_store, Hl changes while Hframe is preserved; Lean's ordinary goal diff remains beside this resource view."
    look := "Look at Hl and its ‘was’ line, then Hframe. Hover over l or v' for a native type popup; Ctrl/Cmd-click some for its definition." },
  { marker := "widget-position-heap-load", title := "Read the value back"
    text := "The store has finished, so Hl now owns the cell containing v'. The selected wp_load preserves both resources while advancing the program to its postcondition."
    look := "Compare the two preserved markers. Hover over the postcondition's bound r to inspect its saved binder context." },
  { marker := "widget-position-heap-post", title := "Reach the postcondition"
    text := "The read returned v', and the current target states that equality together with ownership of both cells. Here iframe removes resources from the remaining goal; that is a context change, not a claim of consumption."
    look := "Find ⌜v' = v'⌝ and both owned cells in the target." },
  { marker := "widget-position-spin-open", title := "A store inside an opened invariant"
    text := "This is the complete SpinLock release proof, paused inside the opened invariant. The store changes Hpt to the false cell and strips the later modality from Hpt and Hcond; Hinv, Hl, HR and Hcont are preserved."
    look := "Compare both changed rows and their ‘was’ lines. Hover over γ or b for the ordinary Lean context." },
  { marker := "widget-position-spin-stored", title := "Restore the invariant"
    text := "The lock cell now contains false, and the target asks us to restore the invariant under the reduced mask. The selected imodintro changes the target while preserving all six resources."
    look := "Look at the update modality in the current target and the preserved resource labels." },
  { marker := "widget-position-spin-frame", title := "Frame the lock cell"
    text := "The selected iframe Hpt moves the cell ownership out of the remaining context. Hpt is listed last as removed; this view does not infer whether a resource was consumed or framed from two snapshots alone."
    look := "Find the struck-through Hpt row. Contrast removal here with the changed proposition at the store." },
  { marker := "widget-position-how-vir", title := "How VIR is used"
    text := "The proof panel and this tour are React components authored in Lean and packaged by vir_proof_widget. Typed parseIrisGoal? data drives the Iris view, while original CodeWithInfos objects go directly to upstream InteractiveCode."
    look := "The checked View.app declaration below is the production entry. Compare the local show_panel_widgets declaration near the top of this file." },
  { marker := "widget-position-feedback", title := "What should this view add?"
    text := "Does resource-level comparison explain a step better than the ordinary goal diff, and which changes matter most: ownership, modalities, masks or invariant state? Would distant comparisons justify pinning, and which real proof should we try next?"
    look := "Tell us what must stay visible, what can collapse, and one confusing state to preserve as a regression." }
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
