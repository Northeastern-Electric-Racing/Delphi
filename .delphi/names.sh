#!/usr/bin/env bash
# .delphi/names.sh [<rev>]: print `<name> <folder>` for each workspace folder software/**/workspaces/<leaf>/
# in <rev> (default: the working tree here, a main checkout), sorted by folder. A workspace's name is
# the short name of each folder from software/ down to its project folder, then <leaf>, joined by
# dots (software/application-software/argos/workspaces/argos-dev -> s.app.argos.argos-dev; branch
# ws/<name>). A folder's short name is the one line in its `short-name` file, else its own name.
# Prints nothing where there's no software/ (a ws/* branch). Bash 3.2 and Git Bash safe.
set -euo pipefail
rev=${1:-}
folders() {
  if [ -n "$rev" ]; then git ls-tree -r --name-only "$rev" -- software
  else find software -type f -name workspace.yml 2>/dev/null; fi | sed -nE 's#^(software/(.+/)?workspaces/[^/]+)/workspace\.yml$#\1#p' | LC_ALL=C sort
}
short() { # <folder>: its short name
  local s
  if [ -n "$rev" ]; then s=$(git show "$rev:$1/short-name" 2>/dev/null || true); else s=$(cat "$1/short-name" 2>/dev/null || true); fi
  s=$(printf '%s' "$s" | tr -d '[:space:]')
  echo "${s:-${1##*/}}"
}
for f in $(folders); do
  n="" p=""
  for part in $(echo "${f%/workspaces/*}" | tr / ' '); do
    p=${p:+$p/}$part
    n="$n$(short "$p")."
  done
  echo "$n${f##*/} $f"
done
