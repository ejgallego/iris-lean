// Demo controls only. The proof UI below is the production Lean-authored VIR widget.
import * as React from "react";
import { createRoot } from "react-dom/client";
import { createHost } from "./widget-infoview-host.mjs";

const h = React.createElement;
const config = await (await fetch("/config")).json();
const positions = [
  ["heapStore", "Heap · 1. Before store", "Write v' to l, then read it back. Hl owns the cell being updated; Hframe owns a second cell that must survive unchanged. Hover over l, E, or the bound return value r."],
  ["heapLoad", "Heap · 2. After store", "wp_store changed Hl from l ↦ some v to l ↦ some v'. Hframe still owns l' ↦ some w. The remaining program reads l."],
  ["heapPost", "Heap · 3. After load", "The read returned v'. The target now asserts that result and ownership of both cells. iframe and itrivial finish the proof."],
  ["spinOpen", "SpinLock · 1. Open invariant", "Inside release_spec: Hinv is persistent. Hpt owns the lock cell, Hcond records its old state, and Hl/HR supply the ghost token and protected resource. The target stores false under a reduced mask."],
  ["spinStored", "SpinLock · 2. After store", "Hpt now owns the unlocked cell. The target restores the invariant and mask before returning to the caller's continuation; Hl and HR are needed to close the invariant."],
  ["spinFrame", "SpinLock · 3. Frame the cell", "At iframe Hpt: the after-view lists Hpt as removed from this goal. This describes the context change, not a claim that the cell was consumed."],
  ["tourHow", "Tour · How VIR is used", "The tour and proof view are Lean-authored VIR components."],
  ["tourFeedback", "Tour · Feedback", "The final tour step contains the questions for the Iris authors."],
  ["contexts", "Contexts", "Two persistent resources, two spatial resources, and the target."],
  ["split", "Split goals", "Expand the second goal. Hover over the shared P in each goal independently."],
  ["binders", "Nested binders", "Hover over n and m before introduction; their types come from saved binder contexts."],
  ["ordinary", "Ordinary Lean", "Outside Iris proof mode, the Iris widget renders nothing."],
];
const themeVariables = {
  light: { "editor-background": "#ffffff", "editor-foreground": "#24292f", descriptionForeground: "#57606a", "panel-border": "#d0d7de", "textCodeBlock-background": "#f6f8fa", "textLink-foreground": "#0969da", "editorWarning-foreground": "#9a6700", "symbolIcon-keywordForeground": "#8250df" },
  dark: { "editor-background": "#1f1f1f", "editor-foreground": "#cccccc", descriptionForeground: "#aaaaaa", "panel-border": "#555555", "textCodeBlock-background": "#292929", "textLink-foreground": "#4daafc", "editorWarning-foreground": "#d7ba7d", "symbolIcon-keywordForeground": "#c586c0" },
  contrast: { "editor-background": "#000000", "editor-foreground": "#ffffff", descriptionForeground: "#ffffff", "panel-border": "#ffffff", "textCodeBlock-background": "#000000", "textLink-foreground": "#6fc3df", "editorWarning-foreground": "#ffff00", "symbolIcon-keywordForeground": "#ffffff" },
};
const style = document.createElement("style");
style.textContent = `
  * { box-sizing: border-box; }
  body { margin:0; font:14px/1.5 system-ui,sans-serif; }
  main { max-width:1120px; margin:0 auto; padding:24px; }
  h1 { margin:0; font-size:24px; font-weight:650; }
  .intro { color:var(--vscode-descriptionForeground); margin:6px 0 20px; }
  .toolbar { display:flex; flex-wrap:wrap; gap:16px; align-items:end; margin:20px 0; }
  label { display:grid; gap:4px; font-size:12px; font-weight:600; }
  select { padding:7px; font:inherit; color:inherit; background:var(--vscode-editor-background); border:1px solid var(--vscode-panel-border); border-radius:4px; }
  input { accent-color:var(--vscode-textLink-foreground); }
  .workspace { display:grid; grid-template-columns:minmax(0,1fr) minmax(280px,1fr); gap:24px; align-items:start; }
  .preview { width:min(100%,var(--preview-width)); min-height:190px; }
  h2 { margin:0 0 12px; font-size:13px; font-weight:600; color:var(--vscode-descriptionForeground); }
  .source { min-width:0; }
  pre { position:relative; margin:0; padding:12px; background:var(--vscode-textCodeBlock-background); border:1px solid var(--vscode-panel-border); border-radius:4px; font:12px/1.6 ui-monospace,monospace; overflow:auto; max-height:560px; }
  .line { display:block; white-space:pre; }
  .line.current { background:var(--vscode-textCodeBlock-background); outline:1px solid var(--vscode-textLink-foreground); }
  .number { display:inline-block; width:3ch; margin-right:12px; color:var(--vscode-descriptionForeground); user-select:none; }
  .empty { color:var(--vscode-descriptionForeground); border:1px dashed var(--vscode-panel-border); padding:16px; }
  .hint { margin-top:16px; max-width:65ch; color:var(--vscode-descriptionForeground); font-size:13px; }
  :focus-visible { outline:2px solid var(--vscode-textLink-foreground); outline-offset:2px; }
  @media (max-width:760px) { main { padding:16px; } .workspace { grid-template-columns:minmax(0,1fr); } }
`;
document.head.append(style);
document.title = "Iris proof-mode widget · live demo";

