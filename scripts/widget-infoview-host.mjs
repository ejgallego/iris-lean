// Browser harness only: use upstream's real RPC, editor and position providers.
// Widget source loading substitutes the bundled VIR shell; the widget props,
// package, runtime, goals and native term RPCs still come from the Lean server.
import * as React from "react";
import { renderInfoview, defaultInfoviewConfig } from "@leanprover/infoview";
import VirInfoviewWidget from "../Iris/.lake/packages/lean_vir/web/app/vir-infoview-widget.js";
import { unmountInfoviewRoots } from "../Iris/.lake/packages/lean_vir/tests/infoview/react-dom-compat.js";

export const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
export const check = (ok, message) => { if (!ok) throw new Error(message); };
export async function post(path, body) {
  const reply = await (await fetch(path, { method: "POST", body: JSON.stringify(body) })).json();
  if (reply.error) throw reply.error;
  return reply.result;
}
export async function until(label, predicate) {
  const deadline = performance.now() + 20000;
  while (performance.now() < deadline) { if (await predicate()) return; await pause(10); }
  throw new Error(`${label}: timed out; DOM=${document.body.textContent.slice(-4000)}`);
}
export async function createHost(container, config, { intercept, panelProps = props => props } = {}) {
  const calls = [], navigations = [], errors = [], sessions = new Set(), notifications = new Set();
  const widgetHashes = new Set(), subscriptions = new Set();
  let requestId = 0;
  const report = event => errors.push(String(event.error?.stack ?? event.reason ?? event.message));
  addEventListener("error", report); addEventListener("unhandledrejection", report);
  const notify = (path, params) => {
    const task = post(path, params); notifications.add(task);
    void task.then(() => notifications.delete(task), error => { notifications.delete(task); errors.push(JSON.stringify(error)); });
    return task;
  };
  // Stable component identity: changing position does not unmount the panel.
  globalThis.irisHarnessPanel = props => React.createElement("div", { "data-iris-test-panel": true },
    React.createElement(VirInfoviewWidget, panelProps(props)));
  const call = async (params, options) => {
    const record = { ...params, id: ++requestId, hasSignal: Boolean(options?.abortSignal), cancelled: false };
    calls.push(record);
    const cancel = () => { record.cancelled = true; void notify("/cancel", { id: record.id }); };
    options?.abortSignal?.addEventListener("abort", cancel, { once: true });
    if (options?.abortSignal?.aborted) cancel();
    const send = async (next = params) => {
      if (next.method === "Lean.Widget.getWidgetSource" && widgetHashes.has(String(next.params.hash)))
        return { sourcetext: "export default globalThis.irisHarnessPanel;" };
      const value = await post("/call", { id: record.id, params: next });
      if (next.method === "Lean.Widget.getWidgets") {
        for (const widget of value.widgets)
          if (widget.props.irPackage?.entry === "Iris.ProofMode.Widget.createComponent") widgetHashes.add(String(widget.javascriptHash));
      }
      if (next.method === "Lean.Vir.Infoview.buildIRPackage" && config.packageDelayMs) await pause(config.packageDelayMs);
      return value;
    };
    try { return intercept ? await intercept(params, options, send, record) : await send(); }
    catch (error) { record.error = error; throw error; }
    finally { record.settled = true; options?.abortSignal?.removeEventListener("abort", cancel); }
  };
  const api = {
    async createRpcSession() { const { sessionId } = await post("/connect", {}); sessions.add(sessionId); return sessionId; },
    async closeRpcSession(sessionId) { sessions.delete(sessionId); await notify("/close", { sessionId }); },
    async sendClientRequest(_uri, method, params, options) {
      check(method === "$/lean/rpc/call", `unexpected LSP method ${method}`);
      return call(params, options);
    },
    async sendClientNotification(_uri, method, params) { if (method === "$/lean/rpc/release") await notify("/release", params); },
    async subscribeServerNotifications(method) { subscriptions.add(method); }, async unsubscribeServerNotifications() {},
    async subscribeClientNotifications() {}, async unsubscribeClientNotifications() {},
    async copyToClipboard() {}, async saveConfig() {}, async showDocument(params) { navigations.push(params); },
  };
  const infoview = renderInfoview(api, container);
  await until("infoview providers", () => subscriptions.has("$/lean/fileProgress"));
  await infoview.serverRestarted({ capabilities: config.capabilities, serverInfo: { name: "Lean", version: "4.35.0" } });
  await infoview.changedInfoviewConfig({ ...defaultInfoviewConfig, debounceTime: 0 });
  await infoview.initialize({ uri: config.uri, range: { start: config.ordinary, end: config.ordinary } });
  await until("initial ordinary goal", () => container.textContent.includes("Tactic state"));
  return {
    calls, navigations, errors, infoview,
    panel: () => container.querySelector('[data-iris-test-panel]'),
    async move(position) {
      await infoview.changedCursorLocation({ uri: config.uri, range: { start: position, end: position } });
    },
    async edit(change) { await infoview.sentClientNotification("textDocument/didChange", change); },
    async snapshot(position) {
      const { sessionId } = await post("/connect", {});
      try { return await post("/call", { id: ++requestId, params: { sessionId, textDocument: { uri: config.uri },
        position, method: "Iris.ProofMode.Widget.state", params: { pos: position } } }); }
      finally { await post("/close", { sessionId }); }
    },
    async close() {
      unmountInfoviewRoots();
      await pause(50);
      await Promise.all([...notifications]);
      for (const sessionId of sessions) await post("/close", { sessionId });
      sessions.clear();
      removeEventListener("error", report); removeEventListener("unhandledrejection", report);
    },
  };
}
