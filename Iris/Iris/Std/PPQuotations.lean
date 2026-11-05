/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Lean.PrettyPrinter.Formatter
public meta import Lean.Data.Options

public meta section

/-- Keep Iris quotation wrappers in pretty-printed output. Disabling this is a
presentation-only POC: shortened HeapLang values and iProp expressions may not
re-parse, and iProp connectives can look like ordinary Lean propositions.
It changes formatting only, not elaboration or expression identity. -/
register_option pp.iris.quotations : Bool := {
  defValue := true
  descr := "retain Iris quotation wrappers; false is display-only and may not re-parse"
}
