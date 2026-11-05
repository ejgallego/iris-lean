/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Iris.ProofMode.Widget.Model
public meta import Iris.ProofMode.Display
public meta import Iris.BI.WeakestPre
public meta import Iris.Instances.Lib.Invariants
public meta import Iris.ProofMode.Widget.Model
public meta import Lean.Widget.InteractiveCode

public meta section
namespace Iris.ProofMode.Widget.Details
open Lean Meta
open Lean.Widget (CodeWithInfos ppExprTagged)

/-- Only the outermost typed WP/fupd supplies the current mask. -/
def maskExpr? (expr : Expr) : Option Expr :=
  let e := expr.consumeMData
  if e.isAppOfArity ``Wp.wp 9 then e.getAppArgs[6]?
  else if e.isAppOfArity ``FUpd.fupd 5 then e.getAppArgs[2]?
  else none

def invariantExprs? (expr : Expr) : Option (Expr × Expr) :=
  let e := expr.consumeMData
  if e.isAppOfArity ``Iris.inv 5 then some (e.getAppArgs[3]!, e.getAppArgs[4]!) else none

abbrev PrintPart := Expr → Bool → MetaM CodeWithInfos

def printPart : PrintPart := fun e iprop =>
  if iprop then ppExprTagged e delabIProp else ppExprTagged e

private def fragment (expr : Expr) (iprop : Bool) (print : PrintPart) :
    StateT (Array CodeWithInfos) MetaM NativePart := do
  let code ← print expr iprop
  let codeIndex ← modifyGet fun codes => (codes.size, codes.push code)
  return { text := code.stripTags, codeIndex }

/-- Keep canonical code intact on a detail-printing failure; never swallow cancellation. -/
private def attempt (codes : Array CodeWithInfos)
    (action : StateT (Array CodeWithInfos) MetaM α) : MetaM (Option α × Array CodeWithInfos) := do
  try
    let (value, next) ← action.run codes
    return (some value, next)
  catch ex =>
    if ex.isInterrupt then throw ex
    return (none, codes)

def mask? (expr : Expr) (codes : Array CodeWithInfos) (print : PrintPart := printPart) :
    MetaM (Option NativePart × Array CodeWithInfos) := do
  let some mask := maskExpr? (← instantiateMVars expr) | return (none, codes)
  attempt codes (fragment mask false print)

def invariant? (expr : Expr) (codes : Array CodeWithInfos) (print : PrintPart := printPart) :
    MetaM (Option InvariantParts × Array CodeWithInfos) := do
  let some (ns, body) := invariantExprs? (← instantiateMVars expr) | return (none, codes)
  attempt codes do
    return { name := ← fragment ns false print, body := ← fragment body true print }

end Iris.ProofMode.Widget.Details
