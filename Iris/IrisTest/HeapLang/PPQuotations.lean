/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

import Iris.HeapLang.ProofMode
import Iris.Instances.Lib.Invariants
public meta import Lean.Widget.InteractiveCode

open Iris HeapLang Lean Meta Elab.Tactic

private meta partial def taggedLocal (code : Widget.CodeWithInfos) (name : String)
    (expected : Expr) : MetaM Nat := do
  match code with
  | .text _ => return 0
  | .append children => return (← children.mapM (taggedLocal · name expected)).foldl (· + ·) 0
  | .tag tag body =>
    let count ← taggedLocal body name expected
    if body.stripTags != name then return count
    let saved := tag.info.val
    let term ← match saved.info with
      | .ofTermInfo term => pure term
      | .ofDelabTermInfo term => pure term.toTermInfo
      | _ => throwError "missing term info"
    unless term.expr == expected do throwError "wrong expression for {name}"
    let type ← inferType expected
    saved.ctx.runMetaM term.lctx do
      unless ← isDefEq (← inferType term.expr) type do throwError "wrong saved type for {name}"
    return count + 1

example (b : Bool) (v : Val) : True := by
  run_tac do
    withMainContext do
      let b := mkIdent `b
      let v := mkIdent `v
      let cases := #[
        (← `(hl_val(#false)), "hl_val(#false)", "#false"),
        (← `(hl_val(#())), "hl_val(#())", "#()"),
        (← `(hl_val(#$b)), "hl_val(#b)", "#b"),
        (← `(hl_val((&$v, #$b))), "hl_val((&v, #b))", "(&v, #b)"),
        (← `(hl_val(injl(injr(#())))), "hl_val(injl(injr(#())))", "injl(injr(#()))"),
        (← `(hl(v(#$b))), "hl(#b)", "hl(#b)"),
        (← `(hl(v((#$b, &$v)))), "hl(v((#b, &v)))", "hl(v((#b, &v)))"),
        (← `(hl_val(&$v)), "v", "v"),
        (← `(Val.rec_ Binder.anon (Binder.named "x") (Exp.var "x")), "hl_val(λ x, x)", "hl_val(λ x, x)"),
        (← `(Val.rec_ (Binder.named "f") (Binder.named "x") (Exp.var "x")), "hl_val(rec f x := x)", "hl_val(rec f x := x)")]
      for (stx, plain, short) in cases do
        let expr ← Lean.Elab.Term.elabTerm stx none
        for (quotations, expected) in [(true, plain), (false, short)] do
          let code ← withOptions (pp.iris.quotations.set · quotations) (Widget.ppExprTagged expr)
          unless code.stripTags == expected do
            throwError "quotations={quotations}: expected {expected}, got {code.stripTags}"
      let expr ← Lean.Elab.Term.elabTerm (← `((hl_val((#$b, &$v)), hl(v(#$b))))) none
      for quotations in [true, false] do
        let code ← withOptions (pp.iris.quotations.set · quotations) (Widget.ppExprTagged expr)
        for (name, minimum) in [("b", 2), ("v", 1)] do
          let expected := (← getLocalDeclFromUserName (Name.mkSimple name)).toExpr
          unless (← taggedLocal code name expected) >= minimum do throwError "missing {name} tag"
  trivial

example {hlc} {GF : BundledGFunctors} [HeapLangGS hlc GF] (N : Namespace) : True := by
  run_tac do
    withMainContext do
      let ns := mkIdent `N
      let gf := mkIdent `GF
      let expr ← Lean.Elab.Term.elabTerm (← `((inv $ns iprop(∃ b : Bool, ⌜b = true⌝) : IProp $gf))) none
      for (quotations, expected) in [(true, "inv N iprop(∃ b, ⌜b = true⌝)"), (false, "inv N (∃ b, ⌜b = true⌝)")] do
        let code ← withOptions (pp.iris.quotations.set · quotations) (Widget.ppExprTagged expr)
        unless code.stripTags == expected do throwError "expected {expected}, got {code.stripTags}"
        unless (← taggedLocal code "N" (← getLocalDeclFromUserName `N).toExpr) > 0 do
          throwError "namespace tag missing"
  trivial
