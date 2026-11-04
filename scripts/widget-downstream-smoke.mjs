// Packaging diagnostic: a fresh consumer and an isolated copy of the current Iris sources.
// Keeps its workspace/logs under .tmp; never changes the working dependency checkout.
// Requires the normal widget development dependencies and matching installed Wasm.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { cp, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const iris = join(root, "Iris"), donor = join(iris, ".lake/packages/lean_vir");
const require = createRequire(join(donor, "package.json"));
const { createMessageConnection, StreamMessageReader, StreamMessageWriter } = require("vscode-jsonrpc/node.js");
const { finishLeanProcess } = await import(new URL("../Iris/.lake/packages/lean_vir/tests/infoview/rpc-process-test-support.mjs", import.meta.url));
const tmp = join(root, ".tmp");
await mkdir(tmp, { recursive: true });
const fixture = await mkdtemp(join(tmp, "widget-downstream-"));
const env = { ...process.env, TMPDIR: tmp, LAKE_ARTIFACT_CACHE: "true", LAKE_RESTORE_ARTIFACTS: "true",
  npm_config_cache: join(tmp, "npm-cache") };
const report = { fixture, stages: [], limitation: "Local Iris source copy, fresh transitive git clones, existing artifact cache. Not a released-package or clean-cache install." };
const hash = value => createHash("sha256").update(value).digest("hex");
let child, connection, keepalive, deadline;
console.log(`Downstream fixture: ${fixture}`);
async function run(stage, command, args, cwd = fixture) {
  console.log(`${stage}: ${command} ${args.join(" ")}`);
  const log = join(fixture, `${stage}.log`), stream = createWriteStream(log);
  const process = spawn(command, args, { cwd, env, stdio: ["ignore", "pipe", "pipe"] });
  process.stdout.pipe(stream, { end: false }); process.stderr.pipe(stream, { end: false });
  const code = await new Promise((resolve, reject) => { process.once("error", reject); process.once("close", resolve); });
  await new Promise(resolve => stream.end(resolve));
  report.stages.push({ stage, command, args, cwd, code, log });
  assert.equal(code, 0, `${stage} failed; see ${log}`);
}
try {
  // Preserve dirty source changes; exclude all local build/session/dependency material.
  await cp(iris, join(fixture, "iris"), { recursive: true,
    filter: path => ![".lake", ".beam", ".tmp", ".git"].includes(basename(path)) });
  await cp(join(iris, "lean-toolchain"), join(fixture, "lean-toolchain"));
  await writeFile(join(fixture, "lakefile.toml"), `name = "iris_widget_consumer"
enableArtifactCache = true
[[require]]
name = "iris"
path = "iris"
[[lean_lib]]
name = "Consumer"
`);
  const source = `module
import Iris.ProofMode.Widget
public meta import Iris.ProofMode.Widget
import Iris.ProofMode
public meta import Iris.ProofMode
open Iris
show_panel_widgets [local Lean.Vir.Infoview.widget with Iris.ProofMode.Widget.panelProps]
example [BI PROP] (P : PROP) : P ⊢ P := by
  iintro H
  -- downstream-position
  iexact H
`;
  await writeFile(join(fixture, "Consumer.lean"), source);
  report.sourceHash = hash(source);
  report.irisManifestHash = hash(await readFile(join(fixture, "iris/lake-manifest.json")));
  await run("update", "lake", ["update"]);
  const vir = join(fixture, ".lake/packages/lean_vir");
  // The current VIR infoview target invokes esbuild, so prepare its declared JS dependencies.
  await run("npm-ci", "npm", ["ci", "--no-audit", "--no-fund"], vir);
  await run("build", "lake", ["build", "Consumer"]);
  const uri = new URL(`file://${join(fixture, "Consumer.lean")}`).href;
  const lines = source.split("\n"), line = lines.findIndex(line => line.includes("downstream-position")) + 1;
  const position = { line, character: 2 }, diagnostics = [];
  child = spawn("lake", ["serve", "--", "-DstderrAsMessages=false"], { cwd: fixture, env, stdio: ["pipe", "pipe", "pipe"] });
  const serverLog = createWriteStream(join(fixture, "server.log"));
  child.stderr.pipe(serverLog);
  connection = createMessageConnection(new StreamMessageReader(child.stdout), new StreamMessageWriter(child.stdin));
  connection.onNotification("textDocument/publishDiagnostics", value => diagnostics.push(value));
  connection.listen();
  const timeout = new Promise((_, reject) => { deadline = setTimeout(() => reject(new Error("downstream RPC timeout")), 120000); });
  void timeout.catch(() => {});
  const bounded = task => Promise.race([task, timeout]);
  await bounded(connection.sendRequest("initialize", { processId: process.pid, rootUri: new URL(`file://${fixture}/`).href,
    capabilities: { lean: { rpcWireFormat: "v1" } }, initializationOptions: { hasWidgets: true } }));
  await connection.sendNotification("initialized", {});
  await connection.sendNotification("textDocument/didOpen", { textDocument: { uri, languageId: "lean", version: 1, text: source } });
  await bounded(connection.sendRequest("textDocument/waitForDiagnostics", { uri, version: 1 }));
  assert.ok(!diagnostics.some(d => d.diagnostics.some(d => d.severity === 1)), JSON.stringify(diagnostics));
  const { sessionId } = await bounded(connection.sendRequest("$/lean/rpc/connect", { uri }));
  keepalive = setInterval(() => connection.sendNotification("$/lean/rpc/keepAlive", { uri, sessionId }), 5000);
  const rpc = (method, params) => bounded(connection.sendRequest("$/lean/rpc/call", { textDocument: { uri }, position, sessionId, method, params }));
  const widgets = await rpc("Lean.Widget.getWidgets", position);
  const props = widgets.widgets.find(w => w.props?.irPackage?.entry === "Iris.ProofMode.Widget.createComponent")?.props;
  assert.ok(props, "downstream imported widget is registered");
  report.props = props;
  const state = await rpc("Iris.ProofMode.Widget.state", { pos: position });
  const goal = JSON.parse(state.display).goals[0];
  assert.equal(goal.target.text, "P");
  assert.equal(goal.spatial[0].name, "H");
  report.typedState = "P ⊢ P, spatial H, imported RPC works";
  let missing;
  try { await rpc("Lean.Vir.Infoview.readAsset", { path: props.wasmPath }); }
  catch (error) { missing = { code: error.code, message: error.message }; }
  assert.ok(missing, "fresh dependency is expected to have no installed Wasm; update this diagnostic when packaging changes");
  assert.ok(missing.message.includes(resolve(fixture, props.wasmPath)), JSON.stringify(missing));
  report.initialAssetFailure = missing;
  // Diagnostic control only: install identical, already validated bytes in the CONSUMER clone.
  // This is not a proposed distribution fix or a claim that fresh installation works unaided.
  const wasm = await readFile(join(donor, "web/public/vir-upstream.wasm"));
  const destination = resolve(fixture, props.wasmPath);
  assert.ok(destination.startsWith(vir + "/"), "runtime resolves into the consumer's transitive VIR dependency");
  await mkdir(join(vir, "web/public"), { recursive: true });
  await writeFile(destination, wasm);
  const asset = await rpc("Lean.Vir.Infoview.readAsset", { path: props.wasmPath });
  assert.equal(hash(Buffer.from(asset.dataBase64, "base64")), hash(wasm));
  report.runtime = { sha256: hash(wasm), bytes: wasm.length, destination, control: "Matching donor bytes installed only in isolated consumer" };
  const pkg = await rpc("Lean.Vir.Infoview.buildIRPackage", { package: props.irPackage, pos: position });
  assert.equal(pkg.entry, props.irPackage.entry);
  assert.equal(pkg.fingerprint, props.irPackage.fingerprint);
  const bytes = Buffer.from(pkg.dataBase64, "base64");
  assert.ok(bytes.length > 0);
  report.package = { entry: pkg.entry, fingerprint: pkg.fingerprint, bytes: bytes.length, sha256: hash(bytes) };
  report.ok = true;
  console.log("PASS: downstream registration/state/package; missing runtime reproduced, consumer-local install control resolves exact bytes.");
} catch (error) {
  report.ok = false; report.error = String(error.stack ?? error); process.exitCode = 1;
  console.error(report.error);
} finally {
  clearTimeout(deadline); clearInterval(keepalive);
  if (connection && child?.exitCode === null) {
    await Promise.race([connection.sendRequest("shutdown"), new Promise(resolve => setTimeout(resolve, 2000))]).catch(() => {});
    await connection.sendNotification("exit").catch(() => {});
  }
  connection?.dispose();
  if (child) await finishLeanProcess(child);
  await writeFile(join(fixture, "result.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(`Evidence retained at ${join(fixture, "result.json")}`);
}
