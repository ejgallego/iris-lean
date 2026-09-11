// Hand-authored DESIGN DATA. No parser, elaborator, RPC handles, or live goal snapshots.
// These small presentation helpers are illustrative, not the proposed wire format.
"use strict";
const token = (text, kind = "mi") => ({ kind, text });
const op = text => ({ ...token(text, "mo"), spaced: ["−∗", "++"].includes(text) });
const row = (...children) => ({ kind: "mrow", children });
const sub = (base, index) => ({ kind: "msub", children: [base, index] });
const sup = (base, index) => ({ kind: "msup", children: [base, index] });
const mark = (part, body) => ({ kind: "mrow", part, children: [body] });
const code = text => ({ kind: "mtext", text, className: "fallback" });
const name = text => token(text, "mtext");
const space = () => ({ kind: "mspace", width: "0.25em" });
const E = n => sub(token("E"), token(String(n), "mn"));
const fupd = (from, to, part) => sub(op("|⇛"), mark(part, row(E(from), op(","), E(to))));
const sep = (...names) => row(...names.flatMap((x, i) => i ? [op("∗"), token(x)] : [token(x)]));
const wand = row(token("Q"), op("−∗"), token("R"));
const paperGround = {
  label: "Jung et al. · Iris from the ground up · JFP 2018 · Fig. 15, p. 57 (historical Iris 3.1)",
  url: "https://cs.au.dk/~birke/papers/iris-journal.pdf#page=57",
};
const paperIPM = {
  label: "Krebbers, Timany & Birkedal · Interactive Proofs in Higher-Order Concurrent Separation Logic · POPL 2017 · §3, PDF p. 5",
  url: "https://iris-project.org/pdfs/2017-popl-proofmode-final.pdf#page=5",
};
const local = (label, path) => ({ label, url: `../../Iris/${path}` });
const persistent = () => [
  { name: "HP", body: [mark("hp", token("P"))] },
  { name: "HQR", body: [mark("hqr", wand)] },
];
const spatial = () => [
  { name: "HQ", body: [mark("hq", token("Q"))] },
  { name: "HS", body: [mark("hs", token("S"))] },
];
const judgmentParts = {
  hp: { label: "HP · P", text: "P", note: "Persistent hypothesis proposition. A future reference must retain its goal context; equal printed P elsewhere is not this occurrence." },
  hqr: { label: "HQR · Q −∗ R", text: "Q -∗ R", note: "Whole wand proposition. Domain extensions should also expose its domain and codomain as child occurrences." },
  hq: { label: "HQ · Q", text: "Q", note: "Spatial resource, allocated to the right-hand goal by isplitr [HQ HS]." },
  hs: { label: "HS · S", text: "S", note: "Spatial resource, allocated to the right-hand goal by isplitr [HQ HS]." },
  target: { label: "Target", text: "P ∗ R ∗ S", note: "Target occurrence, distinct from all hypothesis occurrences. The split changes the set of goals; do not transfer a selection by matching its text." },
};

