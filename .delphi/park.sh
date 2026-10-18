#!/usr/bin/env bash
# .delphi/park.sh <prev> <new> <branch-flag>: run by the post-checkout hook .delphi/setup.sh writes,
# from the worktree that checked out. .delphi/ is on every branch, main included, so the hook always
# finds it, the version just checked out. When a checkout moves this clone to another workspace
# (the `name:` in workspace.yml, its place in the tree; none on main), it parks the old workspace's
# root folders listed in .delphi/park.list at .delphi/parked/<name>/
# (git-ignored by .delphi/.gitignore) and brings the new one's back. A name from before workspaces were named by
# path (argos-dev) is the same workspace as the path ending in it, so moving onto the renamed branch
# moves nothing. Moves are renames, so every path is the same again once its workspace is checked
# out. Runs on bash 3.2 and Git Bash.
set -euo pipefail
[ "${3:-0}" = 1 ] || exit 0
name() { git show "$1:workspace.yml" 2>/dev/null | awk '/^name:/ { print $2; exit }' || true; }
old=$(name "$1") new=$(name "$2")
[ "$old" != "$new" ] || exit 0
case "$old" in */*) ;; ?*) [ "$old" != "${new##*/}" ] || exit 0 ;; esac # renamed by path: still the same workspace
case "$new" in */*) ;; ?*) [ "$new" != "${old##*/}" ] || exit 0 ;; esac
top=$(git rev-parse --show-toplevel)
park=$top/.delphi/parked
while read -r d _; do
  case "$d" in '' | \#*) continue ;; esac
  if [ -n "$old" ] && [ -e "$top/$d" ]; then
    if [ -e "$park/$old/$d" ]; then echo "delphi: $park/$old/$d exists; left $d/ in place" >&2
    else mkdir -p "$park/$old" && mv "$top/$d" "$park/$old/$d" || echo "delphi: could not park $d/" >&2; fi
  fi
  src=$park/$new/$d
  if [ -n "$new" ] && [ -e "$src" ]; then
    if [ -e "$top/$d" ]; then echo "delphi: $d/ is in the way; $new's is still at $src" >&2
    else mv "$src" "$top/$d" || echo "delphi: could not restore $d/ from $src" >&2; fi
  fi
done <"$top/.delphi/park.list"
[ -z "$new" ] || (cd "$park" 2>/dev/null && rmdir -p "$new" 2>/dev/null) || true # once all back, drop the empty slot
