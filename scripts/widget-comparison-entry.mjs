// Experimental comparison under the actual upstream infoview providers.
// Widget discovery is a host shim; goals, Iris state, native tags and popups use real Lean RPCs.
import * as React from "react";
import { InteractiveCode, renderInfoview, useRpcSession, useClientNotificationEffect,
  EditorContext, DocumentPosition, TaggedText_stripTags, defaultInfoviewConfig } from "@leanprover/infoview";
import { createVirRuntime } from "../Iris/.lake/packages/lean_vir/web/src/vir-runtime.js";
import { createBrowserHostBindings } from "../Iris/.lake/packages/lean_vir/web/src/vir-host-bindings.js";
import { createBrowserReactHostBindings } from "../Iris/.lake/packages/lean_vir/web/src/vir-react-host-bindings.js";
import { unmountInfoviewRoots } from "../Iris/.lake/packages/lean_vir/tests/infoview/react-dom-compat.js";

const h = React.createElement;
const check = (ok, message) => { if (!ok) throw new Error(message); };
const post = async (path, body) => {
  const reply = await (await fetch(path, { method: "POST", body: JSON.stringify(body) })).json();
  if (reply.error) throw reply.error;
  return reply.result;
};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
globalThis.irisComparisonResult = undefined;
run().then(value => { globalThis.irisComparisonResult = { ok: true, value }; }, error => {
  globalThis.irisComparisonResult = { ok: false, error: String(error.stack ?? error) };
});

