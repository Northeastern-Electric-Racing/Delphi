#!/usr/bin/env bash
# affected.sh <repo> <branch> [<base>]: print the demos to rerun in <branch>'s worktree of <repo>: each
# *.demo.js that changed since its merge base with <base> (default origin/HEAD), or whose `// covers:` line
# names a path fragment found in a changed file's path. Uncommitted and new files count as changed.
set -euo pipefail
usage='usage: affected.sh <repo> <branch> [<base>]'
repo=${1:?$usage}; branch=${2:?$usage}; base=${3:-origin/HEAD}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root}/.delphi/paths.sh"
wt=$DELPHI_WORKTREES/$repo/$branch
[ -d "$wt" ] || { echo "affected: no worktree at worktrees/$repo/$branch (make it with new-worktree.sh)" >&2; exit 1; }
changed=$(git -C "$wt" diff --name-only "$(git -C "$wt" merge-base "$base" HEAD)" && git -C "$wt" ls-files -o --exclude-standard)
git -C "$wt" ls-files -co --exclude-standard -- '*.demo.js' | while IFS= read -r demo; do
  patterns=$(echo "$demo" && sed -n 's|^// covers:||p' "$wt/$demo" | tr -s '[:blank:]' '\n' | grep -v '^$' || true)
  ! grep -qF -- "$patterns" <<<"$changed" || { name=${demo##*/} && echo "${name%.demo.js}"; }
done
