// Real Iris server + official RPC client + actual VIR shell and Lean-authored UI.
// Run after lake build IrisTest.ProofMode.WidgetDemo IrisTest.ProofMode.WidgetRpc
//   +Iris.ProofMode.Widget:vir +IrisTest.ProofMode.WidgetTour:vir.
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
const { createMessageConnection, StreamMessageReader, StreamMessageWriter, CancellationTokenSource } = require("vscode-jsonrpc/node.js");
const { launchChromium, openChromiumPage, navigate, evaluate } = await import(new URL("tests/browser/harness.mjs", vir));
const { finishLeanProcess } = await import(new URL("tests/infoview/rpc-process-test-support.mjs", vir));
const { withCleanup } = await import(new URL("tests/infoview/rpc-test-support.js", vir));
const sourcePath = new URL("IrisTest/ProofMode/WidgetDemo.lean", iris);
assert.ok(process.argv.slice(2).every(arg => arg === "--demo"), "usage: node scripts/widget-browser-smoke.mjs [--demo]");
const demo = process.argv.includes("--demo");
// Only this in-memory document sees the server cancellation probe.
const originalSource = await readFile(sourcePath, "utf8");
let source = demo ? originalSource : originalSource.replace("import Iris.ProofMode.Widget\n",
  `import Iris.ProofMode.Widget\npublic meta import IrisTest.ProofMode.WidgetRpc\n`);
// Only the automated test opts into the tour; --demo remains the checked-in document.
if (!demo) source = source
  .replace("import Iris.ProofMode.Widget\n", "public meta import IrisTest.ProofMode.WidgetTour\nimport Iris.ProofMode.Widget\n")
  .replace("show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.panelProps]\n",
    "$&show_panel_widgets [local IrisTest.ProofMode.WidgetTour.widget with IrisTest.ProofMode.WidgetTour.panelProps]\n");
const position = marker => {
  const lines = source.split("\n");
  const matches = lines.flatMap((line, index) => line.includes(marker) ? [index] : []);
  assert.equal(matches.length, 1, marker);
  const line = matches[0] + 1;
  return { line, character: lines[line].search(/\S/) };
};
const bundle = await build({
  entryPoints: [fileURLToPath(new URL(demo ? "widget-demo-entry.mjs" : "widget-browser-entry.mjs", import.meta.url))],
  nodePaths: [fileURLToPath(new URL("node_modules", vir))],
  bundle: true, write: false, platform: "browser", format: demo ? "esm" : "iife",
  define: { "process.env.NODE_ENV": JSON.stringify("development") },
  plugins: [{ name: "vir-source-override", setup(builder) {
    if (process.env.IRIS_VIR_SOURCE_DIR) {
      builder.onResolve({ filter: /\/web\/app\/vir-infoview-widget\.js$/ }, () => ({
        path: resolve(process.env.IRIS_VIR_SOURCE_DIR, "web/app/vir-infoview-widget.js"),
      }));
    }
  }}, { name: "official-session-context", setup(builder) {
    builder.onResolve({ filter: /^react-dom$/ }, args => {
      if (args.importer.includes("@leanprover/infoview/dist/"))
        return { path: fileURLToPath(new URL("tests/infoview/react-dom-compat.js", vir)) };
    });
  }}],
});

const assets = {
  "/infoview.css": ["text/css", await readFile(new URL("node_modules/@leanprover/infoview/dist/index.css", vir))],
};

