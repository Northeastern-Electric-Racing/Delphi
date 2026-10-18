#!/usr/bin/env bash
# 0.8.0: a workspace's name is its folders' short names and its own, joined by dots (.delphi/names.sh:
# s.app.argos.argos-dev, branch ws/s.app.argos.argos-dev; was its folder's path without workspaces/,
# software/application-software/argos/argos-dev), and `workspaces:` entries (`- <name>` or `- main`)
# are copied to linked/<name>. Moves what this clone keeps under old names to the new ones, for every
# workspace on main: parked slots (.delphi/parked/<old> to .delphi/parked/<name>), read-only copies
# (linked/ws/<old> to linked/<name>, here and in each parked slot), and version records
# (delphi.<old>.* in git config). Then, if this clone is on ws/<old>, renames that branch ws/<name>
# tracking origin/ws/<name> (sync pushed both to the same commit); a local ws/<name> already there is
# replaced only if this branch has all its commits. Only renames; a name taken at both places is
# reported and left.
set -euo pipefail
git fetch -q origin 2>/dev/null || echo "migrate: could not fetch; using the last fetched" >&2
git rev-parse -q --verify refs/remotes/origin/main >/dev/null ||
  { echo "migrate: no origin/main here; git fetch origin main, then re-run setup" >&2 && exit 1; }
pairs=$(bash .delphi/names.sh refs/remotes/origin/main | awk '{ sub("/workspaces/", "/", $2); print $2 "|" $1 }') # <old>|<name>
move() { # <from> <to>
  [ -e "$1" ] || return 0
  if [ -e "$2" ]; then echo "migrate: $1 and $2 both exist; left $1 (move what you need by hand)" >&2 && return 0; fi
  mkdir -p "$(dirname "$2")" && mv "$1" "$2" && echo "migrate: moved $1 to $2"
}
for p in $pairs; do
  old=${p%|*} n=${p#*|}
  move ".delphi/parked/$old" ".delphi/parked/$n"
  (cd .delphi/parked 2>/dev/null && rmdir -p "${old%/*}" 2>/dev/null) || true # the old name's emptied folders
  if git config --get-regexp "^delphi\\.$old\\." >/dev/null; then
    if git config "delphi.$n.version" >/dev/null; then git config --remove-section "delphi.$old"
    else git config --rename-section "delphi.$old" "delphi.$n"; fi
  fi
done
for slot in . $(for p in $pairs; do [ ! -d ".delphi/parked/${p#*|}" ] || echo ".delphi/parked/${p#*|}"; done); do
  for p in $pairs; do
    old=${p%|*}
    move "$slot/linked/ws/$old" "$slot/linked/${p#*|}"
    (cd "$slot/linked" 2>/dev/null && rmdir -p "ws/${old%/*}" 2>/dev/null) || true
  done
done

cur=$(git branch --show-current)
for p in $pairs; do
  n=${p#*|}
  [ "$cur" = "ws/${p%|*}" ] || continue
  if git rev-parse -q --verify "refs/heads/ws/$n" >/dev/null; then
    git merge-base --is-ancestor "ws/$n" HEAD ||
      { echo "migrate: local ws/$n has commits $cur doesn't; merge or delete it (git branch -D ws/$n), then re-run setup" >&2 && exit 1; }
  fi
  git branch -M "$cur" "ws/$n"
  if git rev-parse -q --verify "refs/remotes/origin/ws/$n" >/dev/null; then
    git branch -q -u "origin/ws/$n" "ws/$n"
    echo "migrate: renamed this branch $cur to ws/$n, tracking origin/ws/$n"
  else echo "migrate: renamed this branch $cur to ws/$n; once CI creates origin/ws/$n: git branch -u origin/ws/$n"; fi
done
