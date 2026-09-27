#!/usr/bin/env bash
# .delphi/setup.sh: run in a checkout of ws/<name> (the workspace root). Clones each repo listed
# under `repos:` in workspace.yml into repos/<name> (skipping ones already there) and adds /repos/
# to this clone's .git/info/exclude. Safe to re-run. Keep it bash 3.2 (macOS) and Git Bash safe:
# no bash-4 features, POSIX awk only.
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
  if [ -e "repos/$name" ]; then
    echo "repos/$name: already present"
  else
    git clone "$url" "repos/$name" </dev/null
  fi
done <<EOF
$list
EOF

exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
grep -qxF /repos/ "$exclude" 2>/dev/null || echo /repos/ >>"$exclude"
