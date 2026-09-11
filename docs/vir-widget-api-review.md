# VIR API review from the Iris widget

Reviewed 2026-09-11 against local compatibility commit
`be6931c063a675a8089f2d5ed52bb4d379d0f718`, directly over PR #171 at `8750e1b`,
using Lean 4.32.2. These findings concern that exact checkout, not uninspected
later VIR changes. No VIR sources were modified by the initial review and no
issues were filed. A subsequent editor failure led to the local
[shell error/startup fixes](widget-shell-errors.md), now pinned by Iris.

## 1. Confirmed mismatch: `ofNat` documents number but returns bigint

The generated documentation for `JsValue.ofNat` says JavaScript number:
[`Vir/Js/Generated.lean`](../Iris/.lake/packages/lean_vir/Vir/Js/Generated.lean).
The host implementation returns `BigInt(text)` and `toNat` requires bigint:
[`vir-js-value-bindings.js`](../Iris/.lake/packages/lean_vir/web/src/host/vir-js-value-bindings.js).

This matters for native RPC: `JSON.stringify({ line: 3n })` throws. Merely
replacing our explicit `ofFloat n.toFloat` conversions with the apparently
more idiomatic `ofNat n` would break the request. This was reproduced directly
against the pinned host implementation:

```sh
cd Iris/.lake/packages/lean_vir
node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { createJsValueHostBindings } from './web/src/host/vir-js-value-bindings.js';
const api = createJsValueHostBindings();
const value = api['js.nat'](3n);
assert.equal(typeof value, 'bigint');
assert.throws(() => JSON.stringify({ line: value }), TypeError);
assert.equal(JSON.stringify({ line: api['js.float'](3) }), '{"line":3}');
JS
```

`Surface.DocumentPosition.toJs` also calls `ofNat` for line/character:
[`Surface.lean`](../Iris/.lake/packages/lean_vir/Vir/Infoview/Surface.lean).
Follow-up source inspection found that `documentPosition` in
[`vir-infoview-host-bindings.js`](../Iris/.lake/packages/lean_vir/web/src/host/vir-infoview-host-bindings.js)
explicitly normalizes safe bigint coordinates to numbers. Thus that helper
does not establish an editor-command defect. Reveal/insert commands themselves
were not exercised. The raw native-RPC JSON conversion mismatch above remains.

Recommended upstream change: make BigInt semantics explicit in the source
binding configuration and generated docs, and provide a checked natural-to-JS-
number conversion for indices/positions. Do not silently change arbitrary-
precision Nat conversion and lose precision. Include JSON RPC and editor-command
tests, and define the safe-integer overflow policy.

Iris keeps the existing JS-number conversion for practical array indices and
LSP positions, with an explanation at the call site. This is not a claim that
`Nat.toFloat` is lossless for every Lean natural number.

## 2. Missing binding: React `useId`

There is no `useId` binding in the pinned
[`React/Generated.lean`](../Iris/.lake/packages/lean_vir/Vir/React/Generated.lean)
or its convenience API. The Iris view previously built DOM IDs from semantic
hypothesis IDs. Expanding both split goals reproduced duplicate IDs because
persistent hypotheses are shared. That was an **Iris bug**, now fixed with
goal/context/row occurrence scoping and a browser regression.

The remaining multi-instance case should use React-provided instance identity,
not a new global registry of Iris expressions or a render-time counter. A direct
`useId` binding, tested for Strict Mode and multiple roots/instances, would make
accessible `aria-controls`/`aria-labelledby` authoring much easier.

## 3. Async authoring is correct but too repetitive downstream

The native primitives already exist: exact RPC session, Promise, callback,
AbortController, and `callWithOptions`. Cancellation is **not missing**.
See [`Surface/Generated.lean`](../Iris/.lake/packages/lean_vir/Vir/Infoview/Surface/Generated.lean)
and [VIR's compatibility review](../Iris/.lake/packages/lean_vir/docs/PROOFWIDGETS_RPC_COMPATIBILITY.md).

Iris still has to compose callback conversions, both fulfillment and rejection
observation, state updates, exact effect dependencies, and stale-result guards
for each interaction. A two-handler `then(success, failure)` alone does not catch
exceptions thrown by `success`; our observer chains another rejection handler.
This is native Promise semantics, not a VIR Promise bug.

Recommended upstream work: bind the existing infoview async hooks or provide a
small, clearly optional Lean convenience layer over native React/Promises.
Preserve exact session/reference identity, handle cleanup and both late outcomes,
and document cancellation separately from stale-result suppression. Test thrown
fulfillment handlers as well as genuine server rejections. Do not add another
RPC reference registry or a replacement Promise scheduler.

Iris now isolates this composition in `Client.useInspection`; the renderer sees
Lean values and actions. Our helper does not yet request cancellation or handle
every possible synchronous host exception during effect setup.

## 4. Native wire records need an ergonomic typed boundary

`RpcSession.call` correctly accepts native JS values, but its method string,
request phantom type and result phantom type are independently chosen by the
caller. Iris manually assembles `pos`, `snapshot` and `reference` properties and
reads the response with `Js.Object.get`. A Lean `RpcEncodable` server structure
does not automatically provide a matching client-side record builder/decoder.

This is an ergonomics/schema-drift risk, not evidence that the binding corrupts
data. A useful layer would generate or declare method-specific request builders
and checked response projections while retaining exact native `WithRpcRef`
objects. Recursive JSON copying is not an acceptable reference encoder.

Likewise, `StateTuple.toState` plus explicit `LeanRef` wrapping is mechanically
repeated for Lean-owned state. Iris's small `Client.useState` helper composes
these operations without changing React ownership. Its dependency is the exact
retained JSL object, not a fresh wrapper on each render.

## 5. Error presentation still loses useful information in Iris

VIR forwards the real rejection as `Js.Any`; **Iris currently discards it** and
shows a generic inspection/snapshot message. Do not classify this as a transport
bug. A checked `mapRpcError`-style convenience would make it easier to distinguish
expired references, server errors and malformed payloads without unsafe casts.
Preserve the original rejection for diagnosis and guard error rendering itself.

This remains follow-up work. Browser tests prove visible generic errors and
suppression of stale errors, not good diagnostic detail or automatic restart
recovery.

## 6. Downstream packaging and test infrastructure are still repo-shaped

Iris explicitly points at a matching Wasm inside `.lake/packages/lean_vir/` and
pins a compatibility commit. That source pin is now published on
[`fix/iris-widget-errors`](https://github.com/ejgallego/lean-vir/tree/fix/iris-widget-errors),
but a fresh dependency checkout alone
does not provide a runnable widget. The `vir_proof_widget` convenience macro also
does not expose our custom Wasm path/setup hint, so this example spells out its
entry declarations. The explicit `ReactWidget` API does support them.

Our browser regression imports VIR's internal test harness files. This gives
valuable real-runtime coverage today but is not a stable downstream test API.
Before upstreaming Iris support, agree on a toolchain-compatible runtime staging
target and a supported external-widget browser harness.
Keep artifact caching enabled; none of these issues is a reason to rewrite the
downloader or disable the cache.

## Suggested order

1. Correct numeric conversion documentation/contracts and add boundary tests.
2. Expose `useId` and a small async/error authoring example or helper.
3. Make downstream runtime setup and browser tests reproducible.
4. Explore typed native RPC records after stabilizing the reference boundary.

The native RPC foundation works in the tested Iris cases. Remaining unmeasured
areas include long-session retention, runtime replacement during pending work,
server restart/expired references, multiple widget instances and large goals.
No leak, performance regression or cancellation defect is claimed without those
measurements.
