/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public meta import Iris.ProofMode.Widget.Vendor.ExprDiff
public meta import Iris.ProofMode.Widget.Details

public meta section
namespace Iris.ProofMode.Widget.Diff
open Lean Meta Lean.Widget

/-- A unique, structurally identical argument survives a dropped application wrapper.
No names, printed text, definitional equality, or cross-tactic matching is used. -/
def strippedArgument? (before after : Expr) : Option SubExpr.Pos := Id.run do
  let args := before.consumeMData.getAppArgs
  let hits := args.zipIdx.filterMap fun (arg, i) => if arg == after then some i else none
  if hits.size != 1 then return none
  return some (SubExpr.Pos.root.pushNaryArg args.size hits[0]!)

private partial def hasPosition (pos : SubExpr.Pos) : CodeWithInfos → Bool
  | .text _ => false
  | .append children => children.any (hasPosition pos)
  | .tag info body => info.subexprPos == pos || hasPosition pos body

/-- Keep the surviving argument's entire tagged subtree. Mark only text outside it,
using its original enclosing semantic info; never slice or parse printed strings. -/
private partial def tagWrapper (keep : SubExpr.Pos) (parent : Option SubexprInfo := none) :
    CodeWithInfos → CodeWithInfos
  | .text text => match parent with
    | none => .text text
    | some info => .tag (info.withDiffTag .willDelete) (.text text)
  | .append children => .append (children.map (tagWrapper keep parent))
  | .tag info body =>
    if info.subexprPos == keep then .tag info body
    else .tag info (tagWrapper keep (some info) body)