let child, connection, server, chrome, cdp, deadline;
const keepalives = new Map(), diagnostics = [];
const pending = new Map(), cancelled = new Set(), completed = new Set();
let stderr = "";
let currentSource = source, documentVersion = 1;
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
    width: Number(process.env.IRIS_WIDGET_WIDTH ?? 360),
    fontSize: Number(process.env.IRIS_WIDGET_FONT_SIZE ?? 14),
    theme: process.env.IRIS_WIDGET_THEME ?? "light",
    contexts: position("widget-position-contexts"), split: position("widget-position-split"),
    binders: position("widget-position-binders"),
    ordinary: position("widget-position-ordinary"),
    heapStore: position("widget-position-heap-store"),
    heapLoad: position("widget-position-heap-load"),
    heapPost: position("widget-position-heap-post"),
    parSplit: position("widget-position-par-split"),
    spinOpen: position("widget-position-spin-open"),
    spinStored: position("widget-position-spin-stored"),
    spinFrame: position("widget-position-spin-frame"),
    tourHow: position("widget-position-how-vir"),
    tourFeedback: position("widget-position-feedback"),
    ...(demo ? { source } : {}),
  };
  assert.ok(Number.isFinite(config.width) && config.width >= 200);
  assert.ok(Number.isFinite(config.fontSize) && config.fontSize >= 10);
  const themes = {
    light: "--vscode-editor-background:#fff;--vscode-editor-foreground:#24292f",
    dark: "--vscode-editor-background:#1f1f1f;--vscode-editor-foreground:#ccc;--vscode-descriptionForeground:#aaa;--vscode-panel-border:#555;--vscode-textCodeBlock-background:#292929;--vscode-textLink-foreground:#4daafc;--vscode-editorWarning-foreground:#d7ba7d;--vscode-symbolIcon-keywordForeground:#c586c0",
    contrast: "--vscode-editor-background:#000;--vscode-editor-foreground:#fff;--vscode-descriptionForeground:#fff;--vscode-panel-border:#fff;--vscode-textCodeBlock-background:#000;--vscode-textLink-foreground:#6fc3df;--vscode-editorWarning-foreground:#ffff00;--vscode-symbolIcon-keywordForeground:#fff",
  };
  assert.ok(Object.hasOwn(themes, config.theme), "unknown test theme");
  server = createServer(async (req, res) => {
    try {
      const port = server.address().port;
      if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(req.headers.host) ||
          (req.headers.origin && req.headers.origin !== `http://${req.headers.host}`)) {
        res.writeHead(403); res.end(); return;
      }
      if (req.method === "GET") {
        const routes = {
          "/": ["text/html", `<!doctype html><meta charset="utf-8"><style>
            :root { ${themes[config.theme]}; --vscode-editor-font-size:${config.fontSize}px; --vscode-editor-font-family:ui-monospace,monospace; --vscode-font-family:system-ui,sans-serif; }
            body { background:var(--vscode-editor-background); color:var(--vscode-editor-foreground); }
            </style><link rel="stylesheet" href="/infoview.css"><div id="app"></div><script ${demo ? 'type="module"' : ""} src="/test.js"></script>`],
          "/test.js": ["text/javascript", bundle.outputFiles[0].contents],
          "/config": ["application/json", JSON.stringify(config)],
          ...assets,
        };
        const asset = routes[req.url];
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
        if (demo) { res.writeHead(404); res.end(); return; }
        const kind = body.kind ?? "rename";
        assert.ok(["rename", "type", "allocate", "tourShift"].includes(kind));
        let text = kind === "tourShift" ? currentSource.replace("  -- widget-position-heap-store", "\n  -- widget-position-heap-store") :
          kind === "rename" ? currentSource.replaceAll(/\bS\b/g, "T") :
          currentSource.replace("-- widget-position-split", "-- widget-position-split ");
        if (kind === "allocate") text = text.replace("  iintro ⟨#HP, #HQR⟩ HQ HS",
          "  have _widgetPadding : True := True.intro; iintro ⟨#HP, #HQR⟩ HQ HS");
        assert.notEqual(text, currentSource, "edit fixture must change the document");
        currentSource = text;
        result = { textDocument: { uri: sourcePath.href, version: ++documentVersion }, contentChanges: [{ text }] };
        await connection.sendNotification("textDocument/didChange", result);
        await connection.sendRequest("textDocument/waitForDiagnostics", { uri: sourcePath.href, version: documentVersion });
        const lines = text.split("\n"), line = lines.findIndex(line => line.includes("widget-position-split"));
        result.cursor = { line, character: lines[line].length };
      } else if (req.url === "/call") {
        const token = new CancellationTokenSource();
        pending.set(body.id, token);
        if (cancelled.delete(body.id)) token.cancel();
        try {
          result = await connection.sendRequest("$/lean/rpc/call", body.params, token.token);
        } finally {
          pending.delete(body.id); cancelled.delete(body.id); completed.add(body.id); token.dispose();
        }
      } else if (req.url === "/cancel") {
        if (!completed.has(body.id)) {
          cancelled.add(body.id);
          pending.get(body.id)?.cancel();
        }
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
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(demo ? Number(process.env.IRIS_WIDGET_PORT ?? 8140) : 0, "127.0.0.1", resolve);
  });
  if (demo) {
    clearTimeout(deadline);
    console.log(`Iris live widget demo: http://127.0.0.1:${server.address().port}/`);
    console.log("Ctrl+C stops the demo and its Lean server.");
    await new Promise(resolve => {
      process.once("SIGINT", resolve);
      process.once("SIGTERM", resolve);
      child.once("exit", resolve);
    });
    return;
  }
  chrome = await launchChromium(); cdp = await openChromiumPage(chrome);
  await cdp.send("Emulation.setDeviceMetricsOverride", { width: config.width, height: 900, deviceScaleFactor: 1, mobile: false });
  await bounded(navigate(cdp, `http://127.0.0.1:${server.address().port}/`));
  let handled;
  while (!await bounded(evaluate(cdp, "Boolean(globalThis.irisResult)"))) {
    const action = await evaluate(cdp, "globalThis.irisAction");
    if (action && action.id !== handled) {
      handled = action.id;
      if (action.kind === "key") {
        await cdp.send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", text: "\r", windowsVirtualKeyCode: 13 });
        await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
      } else {
        await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: action.x, y: action.y });
        if (action.kind === "click") {
          await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", x: action.x, y: action.y, button: "left", clickCount: 1, modifiers: 2 });
          await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: action.x, y: action.y, button: "left", clickCount: 1, modifiers: 2 });
        }
      }
      await evaluate(cdp, `globalThis.irisActionDone = ${action.id}`);
    }
    if (await evaluate(cdp, "Boolean(globalThis.irisCapture)")) {
      if (process.env.IRIS_WIDGET_SCREENSHOT) {
        const { data } = await cdp.send("Page.captureScreenshot", { format: "png" });
        await writeFile(process.env.IRIS_WIDGET_SCREENSHOT, Buffer.from(data, "base64"));
      }
      await evaluate(cdp, "globalThis.irisCapture = false; globalThis.irisCaptured = true");
    }
    await bounded(new Promise(resolve => setTimeout(resolve, 20)));
  }
  const result = await evaluate(cdp, "globalThis.irisResult");
  assert.equal(result.ok, true, JSON.stringify({ result, diagnostics, stderr }, null, 2));
  assert.ok(!diagnostics.some(report => report.diagnostics.some(d => d.severity === 1)), JSON.stringify(diagnostics));
  if (process.env.IRIS_WIDGET_RESULT) await writeFile(process.env.IRIS_WIDGET_RESULT, JSON.stringify(result.value, null, 2) + "\n");
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
