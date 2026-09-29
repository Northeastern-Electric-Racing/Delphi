#!/usr/bin/env bash
# Thin capture helper for the journal skill.
# Drops a formless note into .journal/ at the workspace root (excluded from git
# via .git/info/exclude). Never touches git history, GitHub, or any other skill.
#
# Usage:
#   capture.sh "note text"                 # loose entry at journal root
#   capture.sh -c <category> "note text"   # entry inside a category subfolder
#   capture.sh -c <category>               # create an empty entry to hand-edit
set -euo pipefail

category=""
while getopts "c:" opt; do
  case "$opt" in
    c) category="$OPTARG" ;;
    *) echo "usage: capture.sh [-c category] [note text]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
text="${*:-}"

root="$(cd "$(dirname "$0")/../../../.." && pwd)"
exclude="$(git -C "$root" rev-parse --git-path info/exclude 2>/dev/null || true)"
if [ -n "$exclude" ]; then
  case "$exclude" in /*) ;; *) exclude="$root/$exclude" ;; esac
  mkdir -p "$(dirname "$exclude")"
  grep -qxF /.journal/ "$exclude" 2>/dev/null || echo /.journal/ >>"$exclude"
fi
dir="$root/.journal"
[ -n "$category" ] && dir="$dir/$category"
mkdir -p "$dir"

file="$dir/$(date +%Y-%m-%d-%H%M%S).md"
{
  echo "<!-- captured $(date -u +%Y-%m-%dT%H:%M:%SZ) -->"
  [ -n "$text" ] && echo "$text"
} >"$file"

echo "$file"
