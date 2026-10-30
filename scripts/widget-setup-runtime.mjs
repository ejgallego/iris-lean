// Install the Wasm selected by the pinned VIR resource lock, without a local Wasm build.
// Lake's VIR target downloads and validates the complete pack against its compatibility profile.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const iris = new URL("../Iris/", import.meta.url);
const vir = new URL(".lake/packages/lean_vir/", iris);
execFileSync("lake", ["build", "lean_vir/virRuntimePack"], {
  cwd: fileURLToPath(iris), stdio: "inherit",
  env: { ...process.env, LAKE_ARTIFACT_CACHE: "true", LAKE_RESTORE_ARTIFACTS: "true" },
});
const bytes = await readFile(new URL(".vir-generated/VirResourceRuntime.virres", vir));
assert.deepEqual(bytes.subarray(0, 8), Buffer.from([86, 73, 82, 82, 69, 83, 0, 1]));
const end = 12 + bytes.readUInt32LE(8);
const lock = JSON.parse(await readFile(new URL("vir-resources/runtime.json", vir), "utf8"));
const contentId = createHash("sha256").update("vir-resource-bundle-v2\n")
  .update(bytes.subarray(12, end)).digest("hex");
assert.equal(contentId, lock.contentId, "installed runtime must match the pinned resource lock");
const descriptor = JSON.parse(bytes.subarray(12, end));
assert.equal(descriptor.kind, "runtime");
const wasmEntry = descriptor.fileEntries.find(entry => entry.role === "wasm");
assert.ok(wasmEntry, "runtime pack must declare its Wasm entry");
let offset = end, wasm;
for (const entry of descriptor.files) {
  const payload = bytes.subarray(offset, offset + entry.byteLength);
  assert.equal(payload.length, entry.byteLength);
  assert.equal(createHash("sha256").update(payload).digest("hex"), entry.sha256);
  if (entry.path === wasmEntry.path) wasm = payload;
  offset += entry.byteLength;
}
assert.equal(offset, bytes.length);
assert.ok(wasm, "declared Wasm entry must be present");
await mkdir(new URL("web/public/", vir), { recursive: true });
const destination = new URL("web/public/vir-upstream.wasm", vir);
const temporary = new URL(`web/public/vir-upstream.wasm.${process.pid}.tmp`, vir);
await writeFile(temporary, wasm);
await rename(temporary, destination);
console.log(`Installed runtime ${contentId} (${wasm.length} Wasm bytes) at ${fileURLToPath(destination)}`);
