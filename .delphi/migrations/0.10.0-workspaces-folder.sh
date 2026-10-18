#!/usr/bin/env bash
# 0.10.0: the clones of the workspaces under `workspaces:` moved from linked/<name> to workspaces/<name>.
# Moves each one here (a leftover worktree with git worktree move), then removes linked/ if that
# empties it. Parked ones are their own workspace's, moved when it's set up. Only renames; a name taken
# at both places is reported and left.
set -euo pipefail
[ -d linked ] || exit 0
mkdir -p workspaces
for d in linked/*; do
  [ -e "$d" ] || continue
  to=workspaces/${d#linked/}
  if [ -e "$to" ]; then echo "migrate: $d and $to both exist; left $d (move what you need by hand)" >&2 && continue; fi
  if [ -f "$d/.git" ]; then git worktree move "$d" "$to"; else mv "$d" "$to"; fi
  echo "migrate: moved $d to $to"
done
rmdir linked 2>/dev/null || true
