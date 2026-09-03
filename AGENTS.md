# Repository Instructions

## Scope

- The repository contains two Lake workspaces: `Iris/` and `IrisMath/`.
- Core proof-mode code lives under `Iris/Iris/ProofMode/`; its tests live under
  `Iris/IrisTest/`.
- Keep generated build products and downloaded packages out of Git.

## Git workflow

- Do implementation work in a linked worktree at `.worktrees/<task_id>` and
  keep the primary checkout as a stable base.
- Use a focused branch such as `feat/<task_id>`, `fix/<task_id>`, or
  `docs/<task_id>`.
- Preserve unrelated changes. Do not push, open a pull request, remove a
  worktree, or delete a branch unless the maintainer asks.

## Lean workflow

- Use the toolchain pinned by each workspace's `lean-toolchain` file.
- Keep Lake's local artifact cache enabled. In restricted environments, set
  `LAKE_CACHE_DIR` to an explicitly provided writable cache directory.
- Run Iris commands from `Iris/` and IrisMath commands from `IrisMath/`.
- Use `lean-beam` for focused inspection and single-module development checks.
  After every saved Lean edit, update the file before the next version-bound
  probe; use `sync` for diagnostics and `save` for a single-module checkpoint.
- Use `lake build` for dependency-cone validation and final batch evidence.
- After editing Lake configuration, stop any active Lean Beam session before
  starting a new one.

## Changes and validation

- Keep changes small and follow the style of adjacent Lean modules.
- Add focused regression tests for observable behavior.
- Update user-facing documentation when syntax, display, or workflows change.
- Report the exact validation commands run and any checks that remain.
