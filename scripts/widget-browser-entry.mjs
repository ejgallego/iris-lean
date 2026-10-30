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
      async call(params, options) {
        const id = ++nextId;
        const record = { ...params, id, hasSignal: Boolean(options?.abortSignal), cancelled: false };
        const cancel = () => { record.cancelled = true; notify("/cancel", { id }); };
        options?.abortSignal?.addEventListener("abort", cancel, { once: true });
        if (options?.abortSignal?.aborted) cancel();
        const gate = nextGate?.method === params.method ? nextGate : null;
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

    // An edit at the same cursor must refresh the snapshot without rebuilding code.
    const statesBeforeEdit = calls.filter(call => call.method === prefix + "state").length;
    await React.act(async () => {
      const change = await post("/edit", {});
      for (const handler of [...globalThis.irisNotificationHandlers]) handler(change);
    });
    await waitFor("same-position proof edit", () => button("T") && !button("S"));
    check(calls.filter(call => call.method === prefix + "state").length > statesBeforeEdit,
      "document edit must request a new snapshot");
    check(packageCalls() === packagesAtStartup, "context changes must reuse the fingerprinted package");

    const afterUnmount = arm(prefix + "inspect"); rejectNext = true;
    await click(button("R")); await waitFor("unmount failure held", () => afterUnmount.received);
    await React.act(async () => root.render(null));
    check(calls.some(call => call.method === prefix + "inspect" && call.cancelled && !call.settled),
      "unmount must abort the outstanding inspection");
    await release(afterUnmount); check(container.textContent === "", "late reply resurrected unmounted widget");
    await mount(config.ordinary);
    await waitFor("empty outside Iris", () => container.querySelector('[data-vir-infoview-state="ready"]') &&
      !container.textContent.includes("Loading") && !container.querySelector("[data-iris-proof-mode-widget]"));
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
    return { requests: calls.length, width: innerWidth, fontSize: config.fontSize, theme: config.theme,
      cases: ["editor font size", "native keyboard", "canonical text", "contextual subterms",
      "nested binders", "repeated occurrences", "server rejection", "stale selection success/failure", "stale snapshot",
      "goal split", "unique DOM IDs", "shared hypothesis ARIA/close isolation", "late unmount failure",
      "same-position proof edit", "package reuse", "empty outside Iris", "readable package RPC error", "React Strict Mode",
      "native RPC diagnostics", "snapshot/decoding errors", "server-observed cancellation", "no React key warnings",
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
