import { createHost, check, post, pause, until } from "./widget-infoview-host.mjs";

const prefix = "Iris.ProofMode.Widget.";
let actionId = 0;
async function action(kind, element) {
  element?.scrollIntoView({ block: "center" });
  let rect = element?.getBoundingClientRect();
  if (kind === "click" && element) {
    const text = document.createTreeWalker(element, NodeFilter.SHOW_TEXT).nextNode();
    const range = document.createRange(); range.selectNodeContents(text);
    rect = range.getClientRects()[0];
  }
  const id = ++actionId;
  globalThis.irisAction = { id, kind, x: rect ? rect.x + (kind === "click" ? Math.min(5, rect.width / 2) : rect.width / 2) : 0,
    y: rect ? rect.y + rect.height / 2 : 0 };
  await until("browser input", () => globalThis.irisActionDone === id);
}
run().then(value => { globalThis.irisResult = { ok: true, value }; }, error => {
  globalThis.irisResult = { ok: false, error: String(error.stack ?? error) };
});
async function run() {
  const config = await (await fetch("/config")).json();
  const container = document.getElementById("app"), gates = [], warnings = [];
  const originalError = console.error;
  console.error = (...args) => { warnings.push(args.map(String).join(" ")); originalError(...args); };
  let host, failure, malformed = false, waitNext = false, invalidFingerprint = false;
  const arm = (method = prefix + "state", position) => {
    const gate = { method, position, ...Promise.withResolvers(), count: 0, finished: 0, open: true };
    gates.push(gate); return gate;
  };
  const release = async gate => { gate.open = false; gate.resolve(); await until("released replies", () => gate.finished === gate.count); };
  const panel = () => host.panel();
  const cards = () => [...(panel()?.querySelectorAll("article") ?? [])];
  const ready = () => panel()?.querySelector('[data-vir-infoview-state="ready"]') && !panel().querySelector('[aria-busy="true"]');
  const native = () => [...(panel()?.querySelectorAll('[data-has-tooltip-on-hover]') ?? [])];
  const leaf = (name, parent = panel()) => [...(parent?.querySelectorAll('[data-has-tooltip-on-hover]') ?? [])]
    .find(node => node.textContent === name && !node.querySelector('[data-has-tooltip-on-hover]'));
  const target = () => panel()?.querySelector('section[aria-label="Target"] [data-term-id]');
  const semanticCalls = () => host.calls.filter(c => /infoToInteractive|getGoToLocation/.test(c.method));
  const wait = async (label, predicate) => until(label, async () => {
    check(!host.errors.length, host.errors.join("\n"));
    return await predicate();
  });
  const move = async position => {
    const before = host.calls.length;
    await host.move(position);
    await wait("new position ready", () => ready() && host.calls.slice(before).some(c => c.method === prefix + "state" && c.settled));
  };
  const hover = async (name, expected, parent = panel()) => {
    await action("move"); await pause(150);
    const node = leaf(name, parent); check(node, `missing native ${name}`);
    await action("move", node);
    await wait(`native hover ${name} : ${expected}`, () => [...document.querySelectorAll('.tooltip')]
      .some(p => p.textContent.includes(expected)));
    await action("move"); await pause(150);
  };
  try {
    host = await createHost(container, config, {
      panelProps: props => invalidFingerprint ? { ...props, irPackage: { ...props.irPackage, fingerprint: "unavailable-test-generation" } } : props,
      async intercept(params, options, send, record) {
        const gate = gates.find(g => g.open && g.method === params.method && (!g.position ||
          g.position.line === params.position.line && g.position.character === params.position.character));
        try {
          if (params.method === prefix + "state" && waitNext) {
            waitNext = false; record.probe = true;
            return await send({ ...params, method: "IrisTest.ProofMode.WidgetRpc.waitForCancellation" });
          }
          if (params.method === prefix + "state" && failure) {
            const error = failure;
            if (error.server) return await send({ ...params, method: prefix + "missingStateForTest" });
            throw error.value;
          }
          let result = await send();
          if (params.method === prefix + "state" && malformed) {
            result = { ...result, display: null };
          }
          return result;
        } finally {
          if (gate) { gate.count++; await gate.promise; gate.finished++; }
        }
      },
    });
    await move(config.contexts);
    check(cards().length === 1 && native().length > 0, "one native Iris goal");
    check([...panel().querySelectorAll('li[role="listitem"]')].every(row =>
      row.firstElementChild.textContent.endsWith(": ")), "hypothesis separator matches irisHyp");
    const packageCalls = () => host.calls.filter(c => c.method === "Lean.Vir.Infoview.buildIRPackage").length;
    const startupPackages = packageCalls();
    const snapshot = await host.snapshot(config.contexts), payload = JSON.parse(snapshot.display);
    check(payload.version === 5 && snapshot.codes.length > 0, "versioned native terms");
    check(target().textContent === payload.goals[0].target.text, "canonical native target");
    check(payload.goals[0].comparison.branches.length === 2, "branching tactic retains both outcomes");
    check(panel().querySelectorAll('[data-after-goal-id]').length === 2, "both outcomes rendered");
    check(!panel().querySelector('[data-term-ref]'), "retired per-leaf buttons");
    check(!panel().querySelector('section[aria-label="Target"] button'), "no inline inspector");
    check(parseFloat(getComputedStyle(leaf("P")).fontSize) === config.fontSize, "editor font size");
    await hover("P", "PROP");
    // The collapse control remains keyboard-operable; native term keyboard policy is deferred.
    const firstToggle = cards()[0].querySelector('header button'); firstToggle.focus();
    await action("key"); await wait("Enter collapses goal", () => firstToggle.getAttribute("aria-expanded") === "false");
    await action("key"); await wait("Enter expands goal", () => firstToggle.getAttribute("aria-expanded") === "true");
    await move(config.binders); await hover("n", "Nat"); await hover("m", "Nat");

    // A fresh snapshot avoids the native popup's already-loaded hover cache.
    await move(config.contexts); await move(config.binders);
    // A native popup in flight is retired with its owning snapshot.
    const popup = arm("Lean.Widget.InteractiveDiagnostics.infoToInteractive");
    await action("move", leaf("m"));
    await wait("native popup response held", () => popup.count > 0);
    const popupCall = host.calls.findLast(c => c.method === popup.method);
    await host.move(config.contexts);
    await wait("retired native popup cancelled", () => popupCall.cancelled);
    await action("move"); await release(popup);
    await wait("new state after popup retirement", ready);
    check(!document.querySelector('.tooltip-code-content'), "late popup resurrected retired term");

    // One mounted panel: real cursor sessions, document notifications, and re-elaboration.
    await move(config.split);
    const stable = cards(); check(stable.length === 2, "split goals");
    stable[0].querySelector('header button').click(); stable[1].querySelector('header button').click();
    const toggle = stable[1].querySelector('header button');
    await wait("split disclosure changes", () => stable[0].querySelector('header button').getAttribute("aria-expanded") === "false" &&
      toggle.getAttribute("aria-expanded") === "true");
    const ids = () => cards().map(c => c.dataset.goalId);
    const identity = { initial: ids() };
    const presentation = label => {
      check(stable.every(c => c.isConnected), `${label}: card identity`);
      check(stable[0].querySelector('header button').getAttribute('aria-expanded') === "false" &&
        toggle.getAttribute('aria-expanded') === "true", `${label}: collapse state`);
    };
    const assertStale = async old => {
      check(native().length === 0, "stale snapshot still has native handlers");
      check(panel().querySelector('[data-term-active="false"]'), "old canonical text remains visible");
      check(!panel().querySelector('[role="status"]'), "refresh must not insert a live status line");
      const count = semanticCalls().length;
      old?.dispatchEvent(new MouseEvent("click", { bubbles: true, ctrlKey: true }));
      await action("move", target()); await pause(150);
      check(semanticCalls().length === count, "stale activation sent semantic RPC");
    };
    for (const position of [{ line: config.split.line - 1, character: 4 }, config.split]) {
      const old = native()[0], gate = arm(prefix + "state", position);
      const height = panel().getBoundingClientRect().height;
      toggle.focus(); await host.move(position);
      await wait("cursor response held", () => gate.count > 0);
      presentation("pending cursor"); await assertStale(old);
      check(panel().getBoundingClientRect().height === height, `refresh shifted Iris panel height: ${height} → ${panel().getBoundingClientRect().height}`);
      await release(gate); await wait("cursor committed", ready);
      presentation("cursor move and return");
      check(document.activeElement === toggle, "cursor lost collapse-control focus");
    }
    identity.cursor = ids();
    let typingCursor;
    for (const kind of ["rename", "type", "allocate"]) {
      const before = ids(), old = native()[0], gate = arm();
      toggle.focus();
      const change = await post("/edit", { kind });
      if (kind !== "rename") check(change.cursor.character === typingCursor.character + 1, "typing advances cursor");
      typingCursor = change.cursor;
      await host.edit(change);
      if (kind !== "rename") await host.move(change.cursor);
      await wait(`held ${kind}`, () => gate.count > 0);
      presentation(`pending ${kind}`); await assertStale(old);
      await release(gate); await wait(`committed ${kind}`, ready);
      presentation(`committed ${kind}`);
      check(document.activeElement === toggle, "typing lost collapse-control focus");
      check(!old.isConnected, "new snapshot retained semantic DOM");
      identity[kind] = { before, after: ids(), cursor: change.cursor };
      if (kind === "rename") {
        check(panel().textContent.includes("T"), "edited proposition visible");
        await move(typingCursor); presentation("cursor before typing");
      }
    }
    check(packageCalls() === startupPackages, "proof updates must reuse the fingerprinted package");
    check(identity.allocate.before.some((id, i) => id !== identity.allocate.after[i]), "fixture exercises changed goal IDs");
    failure = { server: true }; await host.move(config.split);
    await wait("failed refresh", () => panel()?.querySelector('[role="alert"]')?.textContent.includes("-32601"));
    presentation("failed refresh"); await assertStale();
    failure = undefined;
    await move({ line: config.split.line - 1, character: 4 });
    presentation("recovery");
    await move({ line: config.split.line + 1, character: config.split.character });
    check(cards().length === 1 && cards()[0] === stable[1], "surviving goal keeps its card when ordinal changes");
    const leave = arm(); await host.move(config.ordinary);
    await wait("outside-Iris held", () => leave.count > 0);
    check(stable[1].isConnected, "leaving keeps old goals until reply");
    await release(leave); await wait("outside-Iris empty", () => ready() && cards().length === 0);

    // Late successes and failures cannot replace a newer snapshot.
    for (const failed of [false, true]) {
      const gate = arm(prefix + "state", config.binders);
      if (failed) failure = { server: true };
      await host.move(config.binders); await wait("obsolete reply held", () => gate.count > 0);
      failure = undefined;
      await move(config.contexts); await release(gate);
      check(target().textContent.includes("T") && !target().textContent.includes("∀"), "late response replaced current goals");
    }
    for (const [value, expected] of [[new Error("Transport offline"), "Transport offline"], ["Disconnected", "Disconnected"],
      [null, "Unknown RPC error"], [undefined, "Unknown RPC error"], [{}, "Unknown RPC error"]]) {
      failure = { value }; await host.move(config.binders);
      await wait("readable RPC rejection", () => panel()?.querySelector('[role="alert"]')?.textContent.includes(expected));
      check(!panel().textContent.includes("[object Object]"), "opaque object error");
      failure = undefined;
      await move(config.contexts);
    }
    malformed = true; await host.move(config.binders);
    await wait("decode exception", () => panel()?.querySelector('[role="alert"]'));
    malformed = false;
    await move(config.contexts);
    // Actual server-observed cancellation, through the production state request.
    waitNext = true; await host.move(config.binders);
    await wait("cancellation probe called", () => host.calls.some(c => c.probe));
    await pause(100); await move(config.contexts);
    const probe = host.calls.find(c => c.probe);
    await wait("cancellation reached Lean", () => probe.settled);
    check(probe.hasSignal && probe.cancelled && probe.error?.code === -32800, "server must settle RequestCancelled");

    const assertChanges = (goal, expected, tactic) => {
      const comparison = goal.comparison;
      check(comparison && comparison.tactic === tactic && !comparison.unavailable && !comparison.closed, `selected tactic comparison for ${tactic}: ${JSON.stringify(comparison)}`);
      check(comparison.branches.length === 1 && !comparison.branches[0].unavailable, "one sound successor");
      const changes = comparison.branches[0].resources;
      check(changes.length === Object.keys(expected).length, "all resources accounted for");
      for (const [name, status] of Object.entries(expected)) {
        const change = changes.find(c => c.name === name);
        check(change?.status === status, `${tactic}: ${name} should be ${status}`);
        const row = panel().querySelector(`[data-resource-name="${name}"][data-resource-status="${status}"]`);
        check(row, `${name} status rendered`);
        if (status === "changed") check(row.textContent.includes("was: " + change.before) &&
          row.querySelector('[data-term-id]').textContent === change.after.text, "both proposition sides rendered");
      }
    };
    const corpus = [];
    for (const [name, value, wp] of [["heapStore", "v", true], ["heapLoad", "v'", true], ["heapPost", "v'", false]]) {
      await move(config[name]);
      const { goals } = JSON.parse((await host.snapshot(config[name])).display), goal = goals[0];
      const resources = new Map(goal.spatial.map(h => [h.name, h.proposition.text]));
      check(goals.length === 1 && goal.persistent.length === 0 && resources.size === 2, "two Heap resources");
      check(resources.get("Hl") === `l ↦ some ${value}` && resources.get("Hframe") === "l' ↦ some w", "store changes owned cell, preserves frame");
      check(goal.target.text.startsWith("WP ") === wp, "load reaches postcondition");
      check(target().textContent === goal.target.text, "canonical Heap target");
      for (const hyp of goal.spatial) check([...panel().querySelectorAll('[data-term-id]')]
        .some(n => n.dataset.termId === hyp.proposition.id && n.textContent === hyp.proposition.text), "canonical Heap resource");
      await hover("l", "Loc"); if (wp) { await hover("E", "CoPset"); await hover("r", "Val"); }
      if (name === "heapStore" || name === "heapLoad") {
        assertChanges(goal, { Hframe: "preserved", Hl: name === "heapStore" ? "changed" : "preserved" },
          name === "heapStore" ? "wp_store" : "wp_load");
      }
      if (name === "heapStore") {
        await hover("v'", "Val", panel().querySelector('[data-resource-name="Hl"]'));
        // Native navigation is tested at EditorApi.showDocument; VS Code opens the file in the maintainer check.
        const some = native().find(node => node.textContent.startsWith("some ")); check(some, "native constant tag");
        await action("click", some); await wait("go to definition", () => host.navigations.length > 0);
        check(host.navigations.at(-1).uri.endsWith("/Init/Prelude.lean"), "some navigates to Prelude");
      }
      corpus.push({ name, tags: native().length, termButtons: panel().querySelectorAll('[data-term-id] button').length,
        goal, overflow: panel().scrollWidth > panel().clientWidth });
    }
    for (const [name, stored] of [["spinOpen", false], ["spinStored", true]]) {
      await move(config[name]);
      const { goals } = JSON.parse((await host.snapshot(config[name])).display), goal = goals[0];
      const resources = new Map(goal.spatial.map(h => [h.name, h.proposition.text]));
      check(goal.persistent.length === 1 && goal.persistent[0].name === "Hinv", "persistent invariant");
      check(resources.size === 5 && resources.get("Hl") === "locked γ" && resources.get("HR") === "R", "ghost token and resource");
      check(resources.get("Hpt") === (stored ? "l ↦ some hl_val(#false)" : "▷ l ↦ some hl_val(#b)"), "lock cell and later");
      check(resources.get("Hcond").startsWith(stored ? "if b" : "▷ if b"), "invariant condition loses later");
      check(goal.target.text.startsWith(stored ? "|={" : "WP ") && goal.target.text.includes("spinlockN"), "invariant-closing target");
      check(target().textContent === goal.target.text, "canonical SpinLock target");
      for (const hyp of [...goal.persistent, ...goal.spatial]) check([...panel().querySelectorAll('[data-term-id]')]
        .some(n => n.dataset.termId === hyp.proposition.id && n.textContent === hyp.proposition.text), "canonical SpinLock resource");
      assertChanges(goal, { Hl: "preserved", HR: "preserved", Hcont: "preserved", Hinv: "preserved",
        Hcond: stored ? "preserved" : "changed", Hpt: stored ? "preserved" : "changed" }, stored ? "imodintro" : "wp_store");
      await hover("l", "Loc"); await hover("γ", "GName"); await hover("b", "Bool");
      corpus.push({ name, tags: native().length, termButtons: panel().querySelectorAll('[data-term-id] button').length,
        goal, overflow: panel().scrollWidth > panel().clientWidth });
    }
    await move(config.spinFrame);
    const framed = JSON.parse((await host.snapshot(config.spinFrame)).display).goals[0];
    assertChanges(framed, { Hl: "preserved", HR: "preserved", Hcont: "preserved", Hinv: "preserved",
      Hcond: "preserved", Hpt: "removed" }, "iframe Hpt");
    await move({ line: config.heapStore.line - 1, character: 4 });
    check(!panel().querySelector('[data-before-goal-id]'), "comment outside tactic has the ordinary view");
    // Inside the selected tactic, Lean uses its after-state. Keep the whole
    // before-goal group rather than silently choosing one resulting goal.
    await move({ ...config.contexts, character: config.contexts.character + 1 });
    check(cards().length === 2 && panel().querySelectorAll('[data-after-goal-id]').length === 2,
      "after-side split retains both descendants");
    await move({ ...config.split, character: config.split.character + 3 });
    check(panel().querySelector('[data-comparison-outcome="closed"]') &&
      !panel().querySelector('[data-resource-status="removed"]'), "closed goal is not resource consumption");
    check(corpus.every(c => !c.overflow && c.termButtons === 0), "native terms overflow or create Tab-stop buttons");
    invalidFingerprint = true;
    await host.move(config.contexts);
    await wait("package failure", () => panel()?.querySelector('[data-vir-infoview-state="error"]'));
    check(panel().textContent.includes("fingerprint is unavailable") && panel().textContent.includes("-32602") &&
      !panel().textContent.includes("[object Object]"), `package failure lost diagnostics: ${panel().textContent}`);
    invalidFingerprint = false;
    await move(config.heapStore);
    globalThis.irisCapture = true; await until("screenshot", () => globalThis.irisCaptured);
    // Unmount cancels a pending state call; a late error cannot revive the panel.
    const unmount = arm(prefix + "state", config.binders); failure = { server: true };
    await host.move(config.binders); await wait("unmount response held", () => unmount.count > 0);
    const close = host.close(); await release(unmount); await close;
    check(container.textContent === "", "late response resurrected unmounted panel");
    check(!warnings.some(w => /unique.*key|same key/i.test(w)), `React key warning: ${warnings.join("\n")}`);
    return { continuity: identity, corpus, calls: host.calls.length, navigation: host.navigations,
      warnings, knownGaps: ["enclosing-subterm selection", "native term keyboard policy"] };
  } finally {
    gates.forEach(g => { g.open = false; g.resolve(); });
    await host?.close(); console.error = originalError;
  }
}
