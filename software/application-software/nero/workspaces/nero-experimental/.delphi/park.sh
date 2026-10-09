#!/usr/bin/env bash
# .delphi/park.sh <prev> <new> <branch-flag>: the post-checkout hook .delphi/setup.sh installs. When a
# checkout moves this clone to another workspace (the `name:` in workspace.yml; none on main), it
# parks the old workspace's repos/, worktrees/ and references/ in this checkout's git dir at
# delphi/<name>/ and brings the new one's back. Moves are renames, so every path is the same again
# once its workspace is checked out. Runs on bash 3.2 and Git Bash.
set -euo pipefail
[ "${3:-0}" = 1 ] || exit 0
name() { git show "$1:workspace.yml" 2>/dev/null | awk '/^name:/ { print $2; exit }' || true; }
old=$(name "$1") new=$(name "$2")
[ "$old" != "$new" ] || exit 0
top=$(git rev-parse --show-toplevel) park=$(git rev-parse --absolute-git-dir)/delphi
for d in repos worktrees references; do
  if [ -n "$old" ] && [ -e "$top/$d" ]; then
    if [ -e "$park/$old/$d" ]; then echo "delphi: $park/$old/$d exists; left $d/ in place" >&2
    else mkdir -p "$park/$old" && mv "$top/$d" "$park/$old/$d" || echo "delphi: could not park $d/" >&2; fi
  fi
  if [ -n "$new" ] && [ -e "$park/$new/$d" ]; then
    if [ -e "$top/$d" ]; then echo "delphi: $d/ is in the way; $new's is still at $park/$new/$d" >&2
    else mv "$park/$new/$d" "$top/$d" || echo "delphi: could not restore $d/ from $park/$new/$d" >&2; fi
  fi
done