function Demo() {
  const [selected, setSelected] = React.useState("heapStore");
  const [theme, setTheme] = React.useState("light");
  const [fontSize, setFontSize] = React.useState(16);
  const [width, setWidth] = React.useState(420);
  const hostRef = React.useRef(null);
  const mountRef = React.useRef(null);
  const [error, setError] = React.useState(null);
  const sourceRef = React.useRef(null);
  const position = config[selected];

  React.useEffect(() => {
    for (const [name, value] of Object.entries(themeVariables[theme]))
      document.documentElement.style.setProperty(`--vscode-${name}`, value);
    document.documentElement.style.setProperty("--vscode-editor-font-size", `${fontSize}px`);
  }, [theme, fontSize]);
  React.useEffect(() => {
    const pending = createHost(mountRef.current, config, { onReveal: position => {
      const step = positions.find(([name]) => config[name].line === position.line && config[name].character === position.character);
      if (step) setSelected(step[0]);
    } });
    hostRef.current = pending;
    pending.catch(error => setError(error.message ?? String(error)));
    return () => { void pending.then(host => host.close()); };
  }, []);
  React.useEffect(() => {
    void hostRef.current.then(host => host.move(position)).catch(error => setError(error.message ?? String(error)));
  }, [position]);
  React.useEffect(() => {
    const pre = sourceRef.current, line = pre?.querySelector(".current");
    if (line) pre.scrollTop = line.offsetTop - pre.clientHeight / 2;
  }, [selected]);
  const [, label, description] = positions.find(([key]) => key === selected);
  return h("main", null,
    h("h1", null, "Iris proof mode"),
    h("p", { className: "intro" }, "Live Lean goals beside the normal Tactic state. Hover over a term for its native type information; Ctrl/Cmd-click a constant for navigation."),
    h("div", { className: "toolbar" },
      h("label", null, "Proof position", h("select", { value: selected, onChange: event => setSelected(event.target.value) },
        positions.map(([value, label]) => h("option", { key: value, value }, label)))),
      h("label", null, "Theme", h("select", { value: theme, onChange: event => setTheme(event.target.value) },
        [["light", "Light"], ["dark", "Dark"], ["contrast", "High contrast"]].map(([value, label]) => h("option", { key: value, value }, label)))),
      h("label", null, `Proof text · ${fontSize}px`, h("input", { type: "range", min: 12, max: 28, value: fontSize, onChange: event => setFontSize(Number(event.target.value)) })),
      h("label", null, `Panel · ${width}px`, h("input", { type: "range", min: 280, max: 520, step: 20, value: width, onChange: event => setWidth(Number(event.target.value)) }))),
    h("div", { className: "workspace" },
      h("section", { "aria-label": "Live widget" },
        h("h2", null, label),
        h("div", { className: "preview", style: { "--preview-width": `${width}px` } },
          error && h("p", { role: "alert" }, error),
          h("div", { ref: mountRef }),
          selected === "ordinary" && h("p", { className: "empty" }, "This is an ordinary Lean goal. The Iris panel is intentionally empty.")),
        h("p", { className: "hint" }, description)),
      h("section", { className: "source", "aria-label": "Lean source" },
        h("h2", null, `WidgetDemo.lean · line ${position.line + 1}`),
        h("pre", { ref: sourceRef }, h("code", null, config.source.split("\n").map((line, index) =>
          h("span", { key: index, className: `line${index === position.line ? " current" : ""}` },
            h("span", { className: "number", "aria-hidden": true }, index + 1), line || " ")))))),
    h("p", { className: "hint" }, "The proof panel is authored in Lean and runs through VIR. This browser harness uses the real upstream infoview providers. Its navigation callback records a destination; opening that file is part of the VS Code check."));
}
createRoot(document.getElementById("app")).render(h(Demo));
