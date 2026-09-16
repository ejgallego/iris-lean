// Run from any directory after building +Iris.ProofMode.Widget:vir and the matching VIR Wasm.
// Component-factory and SSR loading-shell check. Effects/native RPC run in widget-browser-smoke.mjs.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const irisRoot = new URL("../Iris/", import.meta.url);
const virRoot = new URL(".lake/packages/lean_vir/", irisRoot);
const { createVirRuntime } = await import(new URL("web/src/vir-runtime-node.js", virRoot));
const { createBrowserHostBindings } = await import(new URL("web/src/vir-host-bindings.js", virRoot));
const { createBrowserReactHostBindings } = await import(new URL("web/src/vir-react-host-bindings.js", virRoot));
const React = await import(new URL("node_modules/react/index.js", virRoot));
const { renderToStaticMarkup } = await import(new URL("node_modules/react-dom/server.node.js", virRoot));

const descriptorUrl = new URL(".lake/build/vir/module-sets/Iris/ProofMode/Widget.irpkg-set.json", irisRoot);
const descriptor = JSON.parse(await readFile(descriptorUrl, "utf8"));
assert.equal(descriptor.format, "lean-vir-ir-package-set");
assert.equal(descriptor.version, 2);
const packages = await Promise.all(descriptor.packages.map(async entry => {
  const bytes = await readFile(new URL(entry.path, descriptorUrl));
  assert.equal(bytes.byteLength, entry.byteLength);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), entry.sha256);
  return bytes;
}));
const runtime = await createVirRuntime({
  wasmBytes: await readFile(new URL("web/public/vir-upstream.wasm", virRoot)),
  irPackageSet: packages,
  hostBindings: createBrowserHostBindings({
    reactHostBindings: createBrowserReactHostBindings,
    // SSR evaluates the hook but must never schedule its RPC effect.
    infoviewUseRpcSession: () => ({ call() { throw new Error("SSR must not run an RPC effect"); } }),
  }),
});

try {
  const component = runtime.call("Iris.ProofMode.Widget.createComponent");
  assert.equal(typeof component, "function");
  const panelProps = { pos: { line: 0, character: 0 } };
  const markup = renderToStaticMarkup(React.createElement(component, panelProps));
  assert.match(markup, /Loading Iris goals/);
  console.log(`PASS: ${packages.length} verified package members; native panel component factory and SSR loading shell. Run widget-browser-smoke.mjs for live RPC and interactions.`);
} finally {
  runtime.dispose();
}
