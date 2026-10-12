#!/usr/bin/env bash
# ci.sh <branch>: run rust-ci.yml's checks (build, test, fmt, clippy; all --all) in
# worktrees/calypso/<branch>, stopping at the first failure. Natively on Linux; on macOS in a
# rust:latest container (the main crate needs socketcan), building into the git-ignored target/linux.
set -euo pipefail
branch=${1:?usage: ci.sh <branch>}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root, on Delphi 0.2.0+ (pull its ws/ branch), or source <root>/.delphi/paths.sh}/.delphi/paths.sh"
w=$DELPHI_WORKTREES/calypso/$branch
[ -d "$w" ] || { echo "no worktree at $w; make it with new-worktree" >&2; exit 2; }
[ -n "$(ls -A "$w/Odyssey-Definitions" 2>/dev/null)" ] || { echo "run: git -C $w submodule update --init --recursive" >&2; exit 2; }
# shellcheck disable=SC2016
steps='set -e; for s in "build --all" "test --all" "fmt --all --check" "clippy --all -- -D warnings"; do echo "== cargo $s"; cargo $s; done'
if [ "$(uname -s)" = Linux ]; then
  (cd "$w" && bash -c "$steps")
else
  docker run --rm -v "$w":/w -w /w -e CARGO_TARGET_DIR=/w/target/linux rust:latest \
    bash -c "rustup component add clippy rustfmt >/dev/null 2>&1; $steps"
fi
