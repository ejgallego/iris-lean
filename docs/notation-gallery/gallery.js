// Disposable, offline design renderer. Production projection and UI remain Lean/VIR.
"use strict";
const byId = id => document.getElementById(id);
const mathNS = "http://www.w3.org/1998/Math/MathML";
let specimenIndex = 0;
let stateIndex = 0;
let selected = null;
let expandedGoals = [true];
const specimen = () => irisSpecimens[specimenIndex];
const state = () => specimen().states[stateIndex];
const element = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

function mathNode(tree) {
  const node = document.createElementNS(mathNS, tree.kind);
  if (tree.text !== undefined) node.textContent = tree.text;
  if (tree.width) node.setAttribute("width", tree.width);
  if (tree.spaced) {
    node.setAttribute("lspace", "0.25em");
    node.setAttribute("rspace", "0.25em");
  }
  if (tree.className) node.setAttribute("class", tree.className);
  if (tree.part) {
    node.dataset.part = tree.part;
    node.setAttribute("title", state().parts[tree.part].label);
  }
  for (const child of tree.children ?? []) node.append(mathNode(child));
  return node;
}

function formula(fragments) {
  const container = element("div", "formula");
  for (const fragment of fragments) {
    const wrapper = element("span", "math-fragment");
    const math = document.createElementNS(mathNS, "math");
    math.append(mathNode(fragment));
    wrapper.append(math);
    container.append(wrapper);
  }
  return container;
}

function context(kind, hypotheses) {
  const container = element("div", "context");
  container.append(element("div", "context-label", `${kind} · ${hypotheses.length}`));
  for (const hyp of hypotheses) {
    const line = element("div", "hyp");
    line.append(element("span", "hyp-name", hyp.name), formula(hyp.body));
    container.append(line);
  }
  if (!hypotheses.length) container.append(element("span", "muted", "empty"));
  return container;
}

function renderPreview() {
  const preview = byId("preview");
  preview.replaceChildren();
  if (byId("notation").value === "text") {
    preview.append(element("pre", "", state().source));
  } else if (state().goals) {
    state().goals.forEach((goal, index) => {
      const container = element(state().goals.length > 1 ? "details" : "div", "goal");
      if (state().goals.length > 1) {
        container.open = expandedGoals[index] ?? false;
        container.append(element("summary", "", `Goal ${index + 1} · □ ${goal.persistent.length} · ∗ ${goal.spatial.length}`));
      }
      const target = element("div", "conclusion");
      target.append(element("span", "", "⊢"), formula(goal.target));
      container.append(context("□ Persistent", goal.persistent), context("∗ Spatial", goal.spatial), target);
      preview.append(container);
    });
  } else {
    preview.append(formula(state().formula));
  }
  highlight(selected);
}

function highlight(part) {
  document.querySelectorAll("#preview [data-part]").forEach(node => {
    node.classList.toggle("highlight", node.dataset.part === part);
  });
}

function selectPart(part) {
  selected = part;
  const annotation = state().parts[part];
  byId("inspection").textContent = annotation
    ? `${annotation.label} — source fragment: ${annotation.text}. ${annotation.note} [Design annotation; no live reference.]`
    : "No part selected. These annotations describe intended interactions, not Lean server results.";
  document.querySelectorAll("#parts button").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.part === part));
  });
  // A keyboard proxy may address a term in a collapsed goal.
  document.querySelectorAll("#preview [data-part]").forEach(node => {
    if (node.dataset.part === part) {
      const goal = node.closest("details");
      if (goal) goal.open = true;
    }
  });
  highlight(part);
}

function renderState() {
  selected = null; // Mock step changes invalidate selection; no invented snapshot continuity.
  expandedGoals = [true];
  byId("steps").replaceChildren();
  if (specimen().states.length > 1) specimen().states.forEach((step, index) => {
    const button = element("button", "", step.label);
    button.type = "button";
    button.setAttribute("aria-pressed", String(index === stateIndex));
    button.addEventListener("click", () => { stateIndex = index; renderState(); byId("steps").children[index].focus(); });
    byId("steps").append(button);
  });
  byId("source-text").value = state().source;
  byId("source-text").rows = Math.min(10, Math.max(3, state().source.split("\n").length));
  byId("copy-status").textContent = "";
  byId("parts").replaceChildren();
  for (const [part, annotation] of Object.entries(state().parts)) {
    const button = element("button", "", annotation.label);
    button.type = "button";
    button.dataset.part = part;
    button.addEventListener("click", () => selectPart(part));
    button.addEventListener("focus", () => highlight(part));
    button.addEventListener("blur", () => highlight(selected));
    byId("parts").append(button);
  }
  renderPreview();
  selectPart(null);
}

function renderSpecimen() {
  byId("specimen-title").textContent = specimen().title;
  byId("question").textContent = specimen().question;
  byId("provenance").textContent = specimen().provenance;
  byId("review").textContent = specimen().review;
  byId("source-title").textContent = specimen().sourceLabel;
  byId("sources").replaceChildren();
  for (const source of specimen().sources) {
    const li = element("li");
    const a = element("a", "", source.label);
    a.href = source.url;
    li.append(a);
    byId("sources").append(li);
  }
  [...byId("specimens").children].forEach((button, index) => button.setAttribute("aria-current", String(index === specimenIndex)));
  stateIndex = 0;
  renderState();
}

irisSpecimens.forEach((item, index) => {
  const button = element("button", "", item.short);
  button.type = "button";
  button.append(element("small", "", item.subtitle));
  button.addEventListener("click", () => { specimenIndex = index; renderSpecimen(); });
  byId("specimens").append(button);
});
byId("width").addEventListener("change", event => {
  byId("preview").style.width = event.target.value === "wide" ? "100%" : `${event.target.value}px`;
});
byId("theme").addEventListener("change", event => { document.body.dataset.theme = event.target.value; });
byId("notation").addEventListener("change", () => {
  const goals = [...document.querySelectorAll("#preview details")];
  if (goals.length) expandedGoals = goals.map(goal => goal.open);
  renderPreview();
});
byId("preview").addEventListener("click", event => {
  const part = event.target.closest("[data-part]");
  if (part) selectPart(part.dataset.part);
});
byId("preview").addEventListener("pointerover", event => highlight(event.target.closest("[data-part]")?.dataset.part ?? selected));
byId("preview").addEventListener("pointerleave", () => highlight(selected));
document.addEventListener("keydown", event => { if (event.key === "Escape") selectPart(null); });
byId("copy").addEventListener("click", async () => {
  const source = byId("source-text").value;
  try {
    await navigator.clipboard.writeText(source);
    byId("copy-status").textContent = "Copied source text (not the typeset display).";
  } catch {
    byId("source-text").focus();
    byId("source-text").select();
    byId("copy-status").textContent = "Clipboard unavailable; source selected. Press Ctrl/Cmd+C to copy.";
  }
});
renderSpecimen();
