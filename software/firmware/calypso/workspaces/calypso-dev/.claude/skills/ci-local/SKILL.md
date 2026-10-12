---
name: ci-local
description: Run Calypso's CI checks (build, test, fmt, clippy) locally, in a Linux container on macOS. Use before pushing or when CI fails.
---

In `W=worktrees/calypso/<branch>`:

- Linux: `(cd $W && cargo build --all && cargo test --all && cargo fmt --all --check && cargo clippy --all -- -D warnings)`.
- macOS (the main crate needs socketcan), in the background, ~2 minutes:
  ```
  (cd $W && docker run --rm -v "$PWD":/w -w /w -e CARGO_TARGET_DIR=/w/target-linux rust:latest bash -c \
    'rustup component add clippy rustfmt >/dev/null 2>&1; set -e; cargo build --all; cargo test --all; cargo fmt --all --check; cargo clippy --all -- -D warnings')
  ```
  Natively, `cargo test -p calypso-sim` works.

Report where each step ran and any failing output. Fix clippy findings in code, not with `#[allow]`.
