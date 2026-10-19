#!/usr/bin/env bash
# 2.0.0: worktrees come from their own bare store at worktrees/<repo>/.bare, and repos/<repo> is a plain
# clone. Moves each old bare store at repos/<repo> there (a rename: nothing is lost) and repairs its
# worktrees' links to it; setup.sh then clones repos/<repo>. A repo with a store at both places is
# reported and left.
set -euo pipefail
for r in repos/*; do
  [ -d "$r" ] && [ "$(git -C "$r" rev-parse --is-bare-repository 2>/dev/null)" = true ] || continue
  s=worktrees/${r#repos/}/.bare
  [ ! -e "$s" ] || { echo "migrate: $r and $s are both stores; remove the worktrees $r lists (git -C $r worktree list), delete it, and re-run" >&2 && exit 1; }
  mkdir -p "${s%/.bare}" && mv "$r" "$s" && git -C "$s" worktree repair 2>/dev/null
  echo "migrate: moved the worktree store $r to $s"
done
