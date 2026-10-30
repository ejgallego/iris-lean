// Real Iris server + official RPC client + actual VIR shell and Lean-authored UI.
// Run after lake build IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const iris = new URL("../Iris/", import.meta.url);
const vir = new URL(".lake/packages/lean_vir/", iris);
const require = createRequire(new URL("package.json", vir));
const { build } = require("esbuild");
const { createMessageConnection, StreamMessageReader, StreamMessageWriter } = require("vscode-jsonrpc/node.js");
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(new URL("tests/browser/harness.mjs", vir));
const { finishLeanProcess } = await import(new URL("tests/infoview/rpc-process-test-support.mjs", vir));
const { withCleanup } = await import(new URL("tests/infoview/rpc-test-support.js", vir));
const sourcePath = new URL("IrisTest/ProofMode/WidgetDemo.lean", iris);
const source = await readFile(sourcePath, "utf8");
const position = marker => {
  const lines = source.split("\n");
  const matches = lines.flatMap((line, index) => line.includes(marker) ? [index] : []);
  assert.equal(matches.length, 1, marker);
  const line = matches[0] + 1;
  return { line, character: lines[line].search(/\S/) };
};
const bundle = await build({
  entryPoints: [fileURLToPath(new URL("widget-browser-entry.mjs", import.meta.url))],
  nodePaths: [fileURLToPath(new URL("node_modules", vir))],
  bundle: true, write: false, platform: "browser", format: "iife",
  define: { "process.env.NODE_ENV": '"development"' },
  plugins: [{ name: "vir-source-override", setup(builder) {
    if (process.env.IRIS_VIR_SOURCE_DIR) {
      builder.onResolve({ filter: /\/web\/app\/vir-infoview-widget\.js$/ }, () => ({
        path: resolve(process.env.IRIS_VIR_SOURCE_DIR, "web/app/vir-infoview-widget.js"),
      }));
    }
  }}, { name: "official-session-context", setup(builder) {
    builder.onResolve({ filter: /^@leanprover\/infoview$/ }, () => ({ path: "context", namespace: "iris-test" }));
    builder.onLoad({ filter: /.*/, namespace: "iris-test" }, () => ({
      contents: `import * as React from 'react';
        export const EditorContext = React.createContext(null);
        export const DocumentPosition = { toTdpp: position => position };
        export const TaggedText_stripTags = value => value;
        export function InteractiveCode() { throw new Error('Iris uses its own tagged-term renderer'); }
        globalThis.irisNotificationHandlers = new Set();
        export function useClientNotificationEffect(method, handler, deps) {
          React.useEffect(() => {
            if (method !== 'textDocument/didChange') return;
            globalThis.irisNotificationHandlers.add(handler);
            return () => globalThis.irisNotificationHandlers.delete(handler);
          }, deps);
        }
        export function useRpcSession() { return globalThis.irisSession; }`,
      resolveDir: fileURLToPath(vir), loader: "js",
    }));
  }}],
});

