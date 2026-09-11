import * as React from "react";
import { createRoot } from "react-dom/client";
import { RpcSessions } from "@leanprover/infoview-api";
import VirInfoviewWidget from "../Iris/.lake/packages/lean_vir/web/app/vir-infoview-widget.js";
import { until, withCleanup } from "../Iris/.lake/packages/lean_vir/tests/infoview/rpc-test-support.js";

const check = (condition, message) => { if (!condition) throw new Error(message); };
const post = async (path, body) => {
  const response = await fetch(path, { method: "POST", body: JSON.stringify(body) });
  const value = await response.json(); if (value.error) throw value.error; return value.result;
};
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.irisAcceptance = run().then(value => ({ ok: true, value }), error => {
  globalThis.irisFailure = String(error.stack ?? error);
  return { ok: false, error: globalThis.irisFailure };
});

async function run() {
  const config = await (await fetch("/config")).json();
  const container = document.getElementById("app"), errors = [], notifications = new Set(), gates = [];
  const recordError = event => errors.push(String(event.error ?? event.reason ?? event.message));
  addEventListener("error", recordError); addEventListener("unhandledrejection", recordError);
  const notify = (path, body) => {
    const task = post(path, body).catch(error => errors.push(String(error.message ?? error)));
    notifications.add(task); void task.then(() => notifications.delete(task));
  };
  const calls = [];
  let nextGate, rejectNext = false, sessions, root;
  const arm = method => {
    const gate = { method, ...Promise.withResolvers(), received: false, finished: false };
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
      async call(params) {
        const gate = nextGate?.method === params.method ? nextGate : null;
        if (gate) nextGate = null;
        // Deliberate server-side failure injection, not a fabricated Promise rejection.
        if (rejectNext && params.method === prefix + "inspect") {
          rejectNext = false; params = { ...params, params: { ...params.params, reference: 999999 } };
        }
        calls.push(params);
        try {
          const result = await post("/call", params);
          if (params.method === "Lean.Vir.Infoview.buildIRPackage" && config.packageDelayMs > 0) {
            await new Promise(resolve => setTimeout(resolve, config.packageDelayMs));
          }
          return result;
        }
        catch (error) { params.testError = error; throw error; }
        finally {
          if (gate) { gate.received = true; await gate.promise; gate.finished = true; }
        }
      },
    });
    const sessionAt = position => sessions.connect({ textDocument: { uri: config.uri }, position }, config.capabilities);
    root = createRoot(container, { onUncaughtError: error => errors.push(String(error.stack ?? error)) });
    const mount = async (position, roots = [prefix + "createComponent", prefix + "mount"]) => {
      globalThis.irisSession = sessionAt(position);
      await React.act(async () => root.render(React.createElement(React.StrictMode, null,
        React.createElement(VirInfoviewWidget, {
          wasmPath: ".lake/packages/lean_vir/web/public/vir-upstream.wasm",
          irPackage: { roots },
          componentEntry: prefix + "createComponent", entry: prefix + "mount",
          pos: { uri: config.uri, ...position }, autoReloadMs: config.autoReloadMs,
        }))));
    };
    await mount(config.contexts);
    await waitFor("typed Iris contexts", () => button("P") && button("R"));
    if (config.autoReloadMs > 0) {
      const stats = () => calls.filter(call => call.method === "Lean.Vir.Infoview.statIRPackage").length;
      const baseline = stats();
      await waitFor("editor auto-refresh polling", () => stats() >= baseline + 2);
    }
    check(container.querySelectorAll("article").length === 1, "one initial goal");
    const snapshot = await sessionAt(config.contexts).call(prefix + "state", { pos: config.contexts });
    const payload = JSON.parse(snapshot.display);
    check(payload.version === 3 && payload.goals.length === 1, "versioned typed native snapshot");
    check(target().querySelector("[data-term-id]").textContent === payload.goals[0].target.text,
      "tag rendering preserves canonical Lean text");
    check(!container.querySelector("button button"), "semantic buttons must not nest");
    check(document.documentElement.scrollWidth <= innerWidth, "360px layout overflow");
    button("P").focus(); globalThis.irisPhase = "keyboard";
    await waitFor("native Enter activation inspects P", () => detail().includes("P : PROP"));

    const oldSelection = arm(prefix + "inspect");
    await click(button("R")); await waitFor("actual R reply held", () => oldSelection.received);
    await click(button("S")); await waitFor("new S inspection", () => detail().includes("S : PROP"));
    await release(oldSelection); check(detail().includes("S : PROP"), "late R replaced selected S");

    rejectNext = true;
    await click(button("P")); await waitFor("visible server rejection", () => detail().includes("Inspection unavailable"));
    const oldFailure = arm(prefix + "inspect"); rejectNext = true;
    await click(button("R")); await waitFor("actual failure held", () => oldFailure.received);
    await click(button("S")); await waitFor("S after failure", () => detail().includes("S : PROP"));
    await release(oldFailure); check(detail().includes("S : PROP"), "late failure replaced selected S");

    const oldSnapshot = arm(prefix + "state");
    await mount(config.binders); await waitFor("old snapshot reply held", () => oldSnapshot.received);
    await mount(config.split); await waitFor("split goals", () => container.querySelectorAll("article").length === 2);
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

    const afterUnmount = arm(prefix + "inspect"); rejectNext = true;
    await click(button("R")); await waitFor("unmount failure held", () => afterUnmount.received);
    await React.act(async () => root.render(null));
    await release(afterUnmount); check(container.textContent === "", "late reply resurrected unmounted widget");
    await mount(config.ordinary);
    await waitFor("empty outside Iris", () => container.querySelector('[data-vir-infoview-state="ready"]') &&
      !container.textContent.includes("Loading") && !container.querySelector("#iris-proof-mode-widget"));
    // A genuine package RPC failure must keep its message through the shell UI.
    await mount(config.contexts, [prefix + "noSuchWidgetExport"]);
    await until("readable package failure", async () => {
      await tick();
      return container.querySelector('[data-vir-infoview-state="error"]');
    });
    check(container.textContent.includes("VIR IR package failed") && container.textContent.includes("-32602") &&
      !container.textContent.includes("[object Object]"), `lost native package error: ${container.textContent}`);
    check(errors.length === 0, `uncaught browser failures: ${errors.join("\n")}`);
    return { requests: calls.length, width: innerWidth, cases: ["native keyboard", "canonical text", "contextual subterms",
      "nested binders", "repeated occurrences", "server rejection", "stale selection success/failure", "stale snapshot",
      "goal split", "unique DOM IDs", "shared hypothesis ARIA/close isolation", "late unmount failure",
      "empty outside Iris", "readable package RPC error", "React Strict Mode",
      ...(config.autoReloadMs > 0 ? ["auto-refresh", "slow package startup"] : [])] };
  }, [
    ["gates", () => { for (const gate of gates) gate.resolve(); }],
    ["root", () => root && React.act(async () => root.unmount())],
    ["sessions", () => sessions?.dispose()],
    ["notifications", () => Promise.all(notifications)],
    ["errors", () => { removeEventListener("error", recordError); removeEventListener("unhandledrejection", recordError);
      check(errors.length === 0, `browser or cleanup failure: ${errors.join("\n")}`); }],
  ]);
}
