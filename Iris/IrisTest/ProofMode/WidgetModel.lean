/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.Widget.Model

open Iris.ProofMode.Widget

def term (text : String) : RenderedTerm :=
  { id := text, text, typeText := "PROP", summary := "test" }
def hyp (id : String) (kind : ContextKind := .spatial) : DisplayHypothesis :=
  { id, kind, name := id, proposition := term id }
def resource (id : String) (status : Iris.ProofMode.GoalChanges.ResourceStatus)
    (after? : Option DisplayHypothesis) : DisplayResourceChange := { id, name := id, status, after? }
def hp := hyp "HP" .persistent
def hq := hyp "HQ"
def hs := hyp "HS"
def goal : DisplayGoal := {
  id := "before", index := 0, title := "goal 1"
  persistent := #[hp], spatial := #[hq, hs], target := term "Q ∗ S" }
def split : DisplayComparison := {
  tactic := "isplitr…", beforeId := "before"
  branches := #[
    { id := "left", index := 0, target? := some (term "P"), targetChanged := true
      resources := #[resource "HP" .preserved (some hp), resource "HQ" .removed none, resource "HS" .removed none] },
    { id := "right", index := 1, target? := some (term "Q ∗ S"), targetChanged := true
      resources := #[resource "HP" .preserved (some hp), resource "HQ" .preserved (some hq), resource "HS" .preserved (some hs)] }
  ] }

-- Shared persistent resources are quiet; spatial destinations use successor order.
#guard (split.hypothesisAnnotations hp).isEmpty
#guard (split.hypothesisAnnotations hq).map (·.lead) == #["isplitr…: goal 2"]
#guard (split.hypothesisAnnotations hs).map (·.kind) == #[.distributed]
#guard split.targetAnnotations.map (·.lead) == #["isplitr…: goal 1 ⊢ ", "isplitr…: goal 2 ⊢ "]
#guard goal.changeSummary split == "before isplitr… · changes HQ, HS and the goal"

-- Ordinary successors retain their real numbering without hiding Iris branches.
def mixed := { split with tactic := "iaaccintro…", branches :=
  #[{ id := "side-condition", index := 0, leanGoal := true },
    { split.branches[0] with index := 1 }, { split.branches[1] with index := 2 }] }
#guard mixed.unavailable.isNone
#guard (mixed.hypothesisAnnotations hq).map (·.lead) == #["iaaccintro…: goal 3"]
#guard mixed.targetAnnotations.map (·.lead) == #["iaaccintro…: goal 1 is a Lean goal",
  "iaaccintro…: goal 2 ⊢ ", "iaaccintro…: goal 3 ⊢ "]
#guard (mixed.targetAnnotations[0]?.bind (·.term?)).isNone

def changed : DisplayComparison := {
  tactic := "wp_store", beforeId := "before"
  branches := #[{
    id := "after", target? := some (term "new target"), targetChanged := true
    resources := #[resource "HP" .preserved (some hp),
      resource "HQ" .changed (some { hq with proposition := term "new Q" }), resource "HS" .preserved (some hs)] }] }
#guard (changed.hypothesisAnnotations hp).isEmpty && (changed.hypothesisAnnotations hs).isEmpty
#guard (changed.hypothesisAnnotations hq).map (·.term?.map (·.text)) == #[some "new Q"]
#guard goal.changeSummary changed == "before wp_store · changes HQ and the goal"
#guard changed.targetAnnotations.map (·.term?.map (·.text)) == #[some "new target"]

def modal : DisplayComparison := { changed with tactic := "imodintro", branches := #[
  { changed.branches[0] with resources := #[resource "HQ" .preserved (some hq)] }] }
#guard (modal.hypothesisAnnotations hq).isEmpty
#guard goal.changeSummary modal == "before imodintro · only the goal changes"
def unchanged : DisplayComparison := { modal with tactic := "skip", branches := #[
  { modal.branches[0] with targetChanged := false }] }
#guard unchanged.targetAnnotations.isEmpty
#guard goal.changeSummary unchanged == "before skip · changes nothing in Iris"

def moved : DisplayComparison := { changed with branches := #[
  { id := "after", resources := #[resource "HQ" .changed (some { hq with kind := .persistent })] }] }
#guard (moved.hypothesisAnnotations hq).map (·.lead) == #["wp_store: □ "]
def gone : DisplayComparison := { changed with tactic := "iframe HQ", branches := #[
  { id := "after", resources := #[resource "HQ" .removed none] }] }
#guard (gone.hypothesisAnnotations hq).map (·.lead) == #["iframe HQ: no longer in context"]
#guard (gone.hypothesisAnnotations hq).map (·.kind) == #[.gone]
def added : DisplayComparison := { changed with tactic := "iintro", branches := #[
  { id := "after", resources := #[resource "HS" .added (some hs), resource "HQ" .added (some hq)] }] }
#guard (added.additions .spatial).map (·.1.id) == #["HS", "HQ"]
#guard (added.additions .spatial).map (·.2.lead) == #["iintro adds ∗HS: ", "iintro adds ∗HQ: "]
#guard (added.additions .persistent).isEmpty

-- A closed or refused comparison must never claim resources disappeared.
def closed : DisplayComparison := { tactic := "iexact HQ", beforeId := "before", closed := true }
#guard goal.changeSummary closed == "before iexact HQ · closes this goal"
#guard (closed.hypothesisAnnotations hq).isEmpty && closed.targetAnnotations.isEmpty
def unavailable := { split with branches := #[{ id := "unknown", unavailable? := some "not Iris" }] }
#guard (unavailable.hypothesisAnnotations hq).isEmpty && unavailable.targetAnnotations.isEmpty
#guard (unavailable.additions .spatial).isEmpty
#guard goal.changeSummary unavailable == "can't compare Iris goals for isplitr… (goal 1)"

def quiet := { changed with tactic := "·", quiet := true }
#guard goal.changeSummary quiet == ""
#guard (quiet.hypothesisAnnotations hq).isEmpty && quiet.targetAnnotations.isEmpty
#guard (quiet.additions .spatial).isEmpty
#guard ([
  ("goal correspondence is ambiguous", "can't tell which hypotheses tac keeps"),
  ("duplicate resource identities", "can't tell which hypotheses tac keeps"),
  ("the proposition domain changed", "tac changes the context's types; not compared"),
  ("a shared local declaration changed", "tac changes a hypothesis other goals share; not compared"),
  ("the resulting goal is not in Iris proof mode", "tac leaves Iris proof mode"),
  ("open descendants are absent from the tactic's result", "tac's resulting Iris goals aren't available")
  ] : List (String × String)).all fun (reason, message) =>
    goal.changeSummary { tactic := "tac", beforeId := "before", unavailable? := some reason } == message
#guard match (Lean.fromJson? (Lean.toJson { goal with comparison? := some split }) : Except String DisplayGoal) with
  | .ok decoded => decoded.comparison? == some split
  | .error _ => false
