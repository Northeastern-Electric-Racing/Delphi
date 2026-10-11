#!/usr/bin/env bash
# capture.sh <workspace-root> [-c <category>] [note text]: write a timestamped journal entry to
# .journal/[<category>/] at the workspace root (adding /.journal/ to .git/info/exclude once) and print
# its path. An empty entry is created when no text is given. Never touches git history, GitHub, or
# other skills.
set -euo pipefail
usage="usage: capture.sh <workspace-root> [-c <category>] [note text]"
root=${1:?$usage} && shift
[ -f "$root/.delphi/paths.sh" ] || { echo "capture: '$root' is not a Delphi workspace root" >&2 && exit 2; }
# shellcheck source=/dev/null
. "$root/.delphi/paths.sh"
dir=$DELPHI_ROOT/.journal
[ "${1:-}" = -c ] && dir=$dir/${2:?$usage} && shift 2
exclude=$(git -C "$DELPHI_ROOT" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null || true)
[ -z "$exclude" ] || grep -qxF /.journal/ "$exclude" 2>/dev/null || { mkdir -p "${exclude%/*}" && echo /.journal/ >>"$exclude"; }
mkdir -p "$dir"
file=$dir/$(date +%Y-%m-%d-%H%M%S).md
{ echo "<!-- captured $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"; [ $# -eq 0 ] || echo "$*"; } >"$file"
echo "$file"
