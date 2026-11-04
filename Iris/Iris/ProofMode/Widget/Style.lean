/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Vir.React

namespace Iris.ProofMode.Widget.Style

open Lean.Vir
open Lean.Vir.React

public abbrev Entry := RuntimeM Js.Object

def style (entries : Array (String × String)) : Entry := do
  let object ← Js.Object.empty
  for (name, value) in entries do
    Js.Construction.field object (← JsValue.ofString name) (← JsValue.ofString value)
  pure object

def vscodeColor (name fallback : String) : String :=
  "var(--vscode-" ++ name ++ ", " ++ fallback ++ ")"

def border (color : String) : String :=
  "1px solid " ++ color

def foreground : String := vscodeColor "editor-foreground" "#24292f"
def background : String := vscodeColor "editor-background" "#ffffff"
def muted : String := vscodeColor "descriptionForeground" "#57606a"
def borderColor : String := vscodeColor "panel-border" "#d0d7de"
def codeBackground : String := vscodeColor "textCodeBlock-background" "#f6f8fa"
def persistentAccent : String := vscodeColor "textLink-foreground" "#0969da"
def spatialAccent : String := vscodeColor "editorWarning-foreground" "#9a6700"
def targetAccent : String := vscodeColor "symbolIcon-keywordForeground" "#8250df"
def editorFont : String :=
  "var(--vscode-editor-font-family, ui-monospace, SFMono-Regular, Menlo, Consolas, Liberation Mono, monospace)"

def editorSize : String := "var(--vscode-editor-font-size, 14px)"

public def region : Entry := style #[
  ("display", "grid"),
  ("gap", "4px"),
  ("minWidth", "0"),
  ("padding", "2px"),
  ("background", background),
  ("color", foreground),
  ("colorScheme", "light dark"),
  ("fontFamily", "var(--vscode-font-family, ui-sans-serif, system-ui, sans-serif)"),
  ("fontSize", "var(--vscode-font-size, 13px)"),
  ("lineHeight", "1.4")
]

public def goalList : Entry := style #[
  ("display", "grid"),
  ("gap", "4px")
]

public def goalCard : Entry := style #[
  ("display", "grid"),
  ("gap", "0"),
  ("minWidth", "0"),
  ("overflow", "hidden"),
  ("border", border borderColor),
  ("borderRadius", "4px"),
  ("background", background)
]

public def goalHeader : Entry := style #[
  ("display", "flex"),
  ("alignItems", "center"),
  ("justifyContent", "space-between"),
  ("gap", "5px"),
  ("minWidth", "0"),
  ("padding", "3px 5px"),
  ("flexWrap", "wrap")
]

public def goalHeading : Entry := style #[
  ("minWidth", "0"),
  ("margin", "0"),
  ("fontSize", "1em"),
  ("fontWeight", "760"),
  ("overflowWrap", "anywhere")
]

public def goalSummary : Entry := style #[
  ("margin", "0"),
  ("color", muted),
  ("fontSize", "1em"),
  ("fontWeight", "650"),
  ("overflowWrap", "anywhere")
]

public def collapseButton : Entry := style #[
  ("minWidth", "24px"),
  ("minHeight", "24px"),
  ("padding", "0 3px"),
  ("border", border borderColor),
  ("borderRadius", "3px"),
  ("background", codeBackground),
  ("color", foreground),
  ("font", "inherit"),
  ("fontSize", "1em"),
  ("fontWeight", "760"),
  ("cursor", "pointer")
]

public def goalContent : Entry := style #[
  ("display", "grid"),
  ("gap", "2px"),
  ("minWidth", "0"),
  ("padding", "1px 5px 4px")
]

public def contextSection (persistent : Bool) : Entry := style #[
  ("display", "grid"),
  ("gap", "0"),
  ("minWidth", "0"),
  ("paddingLeft", "4px"),
  ("borderLeft", "2px solid " ++ if persistent then persistentAccent else spatialAccent)
]

public def hypothesisList : Entry := style #[
  ("display", "grid"),
  ("gap", "1px"),
  ("margin", "0"),
  ("padding", "0"),
  ("listStyle", "none")
]

public def hypothesis : Entry := style #[
  ("display", "grid"),
  ("gridTemplateColumns", "minmax(min-content, auto) minmax(0, 1fr)"),
  ("alignItems", "baseline"),
  ("gap", "2px 5px"),
  ("minWidth", "0"),
  ("padding", "0 2px")
]

public def hypothesisName : Entry := style #[
  ("minWidth", "0"),
  ("fontFamily", editorFont),
  ("fontSize", editorSize),
  ("fontWeight", "760"),
  ("overflowWrap", "anywhere")
]

public def interactiveTerm : Entry := style #[
  ("display", "grid"),
  ("gap", "1px"),
  ("minWidth", "0")
]

public def termCode (target : Bool) : Entry := style #[
  ("minWidth", "0"),
  ("fontFamily", editorFont),
  ("fontSize", editorSize),
  ("lineHeight", "1.3"),
  ("whiteSpace", "pre-wrap"),
  ("overflowWrap", "anywhere"),
  ("color", if target then targetAccent else foreground)
]

public def targetSection : Entry := style #[
  ("display", "grid"),
  ("minWidth", "0"),
  ("marginTop", "1px"),
  ("paddingTop", "3px"),
  ("borderTop", "1px solid " ++ targetAccent)
]

public def target : Entry := style #[
  ("display", "grid"),
  ("gridTemplateColumns", "min-content minmax(0, 1fr)"),
  ("alignItems", "baseline"),
  ("gap", "5px"),
  ("minWidth", "0"),
  ("padding", "0 2px"),
  ("fontFamily", editorFont),
  ("lineHeight", "1.3"),
  ("overflowWrap", "anywhere")
]

public def glyph : Entry := style #[
  ("display", "inline-block"),
  ("minWidth", "1em"),
  ("fontFamily", editorFont),
  ("fontSize", editorSize),
  ("fontWeight", "800")
]

end Iris.ProofMode.Widget.Style
