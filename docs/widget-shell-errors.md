# Editor shell error investigation — 2026-09-11

The user reported `[object Object]` followed by the Iris runtime setup hint;
restarting the Lean file did not clear it. That text does **not** identify a
missing runtime, a cache problem, or a failed Iris inspection. The shell was
discarding the message carried by a plain RPC rejection. The underlying error
in that editor session was not captured before the issue stopped occurring.
The user subsequently confirmed that the widget works after the two fixes.
This confirms basic editor usability, not a unique causal diagnosis of the
original RPC failure or full editor/accessibility acceptance.

## Compatibility-branch fixes

Iris now pins `8032fd34add0b75d4f59c82382e2a57b4c2522a4` on published VIR branch
[`fix/iris-widget-errors`](https://github.com/ejgallego/lean-vir/tree/fix/iris-widget-errors),
two commits above the PR #171/Lean 4.32.2 compatibility checkpoint `be6931c`.
The separate remote `feat/module-system-v432` branch was not rewritten.

- `b6eed32`: render plain RPC records using their message and code, preserving
  native errors and aggregate cleanup failures. Unknown/cyclic/unprintable
  values cannot cause error formatting itself to throw.
- `8032fd3`: defer package polling until a widget is installed. Previously a
  polling tick could compare against the empty initial revision and supersede
  a slow initial load repeatedly. A real-server browser run with the normal
  1-second polling interval reproduced the resulting loading loop.

The polling failure was found independently. It is not yet established as the
cause of the user's reported RPC error. This fix covers initial-load starvation;
it does not claim comprehensive hot-reload or server-restart recovery.

Both fixes affect the JavaScript shell only. The Lean toolchain, display schema,
native RPC references and generated Wasm are unchanged. Lake caching remains
enabled. The helper is under VIR's `web/src/`, which the bundle target tracks.

## Validation

From the VIR compatibility worktree:

```sh
node --test tests/infoview/widget-errors.test.mjs
git diff --check
```

The four error-formatting tests pass. The Iris browser acceptance adds a genuine
server-side invalid-package-root failure and checks that its message and
`-32602` code appear instead of `[object Object]`. The polling regression delays
real package responses by 2.2 seconds, longer than the polling interval.

From the Iris widget worktree root, with the cache environment from the runbook:

```sh
node scripts/widget-browser-smoke.mjs
IRIS_WIDGET_RELOAD_MS=1000 IRIS_WIDGET_PACKAGE_DELAY_MS=2200 \
  node scripts/widget-browser-smoke.mjs
node scripts/widget-runtime-smoke.mjs
```

For testing a VIR source worktree before repinning, `IRIS_VIR_SOURCE_DIR` can
override the shell source directory; runtime and server artifacts still come
from Iris's pinned dependency. The candidate polling/error run passed all cases
with 40 RPC calls at 360 px. Final installed-pin validation is recorded below.

After `lake update lean_vir`, the cache-enabled batch command
`lake build IrisTest.ProofMode.Widget IrisTest.ProofMode.WidgetDemo +Iris.ProofMode.Widget:vir`
and full `lake test` passed. The final tests use the installed pin, without a
source override: both browser runs passed (37/40 RPC calls), runtime smoke
verified 38 members, and both script syntax checks and `git diff --check` passed.
Wasm SHA-256 remains
`8aca7930f8f0dee9bd88ee6aceb472dab45f3ded65d52740176f6da5dbec71e2`.

## Editor follow-up

The user confirms the rebuilt widget works. If the error recurs, retain the
exact message and code above the setup hint before changing dependencies or
runtime assets. The fixes and API requests were handed to the VIR integration
coordinator in `IRIS-VIR-INTEGRATION-20260911-001`.
