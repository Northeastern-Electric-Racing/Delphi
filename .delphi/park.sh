#!/usr/bin/env bash
# .delphi/park.sh <prev> <new> <branch-flag>: run by the post-checkout hook .delphi/setup.sh writes,
# from the worktree that checked out. .delphi/ is on every branch, main included, so the hook always
# finds it, the version just checked out. When a checkout moves this clone to another workspace
# (the `name:` in workspace.yml, its place in the tree; none on main), it parks the old workspace's
# root folders (the ones .delphi/paths.sh names, .journal/, and those under `park:` in the workspace.yml
# of the branch it leaves) at .delphi/parked/<name>/ (git-ignored by .delphi/.gitignore), and brings
# back everything parked for the new one. A name from before workspaces were named by
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
parks() { # <commit>: the root folders its workspace parks
  echo repos worktrees references linked .journal
  git show "$1:workspace.yml" 2>/dev/null | awk '/^[^[:space:]#]/ { s = /^park:/; next }
    s && /^[[:space:]]+-/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); print }' || true
}
[ -z "$old" ] || for d in $(parks "$1"); do
  case "$d" in */* | . | .. | .git | .delphi) echo "delphi: won't park '$d' (park: takes folder names at the root)" >&2 && continue ;; esac
  [ -e "$top/$d" ] || continue
  if [ -e "$park/$old/$d" ]; then echo "delphi: $park/$old/$d exists; left $d/ in place" >&2
  else mkdir -p "$park/$old" && mv "$top/$d" "$park/$old/$d" || echo "delphi: could not park $d/" >&2; fi
done
shopt -s nullglob dotglob
[ -z "$new" ] || for src in "$park/$new"/*; do
  d=${src##*/}
  if [ -e "$top/$d" ]; then echo "delphi: $d/ is in the way; $new's is still at $src" >&2
  else mv "$src" "$top/$d" || echo "delphi: could not restore $d/ from $src" >&2; fi
done
[ -z "$new" ] || (cd "$park" 2>/dev/null && rmdir -p "$new" 2>/dev/null) || true # once all back, drop the empty slot