const irisSpecimens = [
  {
    id: "judgment", title: "01 / A judgment in motion", short: "Two contexts", subtitle: "Local proof · two positions",
    question: "Can the resource split stay obvious without repeating a large goal header?",
    provenance: "Manual transcription of WidgetDemo after iintro and after its first isplitr. Not a captured RPC payload; the static step buttons do not execute tactics.",
    sources: [local("WidgetDemo.lean · unnamed BI example, after iintro / first isplitr", "IrisTest/ProofMode/WidgetDemo.lean"), paperIPM],
    review: "Review context order, empty spatial context, two independently collapsible goals, and selection invalidation. Repeated names in different goals must eventually get different occurrence references.",
    sourceLabel: "Lean proof-state notation · manually transcribed",
    states: [
      { label: "After iintro", source: "□ HP : P\n□ HQR : Q -∗ R\n∗ HQ : Q\n∗ HS : S\n⊢ P ∗ R ∗ S", parts: judgmentParts,
        goals: [{ persistent: persistent(), spatial: spatial(), target: [mark("target", sep("P", "R", "S"))] }] },
      { label: "After isplitr [HQ HS]", source: "-- Goal 1\n□ HP : P\n□ HQR : Q -∗ R\n⊢ P\n\n-- Goal 2\n□ HP : P\n□ HQR : Q -∗ R\n∗ HQ : Q\n∗ HS : S\n⊢ R ∗ S", parts: {
          ...judgmentParts,
          target: { label: "First target · P", text: "P", note: "New left-hand goal. This specimen clears selection on a step change; it makes no claim of stable snapshot references." },
          hp2: { ...judgmentParts.hp, label: "Goal 2 · HP" },
          hqr2: { ...judgmentParts.hqr, label: "Goal 2 · HQR" },
          target2: { label: "Second target · R ∗ S", text: "R ∗ S", note: "The remaining spatial resources belong to this goal. Its target has a separate occurrence identity." },
        }, goals: [
          { persistent: persistent(), spatial: [], target: [mark("target", token("P"))] },
          { persistent: [{ name: "HP", body: [mark("hp2", token("P"))] }, { name: "HQR", body: [mark("hqr2", wand)] }],
            spatial: spatial(), target: [mark("target2", sep("R", "S"))] },
        ] },
    ],
  },
  {
    id: "updates", title: "02 / Masks are arguments", short: "Indexed updates", subtitle: "Paper rule · local counterpart",
    question: "Can we read the mask transition without mistaking an index for decoration?",
    provenance: "Adapted FUP-TRANS from Fig. 15. Proposed notation puts the ordered mask pair beneath |⇛; it is not a facsimile of the paper. The corresponding theorem exists locally, but this view is manually authored.",
    sources: [paperGround, local("Iris.fupd_trans · Updates.lean", "Iris/BI/Updates.lean")],
    review: "Keep input/output mask order explicit. Break at the entailment boundary, never between an update operator and its mask pair. Inspecting two equal-looking E₂ occurrences must remain context-aware.",
    sourceLabel: "Lean statement fragment · manually transcribed",
    states: [{ label: "Transitivity", source: "(|={E1,E2}=> |={E2,E3}=> P) ⊢ |={E1,E3}=> P", parts: {
      outer: { label: "Outer masks · E₁, E₂", text: "E1, E2", note: "Future targets: the first two explicit arguments of the outer FUpd.fupd. The pair is a visual group; it is not itself one Lean expression." },
      inner: { label: "Inner masks · E₂, E₃", text: "E2, E3", note: "Future targets: the mask arguments of the nested FUpd.fupd, in this goal snapshot." },
      result: { label: "Result masks · E₁, E₃", text: "E1, E3", note: "Future targets: the right-hand modality's mask arguments. Retain separate references for the two arguments." },
      p: { label: "Nested P", text: "P", note: "The proposition argument of the inner update, not the right-hand occurrence of P." },
    }, formula: [row(fupd(1, 2, "outer"), fupd(2, 3, "inner"), mark("p", token("P"))), row(op("⊢"), fupd(1, 3, "result"), token("P"))] }],
  },
  {
    id: "invariant", title: "03 / A box with a scope", short: "Counter invariant", subtitle: "Local definition · paper styling",
    question: "Can a namespace, a binder, and an unfamiliar predicate coexist in a small panel?",
    provenance: "Paper-inspired invariant box around the local counterInv body, with a namespace superscript. The mathematical points-to n abbreviates Lean's explicit HeapLang value encoding; source text retains that encoding.",
    sources: [paperGround, local("Iris.HeapLang.Counter.counterInv · Counter.lean", "Iris/HeapLang/Lib/Counter.lean"), local("Iris.inv · Invariants.lean", "Iris/Instances/Lib/Invariants.lean")],
    review: "The box denotes inv N, not persistence or ordinary grouping. A n intentionally stays in source-style text to exercise a custom-predicate fallback. Do not silently hide the namespace or equate the Nat binder with a HeapLang value.",
    sourceLabel: "Lean expression · manually expanded counterInv body",
    states: [{ label: "Invariant body", source: "inv N (iprop(∃ n : Nat, A n ∗ l ↦ some hl_val(#n)))", parts: {
      namespace: { label: "Namespace · N", text: "N", note: "Future reference: the namespace argument of Iris.inv. Keep it visible and selectable even when typeset as a script." },
      binder: { label: "Binder · ∃ n : Nat", text: "∃ n : Nat", note: "A binder header is not an isolated expression. Inspection must retain the enclosing expression and binder context; its body uses the bound n." },
      custom: { label: "Fallback · A n", text: "A n", note: "Unknown user predicate: render tagged Lean text without guessing its meaning or parsing a custom syntax. This mock has no tags or server reference." },
      heap: { label: "Heap ownership · l ↦ n", text: "l ↦ some hl_val(#n)", note: "Proposed abbreviated mathematical view. Copying must preserve the explicit source value representation; the displayed n alone is not a faithful copy payload." },
    }, formula: [sup({ kind: "mrow", className: "invariant-box", children: [
      mark("binder", row(op("∃"), token("n"), op(":"), name("ℕ"), op("."))),
      mark("custom", code("A n")), op("∗"), mark("heap", row(token("l"), op("↦"), token("n"))),
    ] }, mark("namespace", token("N")))] }],
  },
  {
    id: "wp", title: "04 / A long induction hypothesis", short: "Binders & weakest preconditions", subtitle: "Paper-only · no Lean fixture yet",
    question: "Where should a long proposition break, and what exactly does a selected binder refer to?",
    provenance: "Adapted list-reversal induction hypothesis from the POPL 2017 proof-mode example. Names and punctuation are normalized for this study. This is paper pseudocode, not a claimed iris-lean port or a checked statement.",
    sources: [paperIPM, local("Iris.Wp · WeakestPre.lean (notation infrastructure only; not a rev proof)", "Iris/BI/WeakestPre.lean")],
    review: "Keep the scope of ▷ and ∀ explicit with parentheses. Wrap at wand and postcondition boundaries. The postcondition binder and body need contextual references, not matching by the printed name w. ReLoC atomic specifications remain a follow-up, not an implemented fixture.",
    sourceLabel: "Paper pseudocode · not Lean",
    states: [{ label: "Induction hypothesis", source: "▷ (∀ hd acc xs ys,\n  isList hd xs -∗ isList acc ys -∗\n  WP (rev hd acc) {{ w, isList w (reverse xs ++ ys) }})", parts: {
      binders: { label: "Quantified variables", text: "∀ hd acc xs ys", note: "Proposed binder-group interaction. The group has four distinct binders; a future renderer must expose them individually with their scopes and types." },
      xs: { label: "First list resource", text: "isList hd xs", note: "Paper predicate only. This assertion needs its own contextual subexpression reference once a real Lean counterpart is selected." },
      ys: { label: "Second list resource", text: "isList acc ys", note: "Separate resource occurrence, distinct from the first list assertion even though both use isList." },
      program: { label: "Program · rev hd acc", text: "rev hd acc", note: "Program expression inside WP. No local declaration or executable source link is asserted for this paper example." },
      postBinder: { label: "Result binder · w", text: "w", note: "Binder navigation must use the elaborator's contextual information, not a free-standing Expr with loose bound variables." },
      post: { label: "Postcondition body", text: "isList w (reverse xs ++ ys)", note: "One semantic body may occupy several layout fragments. All fragments must keep the same contextual target while retaining distinct display keys." },
    }, formula: [
      row(op("▷"), op("("), mark("binders", row(op("∀"), space(), name("hd acc xs ys"), op(".")))),
      row(mark("xs", name("isList hd xs")), op("−∗")),
      row(mark("ys", name("isList acc ys")), op("−∗")),
      row(name("WP"), op("("), mark("program", name("rev hd acc")), op(")")),
      row(op("{"), mark("postBinder", token("w")), op("."), mark("post", row(name("isList"), space(), token("w")))),
      row(mark("post", row(op("("), name("reverse xs"), op("++"), name("ys"), op(")"))), op("}"), op(")")),
    ] }],
  },
];
