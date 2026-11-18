#!/usr/bin/env bash
# run.sh <repo> <branch> <url> [--video] [--from <step>] [<demo>...]: run the demos (each *.demo.js, or the
# named ones) in <branch>'s worktree of <repo> against the app at <url>, with engine.js: stills by default,
# --video for an MP4 per demo; --from replays from that step. Output goes to pictures/<branch>/demo/<demo>/.
# Exits 1 if a step failed.
set -euo pipefail
usage='usage: run.sh <repo> <branch> <url> [--video] [--from <step>] [<demo>...]'
repo=${1:?$usage}; branch=${2:?$usage}; url=${3:?$usage}; shift 3
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root}/.delphi/paths.sh"
here=$(cd "$(dirname "$0")" && pwd)
wt=$DELPHI_WORKTREES/$repo/$branch
[ -d "$wt" ] || { echo "run: no worktree at worktrees/$repo/$branch (make it with new-worktree.sh)" >&2; exit 1; }
mode=stills from=
while [ $# -gt 0 ]; do
  case $1 in --video) mode=video ;; --from) from=${2:?$usage}; shift ;; *) break ;; esac
  shift
done
all=$(git -C "$wt" ls-files -co --exclude-standard -- '*.demo.js')
files=()
if [ $# -eq 0 ]; then
  while IFS= read -r f; do [ -z "$f" ] || files+=("$wt/$f"); done <<<"$all"
fi
for name in "$@"; do
  f=$(awk -v n="$name.demo.js" '{ b = $0; sub(/.*\//, "", b) } b == n { print; exit }' <<<"$all")
  [ -n "$f" ] || { echo "run: no $name.demo.js in worktrees/$repo/$branch" >&2; exit 1; }
  files+=("$wt/$f")
done
[ ${#files[@]} -gt 0 ] || { echo "run: no *.demo.js in worktrees/$repo/$branch (start one with new.sh)" >&2; exit 1; }
for f in "${files[@]}"; do
  ! grep -q '^// covers: TODO' "$f" || echo "run: set the covers: line in ${f#"$wt"/} (see its comment)" >&2
done
NODE_PATH=$(npm root -g 2>/dev/null || true)${NODE_PATH:+:$NODE_PATH}; export NODE_PATH
node -e "require('playwright')" 2>/dev/null ||
  { echo "run: needs Playwright for node: npm i -g playwright && npx playwright install chromium" >&2; exit 1; }
[ $mode = stills ] || command -v ffmpeg >/dev/null || { echo "run: --video needs ffmpeg on PATH" >&2; exit 1; }
node "$here/engine.js" "$DELPHI_ROOT/pictures/$branch/demo" "${url%/}" "$mode" "$from" "${files[@]}"
