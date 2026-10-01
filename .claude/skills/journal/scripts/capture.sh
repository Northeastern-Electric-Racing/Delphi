#!/usr/bin/env bash
# capture.sh [-c <category>] [note text]: write a timestamped journal entry to .journal/[<category>/]
# at the workspace root (adding /.journal/ to .git/info/exclude once) and print its path. An empty
# entry is created when no text is given. Never touches git history, GitHub, or other skills.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../../.." && pwd) && dir=$root/.journal
[ "${1:-}" = -c ] && dir=$dir/${2:?usage: capture.sh [-c <category>] [note text]} && shift 2
exclude=$(git -C "$root" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null || true)
[ -z "$exclude" ] || grep -qxF /.journal/ "$exclude" 2>/dev/null || { mkdir -p "${exclude%/*}" && echo /.journal/ >>"$exclude"; }
mkdir -p "$dir"
file=$dir/$(date +%Y-%m-%d-%H%M%S).md
{ echo "<!-- captured $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"; [ $# -eq 0 ] || echo "$*"; } >"$file"
echo "$file"