let child, connection, server, chrome, cdp, deadline;
const keepalives = new Map(), diagnostics = [];
let stderr = "";
await withCleanup(async () => {
  const timedOut = new Promise((_, reject) => {
    deadline = setTimeout(() => reject(new Error(`Iris browser acceptance timed out: ${stderr}`)), 120000);
  });
  void timedOut.catch(() => {});
  const bounded = action => Promise.race([action, timedOut]);
  child = spawn("lake", ["serve", "--", "-DstderrAsMessages=false"], {
    cwd: fileURLToPath(iris), stdio: ["pipe", "pipe", "pipe"],
  });
  child.stderr.on("data", chunk => { stderr = (stderr + chunk).slice(-8000); });
  connection = createMessageConnection(new StreamMessageReader(child.stdout), new StreamMessageWriter(child.stdin));
  connection.onNotification("textDocument/publishDiagnostics", report => diagnostics.push(report));
  connection.listen();
  const initialized = await bounded(connection.sendRequest("initialize", {
    processId: process.pid, rootUri: iris.href,
    capabilities: { lean: { rpcWireFormat: "v1" } }, initializationOptions: { hasWidgets: true },
  }));
  await connection.sendNotification("initialized", {});
  await connection.sendNotification("textDocument/didOpen", {
    textDocument: { uri: sourcePath.href, languageId: "lean", version: 1, text: source },
  });
  await bounded(connection.sendRequest("textDocument/waitForDiagnostics", { uri: sourcePath.href, version: 1 }));
  assert.ok(!diagnostics.some(report => report.diagnostics.some(d => d.severity === 1)), JSON.stringify(diagnostics));
  const config = {
    uri: sourcePath.href, capabilities: initialized.capabilities,
    packageDelayMs: Number(process.env.IRIS_WIDGET_PACKAGE_DELAY_MS ?? 0),
    contexts: position("widget-position-contexts"), split: position("widget-position-split"),
    binders: position("widget-position-binders"),
    ordinary: position("widget-position-ordinary"),
  };
  server = createServer(async (req, res) => {
    try {
      if (req.method === "GET") {
        const assets = {
          "/": ["text/html", '<!doctype html><meta charset="utf-8"><div id="app"></div><script src="/test.js"></script>'],
          "/test.js": ["text/javascript", bundle.outputFiles[0].contents],
          "/config": ["application/json", JSON.stringify(config)],
        };
        const asset = assets[req.url];
        if (!asset) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { "content-type": asset[0] }); res.end(asset[1]); return;
      }
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString());
      let result;
      if (req.url === "/connect") {
        result = await connection.sendRequest("$/lean/rpc/connect", { uri: sourcePath.href });
        const { sessionId } = result;
        keepalives.set(sessionId, setInterval(() => connection.sendNotification("$/lean/rpc/keepAlive", {
          uri: sourcePath.href, sessionId,
        }), 5000));
      } else if (req.url === "/edit") {
        const text = source.replaceAll(/\bS\b/g, "T");
        assert.notEqual(text, source, "edit fixture must change the target");
        result = { textDocument: { uri: sourcePath.href, version: 2 }, contentChanges: [{ text }] };
        await connection.sendNotification("textDocument/didChange", result);
        await connection.sendRequest("textDocument/waitForDiagnostics", { uri: sourcePath.href, version: 2 });
      } else if (req.url === "/call") {
        result = await connection.sendRequest("$/lean/rpc/call", body);
      } else if (req.url === "/release") {
        await connection.sendNotification("$/lean/rpc/release", body);
      } else if (req.url === "/close") {
        clearInterval(keepalives.get(body.sessionId)); keepalives.delete(body.sessionId);
      } else { throw new Error("Unknown test endpoint"); }
      res.writeHead(200, { "content-type": "application/json" }); res.end(JSON.stringify({ result }));
    } catch (error) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { code: error.code, message: error.message } }));
    }
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  chrome = await launchChromium(); cdp = await openChromiumPage(chrome);
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: 360, height: 900, deviceScaleFactor: 1, mobile: false });
  await bounded(navigate(cdp, `http://127.0.0.1:${server.address().port}/`));
  // Drive actual browser keyboard activation, not a synthetic click claiming to test Enter.
  for (;;) {
    const status = await bounded(evaluate(cdp, "({phase: globalThis.irisPhase, failure: globalThis.irisFailure})"));
    if (status.failure) throw new Error(status.failure);
    if (status.phase === "keyboard") break;
    await bounded(new Promise(resolve => setTimeout(resolve, 50)));
  }
  await cdp.send("Page.bringToFront");
  assert.equal(await evaluate(cdp, "document.activeElement?.textContent"), "P", "term has keyboard focus");
  if (process.env.IRIS_WIDGET_SCREENSHOT) {
    const { data } = await cdp.send("Page.captureScreenshot", { format: "png" });
    await writeFile(process.env.IRIS_WIDGET_SCREENSHOT, Buffer.from(data, "base64"));
  }
  await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", text: "\r", windowsVirtualKeyCode: 13 });
  await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  const result = await bounded(evaluate(cdp, "globalThis.irisAcceptance"));
  assert.equal(result.ok, true, JSON.stringify({ result, diagnostics, stderr }, null, 2));
  assert.ok(!diagnostics.some(report => report.diagnostics.some(d => d.severity === 1)), JSON.stringify(diagnostics));
  console.log("PASS: Iris native-RPC browser acceptance", result.value);
}, [
  ["deadline", () => clearTimeout(deadline)],
  ["keepalives", () => { for (const timer of keepalives.values()) clearInterval(timer); }],
  ["CDP", () => cdp?.close()], ["Chromium", () => chrome?.close()],
  ["HTTP", async () => { if (server) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); } }],
  ["Lean", async () => { if (connection && child?.exitCode === null) {
    await Promise.race([connection.sendRequest("shutdown"), new Promise(resolve => setTimeout(resolve, 2000))]);
    await connection.sendNotification("exit");
  } }],
  ["connection", () => connection?.dispose()],
  ["process", () => child && finishLeanProcess(child)],
]);