async function run() {
  const config = await (await fetch("/config")).json();
  const styles = document.createElement("style");
  styles.textContent = `.iris-comparison {display:flex; flex-wrap:wrap; gap:16px; margin:16px 0}
    .iris-comparison > section {width:360px; max-width:100%}
    .iris-native-target {white-space:pre-wrap; overflow-wrap:anywhere}
    .iris-comparison h3 {font:600 13px system-ui}`;
  document.head.append(styles);
  const methods = [], errors = [], samples = [], facts = {}, pending = {}, sessions = new Set();
  const notifications = new Set(), subscriptions = new Set(), navigations = [];
  let runtime, infoview, sequence = 0, requestId = 0, trial = null, observer, latestNativeFmt;
  const productionCodes = new WeakSet();
  const originalError = console.error;
  console.error = (...args) => { errors.push(args.map(String).join(" ")); originalError(...args); };
  const notify = (path, body) => {
    const task = post(path, body); notifications.add(task);
    void task.finally(() => notifications.delete(task)); return task;
  };
  const wait = async (label, predicate) => {
    const deadline = performance.now() + 20000;
    while (!predicate() && performance.now() < deadline) await pause(10);
    check(predicate(), `${label}; errors=${JSON.stringify(errors)}; DOM=${document.getElementById("app").textContent.slice(-2200)}`);
  };
  const current = () => document.querySelector('[data-renderer="current"]');
  const native = () => document.querySelector('[data-renderer="native"]');
  const target = renderer => renderer === "current" ? current()?.querySelector('section[aria-label="Target"] [data-term-id]') :
    native()?.querySelector('.iris-native-target');
  const observe = () => {
    for (const renderer of ["current", "native"]) {
      const p = pending[renderer];
      if (!p || p.trial !== trial || target(renderer)?.textContent !== p.text) continue;
      if (renderer === "current" && current()?.querySelector('[aria-busy="true"]')) continue;
      if (!samples.some(s => s.sequence === trial.sequence && s.renderer === renderer))
        samples.push({ ...trial, renderer, rpcMs: p.received - p.started,
          responseToDomMs: performance.now() - p.received, chars: p.text.length });
      delete pending[renderer];
    }
  };
  try {
    const paths = await (await fetch("/comparison-packages.json")).json();
    const [wasmBytes, ...packages] = await Promise.all(["/runtime.wasm", ...paths].map(async path =>
      new Uint8Array(await (await fetch(path)).arrayBuffer())));
    const bindings = createBrowserHostBindings({ reactHostBindings: createBrowserReactHostBindings,
      infoviewInteractiveCode: InteractiveCode, infoviewEditorContext: EditorContext,
      infoviewUseRpcSession: useRpcSession, infoviewUseClientNotificationEffect: useClientNotificationEffect,
      infoviewPositionToTdpp: DocumentPosition.toTdpp, infoviewStripTags: TaggedText_stripTags });
    let exactNativeElements = 0;
    const createElement = bindings["react.node.createElement"];
    bindings["react.node.createElement"] = (type, props, children) => {
      if (type === InteractiveCode) {
        check(props.fmt === latestNativeFmt || productionCodes.has(props.fmt), "native fmt must retain its exact registered JS object");
        exactNativeElements++;
      }
      return createElement(type, props, children);
    };
    const startup = performance.now();
    runtime = await createVirRuntime({ wasmBytes, irPackageSet: packages, hostBindings: bindings });
    const runtimeStartupMs = performance.now() - startup;
    const Current = runtime.call("IrisTest.ProofMode.WidgetCompare.current");
    const Native = runtime.call("IrisTest.ProofMode.WidgetCompare.native");
    function Comparison(props) {
      const session = useRpcSession();
      const [code, setCode] = React.useState(null);
      const left = React.useMemo(() => h(Current, props), [props]);
      React.useEffect(() => {
        const controller = new AbortController();
        session.call("IrisTest.ProofMode.WidgetCompare.target", { pos: props.pos }, { abortSignal: controller.signal })
          .then(fmt => { if (!controller.signal.aborted) { latestNativeFmt = fmt; setCode({ fmt, position: props.pos }); } })
          .catch(error => { if (!controller.signal.aborted) errors.push(JSON.stringify(error)); });
        return () => controller.abort();
      }, [session, props.pos]);
      return h("div", { className: "iris-comparison" },
        h("section", { "data-renderer": "current" }, h("h3", null, "Current Iris widget"), left),
        h("section", { "data-renderer": "native" }, h("h3", null, "Native target · through VIR"),
          code?.position === props.pos && code.fmt ? h("div", { className: "iris-native-target font-code" }, h(Native, { fmt: code.fmt })) : "Waiting for an Iris target…"));
    }
    globalThis.irisComparisonWidget = Comparison;
    const api = {
      async createRpcSession() { const { sessionId } = await post("/connect", {}); sessions.add(sessionId); return sessionId; },
      async closeRpcSession(sessionId) { sessions.delete(sessionId); await notify("/close", { sessionId }); },
      async sendClientRequest(_uri, method, params, options) {
        check(method === "$/lean/rpc/call", `unexpected LSP method ${method}`);
        methods.push(params.method);
        if (params.method === "Lean.Widget.getWidgets")
          return { widgets: [{ id: "iris-comparison", javascriptHash: "875222222", props: {} }] };
        if (params.method === "Lean.Widget.getWidgetSource")
          return { sourcetext: "export default globalThis.irisComparisonWidget;" };
        const id = ++requestId, started = performance.now(), owningTrial = trial;
        const cancel = () => { void notify("/cancel", { id }); };
        options?.abortSignal?.addEventListener("abort", cancel, { once: true });
        if (options?.abortSignal?.aborted) cancel();
        try {
          const result = await post("/call", { id, params });
          if (params.method === "Iris.ProofMode.Widget.state") result.codes.forEach(code => productionCodes.add(code));
          const received = performance.now();
          const renderer = params.method === "Iris.ProofMode.Widget.state" ? "current" :
            params.method === "IrisTest.ProofMode.WidgetCompare.target" ? "native" : null;
          if (renderer && owningTrial && params.position.line === config[owningTrial.position].line) {
            const text = renderer === "current" ? JSON.parse(result.display).goals[0]?.target.text : TaggedText_stripTags(result);
            pending[renderer] = { started, received, text, trial: owningTrial };
          }
          return result;
        } finally { options?.abortSignal?.removeEventListener("abort", cancel); }
      },
      async sendClientNotification(_uri, method, params) { if (method === "$/lean/rpc/release") await notify("/release", params); },
      async subscribeServerNotifications(method) { subscriptions.add(method); }, async unsubscribeServerNotifications() {},
      async subscribeClientNotifications() {}, async unsubscribeClientNotifications() {},
      async copyToClipboard() {}, async saveConfig() {}, async showDocument(params) { navigations.push(params); },
    };
    observer = new MutationObserver(observe); observer.observe(document.getElementById("app"), { subtree: true, childList: true, characterData: true, attributes: true });
    infoview = renderInfoview(api, document.getElementById("app"));
    await wait("upstream provider initialization", () => subscriptions.has("$/lean/fileProgress"));
    await infoview.serverRestarted({ capabilities: config.capabilities, serverInfo: { name: "Lean", version: "4.35.0" } });
    await infoview.changedInfoviewConfig({ ...defaultInfoviewConfig, debounceTime: 0 });
    await infoview.initialize({ uri: config.uri, range: { start: config.ordinary, end: config.ordinary } });
    await wait("initial ordinary goal", () => document.getElementById("app").textContent.includes("Tactic state"));
    const positions = ["contexts", "heapStore", "heapLoad", "heapPost", "spinOpen", "spinStored", "binders"];
    for (let pass = 0; pass < 6; pass++) {
      for (const position of positions) {
        trial = { sequence: ++sequence, pass, position, warmup: pass === 0 };
        await infoview.changedCursorLocation({ uri: config.uri, range: { start: config[position], end: config[position] } });
        await wait("both exact targets committed", () => samples.filter(s => s.sequence === sequence).length >= 2 &&
          target("current")?.textContent === target("native")?.textContent);
        const buttons = [...current().querySelectorAll('[data-term-ref]')];
        facts[position] = { termButtons: buttons.length,
          punctuationOnly: buttons.filter(b => !/[\p{L}\p{N}]/u.test(b.textContent)).length,
          visibleChars: current().querySelector('[data-iris-proof-mode-widget]').innerText.length,
          targetChars: target("native").textContent.length,
          nativeButtons: native().querySelectorAll('button').length,
          nativeTabStops: [...native().querySelectorAll('button,a[href],input,select,textarea,[tabindex]')].filter(e => e.tabIndex >= 0).length,
          nativeTaggedSpans: native().querySelectorAll('[data-has-tooltip-on-hover]').length };
      }
    }
    // Real pointer hover, dispatched by the outer Chromium driver.
    const m = [...native().querySelectorAll('[data-has-tooltip-on-hover]')].find(e => e.textContent === "m");
    check(m, "native binder tag exists"); m.scrollIntoView({ block: "center" });
    const box = m.getBoundingClientRect();
    globalThis.irisComparisonPointer = { id: 1, x: box.x + box.width / 2, y: box.y + box.height / 2 };
    await wait("native hover uses the saved binder context", () => document.querySelector('.tooltip-code-content')?.textContent.includes("Nat"));
    globalThis.irisComparisonPointer = { id: 2, x: 1, y: 1 };
    document.body.click();
    await wait("hover closes", () => !document.querySelector('.tooltip-code-content'));
    trial = { sequence: ++sequence, pass: 6, position: "heapStore", warmup: true };
    await infoview.changedCursorLocation({ uri: config.uri, range: { start: config.heapStore, end: config.heapStore } });
    await wait("heap for native navigation", () => samples.filter(s => s.sequence === sequence).length >= 2);
    const some = [...native().querySelectorAll('[data-has-tooltip-on-hover]')].find(e => e.textContent.startsWith("some"));
    check(some, "native Option.some tag exists");
    some.dispatchEvent(new MouseEvent("click", { bubbles: true, ctrlKey: true }));
    await wait("native go-to-definition reaches editor API", () => navigations.length > 0);
    check(errors.length === 0, JSON.stringify(errors));
    if (config.captureComparison) {
      document.querySelector('.iris-comparison').scrollIntoView({ block: "center" });
      globalThis.irisComparisonCapture = true;
      await wait("comparison screenshot", () => globalThis.irisComparisonCaptured);
    }
    return { reactMode: "production", boundary: "native RPC response decoded in JS to MutationObserver seeing exact target; not paint or isolated render time",
      runtimeStartupMs, facts, samples, exactNativeElements, navigation: navigations[0], methods,
      exclusions: ["VS Code command execution", "screen reader", "location-selection provider", "long-session GC", "cold network download"] };
  } finally {
    observer?.disconnect();
    if (infoview) {
      await infoview.changedCursorLocation(undefined);
      await infoview.sentClientNotification("textDocument/didClose", { textDocument: { uri: config.uri } });
      await pause(20);
    }
    unmountInfoviewRoots();
    runtime?.dispose();
    for (const sessionId of sessions) await notify("/close", { sessionId });
    while (notifications.size) await Promise.all([...notifications]);
    delete globalThis.irisComparisonWidget;
    console.error = originalError;
  }
}
