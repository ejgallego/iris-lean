/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public meta import Lean.Elab.Command

import IrisTest.ProofMode.WidgetTour.Model
public meta import IrisTest.ProofMode.WidgetTour.Model

open IrisTest.ProofMode.WidgetTour

def source := String.intercalate "\n" <|
  steps.toList.map fun step => "-- " ++ step.marker ++ "\n  skip"

#guard (resolve source).toOption.map Array.size == some 9
#guard (resolve (source.replace "-- widget-position-heap-load" "-- renamed")).toOption.isNone
#guard (resolve (source ++ "\n-- widget-position-spin-open\n  skip")).toOption.isNone
#guard (resolve (source.replace "  skip" "")).toOption.isNone
#guard ((resolve ("-- preamble\n\n" ++ source)).toOption.bind (·[0]?)).map (·.line) == some 3
#guard ((resolve source).toOption.bind (·[0]?)).map (·.character) == some 2

#guard (select #[{ line := 5, character := 2 }] { line := 0, character := 0 }).index == none
#guard (select #[{ line := 5, character := 2 }] { line := 5, character := 9 }).exact
#guard !(select #[{ line := 5, character := 2 }] { line := 6, character := 0 }).exact
-- The nearest preceding source position, even if the authored step order differs.
#guard (select #[{ line := 9, character := 0 }, { line := 5, character := 0 }]
  { line := 10, character := 0 }).index == some 0

-- Prev returns to a dimmed step, including the first; it only goes back from an exact step.
def positions : Array Position := #[{ line := 5, character := 2 }, { line := 10, character := 2 }]
#guard (select positions { line := 0, character := 0 }).previous? == none
#guard (select positions { line := 5, character := 2 }).previous? == none
#guard (select positions { line := 7, character := 0 }).previous? == some 0
#guard (select positions { line := 10, character := 2 }).previous? == some 0
#guard (select positions { line := 11, character := 0 }).previous? == some 1

-- include_str is relative to this file, not the caller's working directory.
-- IrisTest's Lake `needs` tracks the raw source, including comment-only marker edits.
elab "check_widget_tour" : command => do
  match resolve (include_str "../WidgetDemo.lean") with
  | .ok _ => pure ()
  | .error message => throwError message

check_widget_tour
