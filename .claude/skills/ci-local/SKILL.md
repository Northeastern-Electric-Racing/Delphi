---
name: ci-local
description: Run Calypso's CI checks (build, test, fmt, clippy) locally. Use before pushing or when CI fails.
---

`bash scripts/ci.sh <branch>` runs `rust-ci.yml`'s checks in `worktrees/calypso/<branch>`: natively on Linux, in Docker on macOS (~2 min; run it in the background). On macOS, `cargo test -p calypso-sim` also works natively for a fast loop.

Report the failing step's output. Fix clippy findings in code, not with `#[allow]`.
