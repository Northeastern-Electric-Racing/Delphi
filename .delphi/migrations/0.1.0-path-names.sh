#!/usr/bin/env bash
# 0.1.0: workspaces are named by their place in the tree (ws/software/application-software/argos/argos-dev,
# was ws/argos-dev), and `links:` is `workspaces:` (`- ws/<name>` or `- main`), copied to linked/<branch>.
# Moves what this clone keeps under old names to the new ones, for every workspace on main: parked
# slots (.delphi/parked/<old> and, from before that, .git/delphi/<old>) to .delphi/parked/<name>, and
# read-only copies linked/<old> to linked/ws/<name>, here and in each parked slot. Only renames; a
# name taken at both places is reported and left. Your local ws/<old> branch stays; delete it once
# you're on ws/<name>.
set -euo pipefail
git fetch -q origin main 2>/dev/null || echo "migrate: could not fetch main; using the last fetched" >&2
git rev-parse -q --verify refs/remotes/origin/main >/dev/null ||
  { echo "migrate: no origin/main here; git fetch origin main, then re-run setup" >&2 && exit 1; }
names=$(git ls-tree -r --name-only origin/main -- software |
  sed -nE 's#^(software/(.+/)?)workspaces/([^/]+)/workspace\.yml$#\1\3#p')
move() { # <from> <to>
  [ -e "$1" ] || return 0
  if [ -e "$2" ]; then echo "migrate: $1 and $2 both exist; left $1 (move what you need by hand)" >&2 && return 0; fi
  mkdir -p "$(dirname "$2")" && mv "$1" "$2" && echo "migrate: moved $1 to $2"
}
git_dir=$(git rev-parse --absolute-git-dir)
for n in $names; do
  move ".delphi/parked/${n##*/}" ".delphi/parked/$n"
  move "$git_dir/delphi/${n##*/}" ".delphi/parked/$n"
  git config --remove-section "delphi.${n##*/}" 2>/dev/null || true # its old version record
done
rmdir "$git_dir/delphi" 2>/dev/null || true
for slot in . $(for n in $names; do [ ! -d ".delphi/parked/$n" ] || echo ".delphi/parked/$n"; done); do
  for n in $names; do move "$slot/linked/${n##*/}" "$slot/linked/ws/$n"; done
done
