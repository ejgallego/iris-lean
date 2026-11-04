import * as React from "react";
import { createRoot } from "react-dom/client";
import { RpcSessions, Widget_getWidgets } from "@leanprover/infoview-api";
import VirInfoviewWidget from "../Iris/.lake/packages/lean_vir/web/app/vir-infoview-widget.js";
import { until, withCleanup } from "../Iris/.lake/packages/lean_vir/tests/infoview/rpc-test-support.js";

const check = (condition, message) => { if (!condition) throw new Error(message); };
const post = async (path, body) => {
  const response = await fetch(path, { method: "POST", body: JSON.stringify(body) });
  const value = await response.json(); if (value.error) throw value.error; return value.result;
};
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.irisAcceptance = run().then(value => ({ ok: true, value }), error => {
  globalThis.irisFailure = String(error?.stack ?? JSON.stringify(error) ?? error);
  return { ok: false, error: globalThis.irisFailure };
});

async function run() {
  const config = await (await fetch("/config")).json();
  const container = document.getElementById("app"), errors = [], notifications = new Set(), gates = [];
  const keyWarnings = [], originalConsoleError = console.error;
  console.error = (...args) => {
    const message = args.map(String).join(" ");
    if (/unique.*key|same key/i.test(message)) keyWarnings.push(message);
    originalConsoleError(...args);
  };
  const recordError = event => errors.push(String(event.error ?? event.reason ?? event.message));
  addEventListener("error", recordError); addEventListener("unhandledrejection", recordError);
  const notify = (path, body) => {
    const task = post(path, body).catch(error => errors.push(String(error.message ?? error)));
    notifications.add(task); void task.then(() => notifications.delete(task));
  };
  const calls = [];
  let nextGate, rejectNext = false, sessions, root, nextId = 0, waitNext = false,
    failState = false, malformedState = false, injectedError;
  const arm = (method, position) => {
    const gate = { method, position, ...Promise.withResolvers(), received: false, finished: false };
    gates.push(gate); nextGate = gate; return gate;
  };
  const tick = () => React.act(async () => { await new Promise(resolve => setTimeout(resolve, 10)); });
  const waitFor = async (label, predicate) => { try { await until(label, async () => {
    await tick();
    if (errors.length) throw new Error(errors.join("\n"));
    const error = container.querySelector('[data-vir-infoview-state="error"], [role="alert"]');
    if (error) throw new Error(error.textContent);
    return predicate();
  }); } catch (error) { throw new Error(`${error.message}\nDOM: ${container.textContent}\nCalls: ${JSON.stringify(calls.map(call => ({ method: call.method, reference: call.params?.reference, error: call.testError })))}`); } };
  const release = async gate => {
    await React.act(async () => { gate.resolve(); });
    await waitFor("held response observed", () => gate.finished);
  };
  const prefix = "Iris.ProofMode.Widget.";
  const target = () => container.querySelector('section[aria-label="Target"]');
  const button = text => [...(target()?.querySelectorAll("button[data-term-ref]") ?? [])].find(button => button.textContent === text);
  const detail = () => target()?.querySelector('[role="status"]')?.textContent ?? "";
  const click = async button => { check(button, "missing term button"); await React.act(async () => button.click()); };
  return withCleanup(async () => {
    sessions = new RpcSessions({
      async createRpcSession() { return (await post("/connect", {})).sessionId; },
      closeRpcSession(sessionId) { notify("/close", { sessionId }); },
      release(params) { notify("/release", params); },
      async call(params, options) {
        const id = ++nextId;
        const record = { ...params, id, hasSignal: Boolean(options?.abortSignal), cancelled: false };
        const cancel = () => { record.cancelled = true; notify("/cancel", { id }); };
        options?.abortSignal?.addEventListener("abort", cancel, { once: true });
        if (options?.abortSignal?.aborted) cancel();
        const gate = nextGate?.method === params.method && (!nextGate.position ||
          (nextGate.position.line === params.position.line && nextGate.position.character === params.position.character)) ? nextGate : null;
        if (gate) nextGate = null;
        // Deliberate server-side failure injection, not a fabricated Promise rejection.
        if (rejectNext && params.method === prefix + "inspect") {
          rejectNext = false; params = { ...params, params: { ...params.params, reference: 999999 } };
        }
        if (waitNext && params.method === prefix + "inspect") {
          waitNext = false; params = { ...params, method: "IrisTest.ProofMode.WidgetRpc.waitForCancellation" };
          record.probe = true;
        }
        if (failState && params.method === prefix + "state") {
          failState = false; params = { ...params, method: prefix + "missingStateForTest" };
        }
        calls.push(record);
        try {
          // Transport/decoding failures are deliberately injected at the native client boundary.
          if (injectedError && params.method === prefix + "inspect") {
            const error = injectedError.value; injectedError = undefined; throw error;
          }
          let result = await post("/call", { id, params });
          if (malformedState && params.method === prefix + "state") {
            malformedState = false; result = { ...result, display: null };
          }
          if (params.method === "Lean.Vir.Infoview.buildIRPackage" && config.packageDelayMs > 0) {
            await new Promise(resolve => setTimeout(resolve, config.packageDelayMs));
          }
          return result;
        }
        catch (error) { record.testError = error; throw error; }
        finally {
          if (gate) { gate.received = true; await gate.promise; gate.finished = true; }
          record.settled = true;
          options?.abortSignal?.removeEventListener("abort", cancel);
        }
      },
    });
    const sessionAt = position => sessions.connect({ textDocument: { uri: config.uri }, position }, config.capabilities);
    root = createRoot(container, { onUncaughtError: error => errors.push(String(error.stack ?? error)) });
    const mount = async (position, invalidFingerprint = false) => {
      globalThis.irisSession = sessionAt(position);
      const result = await Widget_getWidgets(globalThis.irisSession, position);
      const props = result.widgets.find(widget => widget.props.irPackage?.entry === prefix + "createComponent")?.props;
      check(props?.irPackage.fingerprint, "server must supply the generated package fingerprint");
      await React.act(async () => root.render(React.createElement(React.StrictMode, null,
        React.createElement(VirInfoviewWidget, {
          ...props,
          irPackage: invalidFingerprint ? { ...props.irPackage, fingerprint: "unavailable-test-generation" } : props.irPackage,
          pos: { uri: config.uri, ...position },
        }))));
    };
    await mount(config.contexts);
    await waitFor("typed Iris contexts", () => button("P") && button("R"));
    const packageCalls = () => calls.filter(call => call.method === "Lean.Vir.Infoview.buildIRPackage").length;
    const packagesAtStartup = packageCalls();
    check(container.querySelectorAll("article").length === 1, "one initial goal");
    const snapshot = await sessionAt(config.contexts).call(prefix + "state", { pos: config.contexts });
    const payload = JSON.parse(snapshot.display);
    check(payload.version === 3 && payload.goals.length === 1, "versioned typed native snapshot");
    check(target().querySelector("[data-term-id]").textContent === payload.goals[0].target.text,
      "tag rendering preserves canonical Lean text");
    check(!container.querySelector("button button"), "semantic buttons must not nest");
    check(document.documentElement.scrollWidth <= innerWidth, "narrow layout overflow");
    check(parseFloat(getComputedStyle(button("P")).fontSize) === config.fontSize,
      "proof terms must respect the editor font-size setting");
    button("P").focus(); globalThis.irisPhase = "keyboard";
    await waitFor("native Enter activation inspects P", () => detail().includes("P : PROP"));

    const oldSelection = arm(prefix + "inspect");
    await click(button("R")); await waitFor("actual R reply held", () => oldSelection.received);
    await click(button("S")); await waitFor("new S inspection", () => detail().includes("S : PROP"));
    check(calls.some(call => call.method === prefix + "inspect" && call.cancelled && !call.settled),
      "reselection must abort the old inspection even when its response has already arrived");
    await release(oldSelection); check(detail().includes("S : PROP"), "late R replaced selected S");

    rejectNext = true;
    await click(button("P")); await waitFor("visible server rejection", () => detail().includes("Inspection unavailable"));
    check(detail().includes("No such expression in this Iris snapshot") && detail().includes("-32602"),
      `lost server RPC diagnostics: ${detail()}`);
    const oldFailure = arm(prefix + "inspect"); rejectNext = true;
    await click(button("R")); await waitFor("actual failure held", () => oldFailure.received);
    await click(button("S")); await waitFor("S after failure", () => detail().includes("S : PROP"));
    await release(oldFailure); check(detail().includes("S : PROP"), "late failure replaced selected S");

    for (const [reference, error, expected] of [
      ["P", Object.assign(new Error("Transport offline in test"), { code: "OFFLINE" }), "Transport offline in test (OFFLINE)"],
      ["R", "Disconnected transport", "Disconnected transport"],
      ["S", null, "Unknown RPC error"],
      ["P", undefined, "Unknown RPC error"],
      ["R", {}, "Unknown RPC error"],
    ]) {
      injectedError = { value: error };
      await click(button(reference));
      await waitFor("readable native rejection", () => detail().includes(expected));
      check(!detail().includes("[object Object]"), "object rejection leaked into the UI");
    }

    // A test-only server method remains active until Lean observes $/cancelRequest.
    const counts = async () => {
      try { return await sessionAt(config.contexts).call("IrisTest.ProofMode.WidgetRpc.counts", {}); }
      catch (error) { throw new Error(`cancellation probe counts: ${JSON.stringify(error)}`); }
    };
    const beforeCancellation = await counts();
    waitNext = true;
    await click(button("P"));
    await waitFor("server cancellation probe started", async () => (await counts())[0] > beforeCancellation[0]);
    const cancelledRequest = calls.findLast(call => call.probe);
    check(cancelledRequest.hasSignal, "inspection must pass a native AbortSignal");
    await click(button("S"));
    await waitFor("replacement after cancellation", () => detail().includes("S : PROP"));
    await waitFor("Lean observed cancellation", async () => (await counts())[1] > beforeCancellation[1]);
    await waitFor("cancelled request settled", () => cancelledRequest.settled);
    check(cancelledRequest.cancelled && cancelledRequest.testError?.code === -32800,
      `server cancellation did not settle as RequestCancelled: ${JSON.stringify(cancelledRequest)}`);

    const beforeClose = await counts();
    waitNext = true;
    await click(button("R"));
    await waitFor("close probe started", async () => (await counts())[0] > beforeClose[0]);
    await click(target().querySelector('button[aria-label="Close term inspection"]'));
    await waitFor("closing cancels in Lean", async () => (await counts())[1] > beforeClose[1]);
    check(!target().querySelector('[role="status"]'), "closing must hide the pending inspector");

    failState = true;
    await mount(config.binders);
    await until("readable snapshot failure", async () => {
      await tick(); return container.querySelector('[role="alert"]')?.textContent.includes("-32601");
    });
    check(container.textContent.includes("missingStateForTest"), "snapshot failure lost method diagnostics");
    malformedState = true;
    await mount(config.contexts);
    await until("fulfillment handler error is visible", async () => {
      await tick(); return container.querySelector('[role="alert"]')?.textContent.includes("Iris snapshot unavailable");
    });
    check(!container.textContent.includes("Unknown RPC error") && !container.textContent.includes("[object Object]"),
      "decoding exception must retain its native message");

    const oldSnapshot = arm(prefix + "state");
    await mount(config.binders); await waitFor("old snapshot reply held", () => oldSnapshot.received);
    await mount(config.split); await waitFor("split goals", () => container.querySelectorAll("article").length === 2);
    check(calls.some(call => call.method === prefix + "state" && call.cancelled && !call.settled),
      "navigation must abort the obsolete snapshot request");
    await release(oldSnapshot); check(container.querySelectorAll("article").length === 2, "late snapshot replaced split goals");
    check(!container.querySelector('[role="status"]'), "split retained old term selection");
    const second = container.querySelectorAll("article")[1];
    await click(second.querySelector('button[aria-expanded="false"]'));
    check(second.querySelector('section[aria-label="Target"]'), "second goal expands independently");
    const ids = [...container.querySelectorAll("[id]")].map(node => node.id);
    check(new Set(ids).size === ids.length, `duplicate DOM IDs across goals: ${ids.filter((id, i) => ids.indexOf(id) !== i)}`);
    await click([...second.querySelectorAll('section[aria-label="Target"] button[data-term-ref]')]
      .find(button => button.textContent === "R"));
    await waitFor("second goal reference belongs to this snapshot", () =>
      second.querySelector('[role="status"]')?.textContent.includes("R : PROP"));
    const sharedHypotheses = [...container.querySelectorAll('section[aria-label="Persistent"] button[data-term-ref]')]
      .filter(button => button.textContent === "P");
    check(sharedHypotheses.length === 2, "P is shared by both persistent contexts");
    for (const hypothesis of sharedHypotheses) {
      await click(hypothesis);
      await waitFor("shared hypothesis inspection", () =>
        document.getElementById(hypothesis.getAttribute("aria-controls"))?.textContent.includes("P : PROP"));
      const panel = document.getElementById(hypothesis.getAttribute("aria-controls"));
      check(hypothesis.closest("article") === panel.closest("article"), "aria-controls crossed goal boundaries");
    }
    const panels = sharedHypotheses.map(button => document.getElementById(button.getAttribute("aria-controls")));
    await click(panels[1].querySelector('button[aria-label="Close term inspection"]'));
    check(!panels[1].isConnected && panels[0].isConnected, "closing one occurrence closed another goal's inspection");

    await mount(config.binders); await waitFor("nested binders", () => button("n") && button("m"));
    await click(button("n")); await waitFor("saved n context", () => detail().includes("n : Nat"));
    await click(button("m")); await waitFor("saved m context", () => detail().includes("m : Nat"));
    const ns = [...target().querySelectorAll("button[data-term-ref]")].filter(button => button.textContent === "n");
    check(ns.length >= 2 && new Set(ns.map(button => button.dataset.termRef)).size === ns.length,
      "repeated names need separate occurrence references");
    const oldTerm = arm(prefix + "inspect");
    await click(button("n")); await waitFor("binder reply held", () => oldTerm.received);
    await mount(config.contexts); await waitFor("new context snapshot", () => button("P") && !button("n"));
    await click(button("P")); await waitFor("new snapshot inspection", () => detail().includes("P : PROP"));
    await release(oldTerm); check(detail().includes("P : PROP"), "old binder leaked into a new snapshot");

    // Continuity uses one mounted panel and real position-specific RPC sessions.
    await mount(config.split);
    await waitFor("split before continuity edit", () => container.querySelectorAll("article").length === 2 &&
      !container.querySelector('[aria-busy="true"]'));
    const stableCards = [...container.querySelectorAll("article")];
    await click(stableCards[0].querySelector('header button'));
    await click(stableCards[1].querySelector('header button'));
    const idsAt = () => [...container.querySelectorAll("article")].map(card => card.dataset.goalId);
    const identity = { initial: idsAt() }, focus = {};
    const checkPresentation = label => {
      check(stableCards.every(card => card.isConnected), `${label}: cards remounted; IDs=${JSON.stringify(identity)}`);
      check(stableCards[0].querySelector('header button').getAttribute('aria-expanded') === "false" &&
        stableCards[1].querySelector('header button').getAttribute('aria-expanded') === "true", `${label}: collapse was lost`);
    };
    const cursor = { line: config.split.line - 1, character: 4 };
    check(sessionAt(cursor) !== sessionAt(config.split), "cursor move must change the native position session");
    const toggle = stableCards[1].querySelector('header button');
    toggle.focus();
    for (const position of [cursor, config.split]) {
      const heldCursor = arm(prefix + "state", position);
      await mount(position);
      await waitFor("cursor reply held", () => heldCursor.received);
      checkPresentation("pending cursor move");
      await release(heldCursor);
      await waitFor("cursor reply committed", () => !container.querySelector('[aria-busy="true"]'));
      identity.cursor = idsAt();
      checkPresentation("cursor move and return");
      check(document.activeElement === toggle, "cursor movement lost presentation-control focus");
    }
    const staleButton = [...stableCards[1].querySelectorAll('[data-term-ref]')].find(b => b.textContent === "S");
    check(staleButton, "expanded second goal has a semantic action");
    staleButton.focus(); focus.beforeRefresh = document.activeElement === staleButton;
    const heightBeforeRefresh = container.getBoundingClientRect().height;
    const statesBeforeEdit = calls.filter(call => call.method === prefix + "state").length;
    const heldRefresh = arm(prefix + "state");
    let typingCursor;
    await React.act(async () => {
      const change = await post("/edit", {});
      typingCursor = change.cursor;
      for (const handler of [...globalThis.irisNotificationHandlers]) handler(change);
    });
    await waitFor("refresh held with old goals", () => heldRefresh.received && container.querySelector('[aria-busy="true"]'));
    checkPresentation("held same-position edit");
    focus.duringRefresh = document.activeElement === staleButton;
    check(!container.querySelector('[role="status"]'), "routine refresh inserted a live announcement");
    check(container.getBoundingClientRect().height === heightBeforeRefresh, "pending refresh shifted the panel layout");
    check(staleButton.isConnected && staleButton.disabled, "stale term must remain visible and disabled");
    const inspectionsBeforeStaleClick = calls.filter(call => call.method === prefix + "inspect").length;
    await click(staleButton);
    check(calls.filter(call => call.method === prefix + "inspect").length === inspectionsBeforeStaleClick,
      "stale activation sent an inspection RPC");
    await release(heldRefresh);
    await waitFor("same-position proof edit", () => container.textContent.includes("T") && !container.querySelector('[aria-busy="true"]'));
    identity.rename = idsAt();
    checkPresentation("same-position edit");
    focus.afterRefresh = document.activeElement === staleButton;
    check(!staleButton.isConnected, "new snapshot reused old semantic components");
    check(calls.filter(call => call.method === prefix + "state").length > statesBeforeEdit,
      "document edit must request a new snapshot");
    check(packageCalls() === packagesAtStartup, "context changes must reuse the fingerprinted package");

    // Typing moves the cursor; allocating an ordinary local forces re-elaboration too.
    // Both edits preserve the Iris goal count but may change metavariable names.
    await mount(typingCursor);
    await waitFor("cursor at comment end before typing", () => !container.querySelector('[aria-busy="true"]'));
    checkPresentation("cursor before typing");
    for (const kind of ["type", "allocate"]) {
      const oldIds = idsAt();
      const change = await post("/edit", { kind });
      check(change.cursor.line === typingCursor.line && change.cursor.character === typingCursor.character + 1,
        "typing must advance the cursor by one character on the same line");
      typingCursor = change.cursor;
      check(sessionAt(change.cursor) !== globalThis.irisSession, "edit also changes cursor/session");
      const heldEdit = arm(prefix + "state", change.cursor);
      toggle.focus();
      await React.act(async () => {
        for (const handler of [...globalThis.irisNotificationHandlers]) handler(change);
        await mount(change.cursor);
      });
      await waitFor("edited cursor response held", () => heldEdit.received);
      checkPresentation(`pending ${kind}`);
      const stale = [...stableCards[1].querySelectorAll('[data-term-ref]')];
      check(stale.every(button => button.disabled), "edit/cursor move left stale actions enabled");
      const before = calls.filter(call => call.method === prefix + "inspect").length;
      await click(stale[0]);
      check(calls.filter(call => call.method === prefix + "inspect").length === before, "edited stale action sent RPC");
      await release(heldEdit);
      await waitFor("edited cursor committed", () => !container.querySelector('[aria-busy="true"]'));
      identity[kind] = { before: oldIds, after: idsAt(), cursor: change.cursor };
      checkPresentation(`edit and cursor move (${kind})`);
      check(document.activeElement === toggle, "edit/cursor move lost presentation-control focus");
      check(stale.every(button => !button.isConnected), "new snapshot retained semantic nodes");
    }
    check(identity.allocate.before.some((id, index) => id !== identity.allocate.after[index]),
      "the real re-elaboration fixture must exercise changed goal IDs");

    // Failed refresh keeps readable, disabled old goals; another update can recover.
    failState = true;
    await mount(config.split);
    await until("refresh failure with retained goals", async () => {
      await tick(); return container.querySelector('[role="alert"]')?.textContent.includes("-32601");
    });
    check(stableCards.every(card => card.isConnected), "refresh failure removed previous goals");
    check([...container.querySelectorAll('[data-term-ref]')].every(b => b.disabled), "failed refresh left live semantic actions");
    await mount(config.split);
    await waitFor("refresh recovery", () => !container.querySelector('[aria-busy="true"]') &&
      [...container.querySelectorAll('[data-term-ref]')].some(b => !b.disabled));
    check(stableCards[0].querySelector('header button').getAttribute('aria-expanded') === "false", "recovery lost collapse");

    // A surviving goal keeps its card when a preceding goal is solved: ID matches beat ordinals.
    await mount({ line: config.split.line + 1, character: config.split.character });
    await waitFor("first goal solved", () => !container.querySelector('[aria-busy="true"]') && container.querySelectorAll("article").length === 1);
    check(container.querySelector("article") === stableCards[1], "surviving goal lost its card when its ordinal changed");
    check(stableCards[1].querySelector('header button').getAttribute('aria-expanded') === "true", "surviving goal lost collapse state");

    const leaveIris = arm(prefix + "state");
    await mount(config.ordinary);
    await waitFor("outside-Iris response held", () => leaveIris.received);
    check(stableCards[1].isConnected, "navigation cleared goals before receiving its result");
    await release(leaveIris);
    await waitFor("outside-Iris clears old goals", () => !container.querySelector('[data-iris-proof-mode-widget]'));
    await mount(config.contexts);
    await waitFor("return from empty state starts presentation", () => button("R") && button("T") && !button("R").disabled);

    const afterUnmount = arm(prefix + "inspect"); rejectNext = true;
    await click(button("R")); await waitFor("unmount failure held", () => afterUnmount.received);
    await React.act(async () => root.render(null));
    check(calls.some(call => call.method === prefix + "inspect" && call.cancelled && !call.settled),
      "unmount must abort the outstanding inspection");
    await release(afterUnmount); check(container.textContent === "", "late reply resurrected unmounted widget");
    await mount(config.ordinary);
    await waitFor("empty outside Iris", () => container.querySelector('[data-vir-infoview-state="ready"]') &&
      !container.textContent.includes("Loading") && !container.querySelector("[data-iris-proof-mode-widget]"));

    // Real HeapLang program: store, load, then discharge the framed postcondition.
    // Compare the UI to typed snapshots and check the resource change independently.
    for (const [position, storedValue, hasWp] of [
      [config.heapStore, "v", true], [config.heapLoad, "v'", true], [config.heapPost, "v'", false],
    ]) {
      await mount(position);
      const snapshot = await sessionAt(position).call(prefix + "state", { pos: position });
      const { goals } = JSON.parse(snapshot.display);
      check(goals.length === 1 && goals[0].persistent.length === 0, "one spatial HeapLang goal");
      const goal = goals[0], resources = new Map(goal.spatial.map(h => [h.name, h.proposition.text]));
      check(resources.size === 2 && resources.get("Hl") === `l ↦ some ${storedValue}` &&
        resources.get("Hframe") === "l' ↦ some w", "store updates exactly its owned cell");
      check(goal.target.text.startsWith("WP ") === hasWp, "load reaches the postcondition");
      if (!hasWp) check(goal.target.text.includes("⌜v' = v'⌝"), "read returns the stored value");
      await waitFor("canonical HeapLang target", () =>
        target()?.querySelector("[data-term-id]")?.textContent === goal.target.text);
      for (const hypothesis of goal.spatial) {
        const rendered = [...container.querySelectorAll('section[aria-label="Spatial"] [data-term-id]')]
          .find(node => node.dataset.termId === hypothesis.proposition.id);
        check(rendered?.textContent === hypothesis.proposition.text,
          "rendered spatial resource matches the typed snapshot");
      }
      check(document.documentElement.scrollWidth <= innerWidth, "HeapLang notation overflows the panel");
      const inspect = async (name, type) => {
        await click(button(name));
        await waitFor(`contextual HeapLang ${name}`, () => detail().includes(`${name} : ${type}`));
      };
      await inspect("l", "Loc");
      if (hasWp) {
        await inspect("E", "CoPset");
        await inspect("r", "Val");
      } else await inspect("v'", "Val");
    }
    // Complete SpinLock.release_spec: open invariant, ghost resources, store and restore.
    for (const [position, stored] of [[config.spinOpen, false], [config.spinStored, true]]) {
      await mount(position);
      const snapshot = await sessionAt(position).call(prefix + "state", { pos: position });
      const { goals } = JSON.parse(snapshot.display);
      check(goals.length === 1, "one SpinLock goal");
      const goal = goals[0], spatial = new Map(goal.spatial.map(h => [h.name, h.proposition.text]));
      check(goal.persistent.length === 1 && goal.persistent[0].name === "Hinv" &&
        goal.persistent[0].proposition.text.startsWith("inv spinlockN"), "persistent lock invariant");
      check(spatial.size === 5 && spatial.get("Hl") === "locked γ" && spatial.get("HR") === "R",
        "ghost token and protected resource survive the store");
      check(spatial.get("Hpt") === (stored ? "l ↦ some hl_val(#false)" : "▷ l ↦ some hl_val(#b)"),
        "the atomic store consumes later and updates the lock cell");
      check(spatial.get("Hcond").startsWith(stored ? "if b" : "▷ if b"), "later is removed from the invariant condition");
      check(goal.target.text.startsWith(stored ? "|={" : "WP ") && goal.target.text.includes("spinlockN"),
        "reduced mask and invariant-closing update remain visible");
      await waitFor("canonical SpinLock target", () =>
        target()?.querySelector("[data-term-id]")?.textContent === goal.target.text);
      for (const [label, hypotheses] of [["Persistent", goal.persistent], ["Spatial", goal.spatial]]) {
        for (const hypothesis of hypotheses) {
          const rendered = [...container.querySelectorAll(`section[aria-label="${label}"] [data-term-id]`)]
            .find(node => node.dataset.termId === hypothesis.proposition.id);
          check(rendered?.textContent === hypothesis.proposition.text, "canonical SpinLock resource");
        }
      }
      check(document.documentElement.scrollWidth <= innerWidth, "SpinLock notation overflows the panel");
      for (const [name, type] of [["l", "Loc"], ["γ", "GName"], ["b", "Bool"]]) {
        await click(button(name));
        await waitFor(`contextual SpinLock ${name}`, () => detail().includes(`${name} : ${type}`));
      }
    }
    // A genuine package RPC failure must keep its message through the shell UI.
    await mount(config.contexts, true);
    await until("readable package failure", async () => {
      await tick();
      return container.querySelector('[data-vir-infoview-state="error"]');
    });
    check(container.textContent.includes("fingerprint is unavailable") && container.textContent.includes("-32602") &&
      !container.textContent.includes("[object Object]"), `lost native package error: ${container.textContent}`);
    check(errors.length === 0, `uncaught browser failures: ${errors.join("\n")}`);
    check(keyWarnings.length === 0, `React key warnings: ${keyWarnings.join("\n")}`);
    return { requests: calls.length, width: innerWidth, fontSize: config.fontSize, theme: config.theme, continuity: { identity, focus },
      cases: ["editor font size", "native keyboard", "canonical text", "contextual subterms",
      "nested binders", "repeated occurrences", "server rejection", "stale selection success/failure", "stale snapshot",
      "goal split", "unique DOM IDs", "shared hypothesis ARIA/close isolation", "late unmount failure",
      "same-position proof edit", "package reuse", "empty outside Iris", "readable package RPC error", "React Strict Mode",
      "retained goals during refresh", "disabled stale actions", "collapse continuity", "refresh failure/recovery", "cursor move and return", "typing with cursor movement", "goal ID churn", "surviving goal reordered",
      "native RPC diagnostics", "snapshot/decoding errors", "server-observed cancellation", "no React key warnings",
      "HeapLang store/load", "framed ownership preserved", "postcondition binder inspection", "HeapLang narrow layout",
      "SpinLock invariant/ghost state", "SpinLock store and closing update", "SpinLock contextual inspection/layout",
      ...(config.packageDelayMs > 0 ? ["slow package startup"] : [])] };
  }, [
    ["gates", () => { for (const gate of gates) gate.resolve(); }],
    ["root", () => root && React.act(async () => root.unmount())],
    ["sessions", () => sessions?.dispose()],
    ["notifications", () => Promise.all(notifications)],
    ["console", () => { console.error = originalConsoleError; }],
    ["errors", () => { removeEventListener("error", recordError); removeEventListener("unhandledrejection", recordError);
      check(errors.length === 0, `browser or cleanup failure: ${errors.join("\n")}`); }],
  ]);
}
