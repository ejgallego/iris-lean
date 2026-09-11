/-
Copyright (c) The Iris-Lean Contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
module

public import Vir.React

namespace Iris.ProofMode.Widget.Style

open Lean.Vir.React

private def style (entries : Array (String × String)) : Props.Entry :=
  Props.stylePairs entries

private def vscodeColor (name fallback : String) : String :=
  "var(--vscode-" ++ name ++ ", " ++ fallback ++ ")"

private def border (color : String) : String :=
  "1px solid " ++ color

private def foreground : String := vscodeColor "editor-foreground" "#24292f"
private def background : String := vscodeColor "editor-background" "#ffffff"
private def muted : String := vscodeColor "descriptionForeground" "#57606a"
private def borderColor : String := vscodeColor "panel-border" "#d0d7de"
private def codeBackground : String := vscodeColor "textCodeBlock-background" "#f6f8fa"
private def persistentAccent : String := vscodeColor "textLink-foreground" "#0969da"
private def spatialAccent : String := vscodeColor "editorWarning-foreground" "#9a6700"
private def targetAccent : String := vscodeColor "symbolIcon-keywordForeground" "#8250df"
private def editorFont : String :=
  "var(--vscode-editor-font-family, ui-monospace, SFMono-Regular, Menlo, Consolas, Liberation Mono, monospace)"

public def region : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "4px"),
  ("minWidth", "0"),
  ("padding", "2px"),
  ("background", background),
  ("color", foreground),
  ("colorScheme", "light dark"),
  ("fontFamily", "Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif")
]

public def goalList : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "4px")
]

public def goalCard : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "0"),
  ("minWidth", "0"),
  ("overflow", "hidden"),
  ("border", border borderColor),
  ("borderRadius", "4px"),
  ("background", background)
]

public def goalHeader : Props.Entry := style #[
  ("display", "flex"),
  ("alignItems", "center"),
  ("justifyContent", "space-between"),
  ("gap", "5px"),
  ("minWidth", "0"),
  ("padding", "3px 5px"),
  ("flexWrap", "wrap")
]

public def goalHeading : Props.Entry := style #[
  ("minWidth", "0"),
  ("margin", "0"),
  ("fontSize", "0.76rem"),
  ("fontWeight", "760"),
  ("overflowWrap", "anywhere")
]

public def goalSummary : Props.Entry := style #[
  ("margin", "0"),
  ("color", muted),
  ("fontSize", "0.68rem"),
  ("fontWeight", "650"),
  ("overflowWrap", "anywhere")
]

public def collapseButton : Props.Entry := style #[
  ("minWidth", "20px"),
  ("minHeight", "20px"),
  ("padding", "0 3px"),
  ("border", border borderColor),
  ("borderRadius", "3px"),
  ("background", codeBackground),
  ("color", foreground),
  ("font", "inherit"),
  ("fontSize", "0.76rem"),
  ("fontWeight", "760"),
  ("cursor", "pointer")
]

public def goalContent : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "2px"),
  ("minWidth", "0"),
  ("padding", "1px 5px 4px")
]

public def contextSection (persistent : Bool) : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "0"),
  ("minWidth", "0"),
  ("paddingLeft", "4px"),
  ("borderLeft", "2px solid " ++ if persistent then persistentAccent else spatialAccent)
]

public def hypothesisList : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "1px"),
  ("margin", "0"),
  ("padding", "0"),
  ("listStyle", "none")
]

public def hypothesis : Props.Entry := style #[
  ("display", "grid"),
  ("gridTemplateColumns", "minmax(min-content, auto) minmax(0, 1fr)"),
  ("alignItems", "baseline"),
  ("gap", "2px 5px"),
  ("minWidth", "0"),
  ("padding", "0 2px")
]

public def hypothesisName : Props.Entry := style #[
  ("minWidth", "0"),
  ("fontFamily", editorFont),
  ("fontSize", "0.74rem"),
  ("fontWeight", "760"),
  ("overflowWrap", "anywhere")
]

public def interactiveTerm : Props.Entry := style #[
  ("display", "grid"),
  ("gap", "1px"),
  ("minWidth", "0")
]

public def termButton (target : Bool) : Props.Entry := style #[
  ("minWidth", "0"),
  ("padding", "0"),
  ("border", "0"),
  ("borderBottom", "1px dotted " ++ muted),
  ("background", "transparent"),
  ("color", if target then targetAccent else foreground),
  ("fontFamily", editorFont),
  ("fontSize", if target then "0.76rem" else "0.75rem"),
  ("fontWeight", "400"),
  ("lineHeight", "1.3"),
  ("textAlign", "left"),
  ("whiteSpace", "pre-wrap"),
  ("overflowWrap", "anywhere"),
  ("cursor", "pointer")
]

public def termDetails : Props.Entry := style #[
  ("minWidth", "0"),
  ("color", muted),
  ("fontFamily", editorFont),
  ("fontSize", "0.65rem"),
  ("lineHeight", "1.25"),
  ("whiteSpace", "pre-wrap"),
  ("overflowWrap", "anywhere")
]

public def termCode (target : Bool) : Props.Entry := style #[
  ("minWidth", "0"),
  ("fontFamily", editorFont),
  ("fontSize", if target then "0.76rem" else "0.75rem"),
  ("lineHeight", "1.3"),
  ("whiteSpace", "pre-wrap"),
  ("overflowWrap", "anywhere"),
  ("color", if target then targetAccent else foreground)
]

public def targetSection : Props.Entry := style #[
  ("display", "grid"),
  ("minWidth", "0"),
  ("marginTop", "1px"),
  ("paddingTop", "3px"),
  ("borderTop", "1px solid " ++ targetAccent)
]

public def target : Props.Entry := style #[
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

public def glyph : Props.Entry := style #[
  ("display", "inline-block"),
  ("minWidth", "1em"),
  ("fontFamily", editorFont),
  ("fontWeight", "800")
]

end Iris.ProofMode.Widget.Style