open PrettyPrinter.Delaborator SubExpr in
/-- Local printing repair for a stripped modality: unpackIprop can discard the
body's root annotation (e.g. an `if`). Reattach it in its actual local context.
No global delaborator is registered; only accept byte-identical printed output. -/
private def delabWrapper : Delab := do
  let e ← getExpr
  let body (i : Nat) := withNaryArg i do
    let stx ← delabIProp
    addTermInfo (← getPos) stx (← getExpr)
    return stx
  let stx ← if e.isAppOfArity ``Iris.BI.BIBase.later 3 then do
      let p ← body 2
      `(iprop(▷ $p))
    else if e.isAppOfArity ``Iris.FUpd.fupd 5 then do
      let e1 ← withNaryArg 2 delab
      let e2 ← withNaryArg 3 delab
      let p ← body 4
      if e1 == e2 then `(iprop(|={$e1}=> $p)) else `(iprop(|={$e1,$e2}=> $p))
    else failure
  let stx ← annotateCurPos (← Iris.BI.unpackIprop stx)
  addTermInfo (← getPos) stx e
  return stx

private partial def rootInfo? (expr : Expr) : CodeWithInfos → Option SubexprInfo
  | .text _ => none
  | .append children => children.findSome? (rootInfo? expr)
  | .tag info body =>
    let term? := match info.info.val.info with
      | .ofTermInfo term => some term
      | .ofDelabTermInfo term => some term.toTermInfo
      | _ => none
    if term?.any (·.expr == expr) then some info else rootInfo? expr body

private def restoreWrapperRoot (before : Expr) (code : CodeWithInfos) : MetaM CodeWithInfos := do
  -- A custom delaborator's failure at the root reaches Lean's panic handler.
  -- Other stripped applications use the ordinary conservative diff below.
  unless before.isAppOfArity ``Iris.BI.BIBase.later 3 ||
      before.isAppOfArity ``Iris.FUpd.fupd 5 do return code
  try
    let some info := rootInfo? before code | return code
    let saved := info.info.val
    let term ← match saved.info with
      | .ofTermInfo term => pure term
      | .ofDelabTermInfo term => pure term.toTermInfo
      | _ => return code
    let repaired ← saved.ctx.runMetaM term.lctx <| ppExprTagged before (delabWrapper <|> delabIProp)
    if repaired.stripTags != code.stripTags then return code
    -- The before term can already carry changes from another resulting goal.
    -- Reprinting for this branch must retain that earlier branch's markings.
    let (_, tags) := (code.forM fun info _ => do
      if let some tag := info.diffStatus? then
        modify fun tags => tags.insert info.subexprPos tag
      : StateM (SubExpr.PosMap DiffTag) Unit).run {}
    repaired.mergePosMap (fun info tag => pure (info.withDiffTag tag)) tags
  catch ex =>
    if ex.isInterrupt then throw ex
    return code

/-- Unexpanders can discard a changed subterm's root tag. If its descendants
are still printed, mark the nearest printed ancestor. Ignore entirely hidden
arguments (such as instances); they must not colour an otherwise quiet term. -/
private def visibleChanges (changes : SubExpr.PosMap Vendor.Lean435.ExprDiffTag)
    (code : CodeWithInfos) : SubExpr.PosMap Vendor.Lean435.ExprDiffTag := Id.run do
  let (_, positions) := (code.forM fun info _ => modify (·.push info.subexprPos)
    : StateM (Array SubExpr.Pos) Unit).run #[]
  let encloses (outer inner : SubExpr.Pos) := outer.toArray.toList.isPrefixOf inner.toArray.toList
  let mut result := changes
  for (pos, tag) in changes.toList do
    if positions.contains pos || !positions.any (encloses pos) then continue
    let parent := positions.foldl (init := none) fun best candidate =>
      if encloses candidate pos && best.all (fun p => p.depth < candidate.depth) then
        some candidate else best
    if let some parent := parent then result := result.insert parent tag
  return result

/-- Both codes must have been printed independently at root, in their own saved
contexts. Diffing runs in the after-context; native semantic contexts stay intact.
If the printer hid the surviving argument, use Lean's conservative whole-term diff. -/
def decorate (before after : Expr) (beforeCode afterCode : CodeWithInfos) :
    MetaM (CodeWithInfos × CodeWithInfos) := do
  if before == after then return (beforeCode, afterCode)
  try
    if let some keep := strippedArgument? before after then
      let beforeCode ← if hasPosition keep beforeCode then pure beforeCode
        else restoreWrapperRoot before beforeCode
      if hasPosition keep beforeCode then
        return (tagWrapper keep none beforeCode, afterCode)
    let diff ← Vendor.Lean435.exprDiff before after
    let diff := { diff with
      changesBefore := visibleChanges diff.changesBefore beforeCode
      changesAfter := visibleChanges diff.changesAfter afterCode }
    return (← Vendor.Lean435.addDiffTags false diff beforeCode,
      ← Vendor.Lean435.addDiffTags true diff afterCode)
  catch ex =>
    if ex.isInterrupt then throw ex
    -- A diff is optional presentation, never a reason to lose a native proof state.
    return (beforeCode, afterCode)

private def atIndices (before after : Expr) (bi ai : Nat) (codes : Array CodeWithInfos) :
    MetaM (Array CodeWithInfos) := do
  let (b, a) ← decorate before after codes[bi]! codes[ai]!
  return codes.set! bi b |>.set! ai a

/-- Decorate canonical propositions and the separately rooted native invariant
fragments. When only one side is an invariant, conservatively mark its fragments. -/
def rendered (before after : Expr) (b a : RenderedTerm) (codes : Array CodeWithInfos) :
    MetaM (Array CodeWithInfos) := do
  let mut codes ← atIndices before after b.codeIndex a.codeIndex codes
  match b.invariant?, a.invariant?, Details.invariantExprs? before, Details.invariantExprs? after with
  | some bi, some ai, some (bn, bp), some (an, ap) =>
    codes ← atIndices bn an bi.name.codeIndex ai.name.codeIndex codes
    codes ← atIndices bp ap bi.body.codeIndex ai.body.codeIndex codes
  | _, _, _, _ =>
    if before != after then
      for (term, useAfter) in [(b, false), (a, true)] do
        if let some inv := term.invariant? then
          for index in [inv.name.codeIndex, inv.body.codeIndex] do
            let diff := Vendor.Lean435.ExprDiff.withChangePos .root .root
            codes := codes.set! index (← Vendor.Lean435.addDiffTags useAfter diff codes[index]!)
  return codes

end Iris.ProofMode.Widget.Diff
