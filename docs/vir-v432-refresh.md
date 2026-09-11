# Local VIR 4.32 refreshes

## Review publication — 2026-09-11

The current Iris pin `8032fd34add0b75d4f59c82382e2a57b4c2522a4` is published
on [`fix/iris-widget-errors`](https://github.com/ejgallego/lean-vir/tree/fix/iris-widget-errors).
It contains the PR #171/Lean 4.32.2 compatibility checkpoint and the two
[shell fixes](widget-shell-errors.md). The existing remote
`feat/module-system-v432` branch was not rewritten. Generated Wasm remains a
separate build requirement, not a checked-in artifact.

The entries below retain the state and validation evidence at each earlier
refresh; their local-only/publication statements describe those checkpoints.

## PR #171 refresh — 2026-09-10

Subsequent adoption: Iris uses native RPC and now pins `8032fd3`, adding two
[shell fixes](widget-shell-errors.md) above `be6931c`. The branch-only
validation record below describes the state before that migration; see
[the native-RPC migration note](widget-native-rpc.md) for the current widget.

The local VIR branch `feat/module-system-v432` is now at
`be6931c063a675a8089f2d5ed52bb4d379d0f718`, one compatibility commit directly
over [PR #171](https://github.com/ejgallego/lean-vir/pull/171) head
`8750e1b2192a2da3ebac518c5dcd2695c10b0b39`. Nothing was pushed.

The branch is checked out in
`/home/egallego/lean/iris-lean/.worktrees/vir-pr171-v432`, a linked worktree of
the independent VIR repository in `Iris/.lake/packages/lean_vir`.
`checkpoint/module-system-v432-20260910` retains the previous `b68e442` tip.

**At the branch-refresh checkpoint, Iris had not been repinned.** Its dependency checkout, lakefile, and manifest
remained at `b68e442`. PR #171 includes #169's native-RPC migration: the then-current
Iris term-detail buttons still called the removed `ResolvedRef`, `ExprWithCtx.save`,
and `Rpc.resolve` adapters. Migrating those interactions is a separate change;
this compatibility refresh does not restore the removed adapters or change the
Iris goal model and its `Iris.ProofMode.parseIrisGoal?` provenance.

The refreshed layer retains Lean 4.32.2, matching Lean source
`f3b06c705e6c85f5314019d5d3baab0fec5b580c`, Float/extern/split-stack adaptations,
and the local typed cursor-RPC bridge. Conflict resolution keeps upstream's
native RPC session and cleanup handling. The typed-RPC test now uses
`--target-module InfoviewFixtures.TypedRpcWidget`; its obsolete import-only
source driver was removed and remains recoverable at the checkpoint.

Validation ran in a fresh worktree. Subsequent checks explicitly enabled both
cache reads/writes and artifact restoration:

```sh
cd /home/egallego/lean/iris-lean/.worktrees/vir-pr171-v432
export LAKE_ARTIFACT_CACHE=true
export LAKE_CACHE_DIR=/home/egallego/.cache/mathlib
export LAKE_RESTORE_ARTIFACTS=true
lake build VirInfoview VirInfoviewFixtures VirBrowserFixtures VirRuntimeFixtures VirExamples vir_irpkg
npm run check:lean-bindings
npm run test:bindings:unit
LEAN4_SRC=/home/egallego/lean/iris-lean/.worktrees/proof-mode-widget/Iris/.lake/packages/lean_vir/third_party/lean4-src WASI_SDK_PATH=/home/egallego/lean/vir/.tools/wasi-sdk VIR_SKIP_PACKAGES=1 npm run probe:upstream
npm run build:demo-package
npm run test:infoview
npm run test:infoview:browser
node --test tests/runtime/collection-type-fidelity.test.mjs tests/runtime/object-type-fidelity.test.mjs tests/runtime/promise-type-fidelity.test.mjs tests/infoview/rpc-test-support.test.mjs tests/infoview/rpc-browser-harness.test.mjs
node tests/runtime/runner.mjs module-input module-cli
node scripts/packages/generate-browser-package.mjs --package fixtures-basic --package pretty-printer --package fixtures-lean --copy-public
node tests/runtime/infoview-rpc-promise-smoke.mjs
git diff --check
```

These checks passed: the fresh Lean build (including positive and negative
binding-type fixtures), generated bindings, 94 binding unit tests, 31 focused
host/RPC harness tests, module snapshots, typed-RPC packaging/JSON, and the
infoview shell smoke. Real Chromium/Lean-server acceptance passed for native
RPC and shell lifetime handling, including actual references, cancellation,
late results, React Strict Mode replay, configuration replacement, and hard
disposal. The module-input and CLI runtime checks and the native RPC/Promise
runtime smoke also passed. This tests VIR fixtures, not a migrated Iris widget.

The matching Wasm built with zero unresolved strict-link symbols. Its SHA-256
is `8aca7930f8f0dee9bd88ee6aceb472dab45f3ded65d52740176f6da5dbec71e2`.
The shared Lean source checkout was read without modification. An initial
infoview test started before Wasm generation finished and reported the missing
artifact; it passed once the build completed. The RPC/Promise smoke likewise
needed the three public fixture packages read by its shared setup helper;
those were generated before the successful rerun. No downloader or cache-policy
fix was made. The full VIR `npm test` suite was not run.

The existing Iris `node scripts/widget-runtime-smoke.mjs` also passed again:
32 verified package members and the real Lean factory/mount with React SSR.
That evidence belongs to the retained `b68e442` dependency, not the PR #171
branch. Existing design/gallery work was preserved.

## Main refresh — 2026-09-09

The existing `feat/module-system-v432` branch in
`Iris/.lake/packages/lean_vir` was refreshed onto fetched upstream main, retaining
Lean 4.32.2. This is a local-only update; no branch was pushed. Iris's local
lakefile and manifest now point to the refreshed commit, which a fresh remote
checkout cannot fetch until the VIR branch is published.

| Identity | Revision |
| --- | --- |
| VIR upstream main at refresh | `44eaeba` (landed module-system #166 and binding cleanup #168) |
| Refreshed compatibility commit | `b68e442689274cb7be7a8d5f3167f201ed97cf9c` |
| Previous published checkpoint | `ea9ba047aef4bc6cbb24c24d74a51af50dcce66c` |
| Local recovery branch in the VIR checkout | `checkpoint/module-system-v432-20260909` at the previous checkpoint |
| Lean toolchain | `leanprover/lean4:v4.32.2` |
| Matching Lean source | `f3b06c705e6c85f5314019d5d3baab0fec5b580c` |
| Generated Wasm SHA-256 | `8023fcb27d12833df94a1b4170c73f7926ae2a3d7757cad9d1b195b7d27327f6` |

The single compatibility commit was replayed over main, not over the old PR
history. Resolve the Lake configuration conflict in favor of upstream's
package-relative bundle target; retain our typed-RPC fixture registration.
The infoview test command now runs both upstream's module-snapshot regression
and the typed-RPC tests. No Iris widget implementation or display-model change
was required.

The remaining local layer is Lean/source version compatibility, Float boundary
coverage, native extern discovery, the split-stack Wasm build flag, and the
typed cursor-RPC/recursive `RpcJson` bridge used by Iris. It does not include
other in-flight VIR branches or repin other consumers.

## Cache-backed packaging

A clean downstream build exposed a concrete path-resolution limitation:

- Lake compiled the widget using `Widget.setup.json`, whose `importArts` maps
  `Iris.ProofMode.Widget.Model` to existing files in the artifact cache.
- VIR's standalone frontend searched the conventional build-directory path
  instead, where `Model.olean` had not been materialized.
- Repeating the build with `LAKE_RESTORE_ARTIFACTS=true` restored cached files
  to those paths and successfully generated the package set.

Keep `enableArtifactCache = true`. This supported, per-command restoration
option neither disables nor clears the cache, and does not change the
downloader. Teaching the generator to consume Lake's artifact mapping is an
upstream follow-up, not part of this compatibility refresh. The earlier weak
internet incident is separate from this reproducible missing-local-path error.

## Validation

In the VIR checkout, with `LAKE_CACHE_DIR=/home/egallego/.cache/mathlib`:

```sh
lake build VirInfoview VirInfoviewFixtures
VIR_SKIP_PACKAGES=1 npm run probe:upstream
npm run build:demo-package
LAKE_RESTORE_ARTIFACTS=true npm run test:infoview
```

The runtime rebuilt with zero unresolved strict-link symbols. The infoview
checks passed, including module snapshots, recursive JSON conversion, the
typed-RPC package contract, and the infoview shell smoke. Only the demo-host
browser package was regenerated; unrelated benchmark/browser artifacts were
not refreshed.

In `Iris/`, with the same cache directory:

```sh
lake update lean_vir
lake clean
LAKE_RESTORE_ARTIFACTS=true lake build IrisTest.ProofMode.WidgetDemo IrisTest.ProofMode.Widget +Iris.ProofMode.Widget:vir
LAKE_RESTORE_ARTIFACTS=true lake test
```

The first post-clean packaging attempt without restoration failed as described
above; the restored build and full test run passed. The exact widget package
contains 32 members, format 11, 945 declarations (863 IR / 82 native), and two
interface exports. Lean tests exercise the elaborated `parseIrisGoal?` mapping.

From the worktree root:

```sh
node scripts/widget-runtime-smoke.mjs
node docs/notation-gallery/smoke.mjs
git diff --check
```

The runtime smoke verifies package-member hashes, loads the matching Wasm,
calls the real Lean component factory and mount, renders through React SSR,
and checks contexts, term controls, empty goals, and malformed input. It uses a
supplied test payload, not a live Lean RPC. The separate offline-gallery smoke
still passes all 90 layouts and its keyboard/copy/state checks.

Manual VS Code cursor-RPC, live term interactions, and visual acceptance of
this exact refreshed runtime remain to be checked. No fresh end-to-end editor
acceptance is implied by SSR or the gallery tests. Restart the Lean server
before opening the current demo against the regenerated runtime.
