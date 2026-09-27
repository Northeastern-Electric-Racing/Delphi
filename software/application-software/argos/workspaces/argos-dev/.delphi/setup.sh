#!/usr/bin/env bash
# .delphi/setup.sh: run in a checkout of ws/<name> (the workspace root). For each repo listed under
# `repos:` in workspace.yml, fetches it into a bare store at worktrees/<name>/.bare and checks out
# its default branch as a worktree at worktrees/<name>/<default-branch> (skipping repos already
# there), then adds /worktrees/ to this clone's .git/info/exclude. Safe to re-run. Keep it bash 3.2
# (macOS) and Git Bash safe: no bash-4 features, POSIX awk only.
set -euo pipefail
cd "$(dirname "$0")/.."

list=$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /^repos:/ { r = 1; next }
  /^[^[:space:]]/ { r = 0 }
  r { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); n = index($0, ":")
      if (n) print substr($0, 1, n - 1), substr($0, n + 1) }' workspace.yml)

while read -r name url; do
  [ -n "$name" ] || continue
  case "$name" in . | .. | *[!A-Za-z0-9._-]*) echo "setup: skipping unsafe repo name '$name'" >&2 && continue ;; esac
  store=worktrees/$name/.bare
  if [ -e "$store" ]; then
    echo "worktrees/$name: already present"
    continue
  fi
  git init -q --bare "$store"
  git -C "$store" remote add origin "$url"
  git -C "$store" fetch -q origin </dev/null
  git -C "$store" remote set-head origin -a >/dev/null </dev/null
  def=$(git -C "$store" symbolic-ref --short refs/remotes/origin/HEAD)
  git -C "$store" worktree add -q --track -b "${def#origin/}" "$PWD/worktrees/$name/${def#origin/}" "$def"
  echo "worktrees/$name/${def#origin/}: default branch checked out"
done <<EOF2
$list
EOF2

exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
grep -qxF /worktrees/ "$exclude" 2>/dev/null || echo /worktrees/ >>"$exclude"
