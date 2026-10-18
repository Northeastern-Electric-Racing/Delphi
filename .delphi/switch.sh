#!/usr/bin/env bash
# .delphi/switch.sh <workspace>|main: move this clone to Delphi's ws/<workspace> (or main). A workspace
# is named by .delphi/names.sh (s.app.argos.argos-dev; ws/ in front is fine). Refuses if tracked files have changes (they would follow the
# switch), fetches the branch, switches to it (the local branch, else a new one tracking origin),
# fast-forwards it to origin, then runs the new workspace's .delphi/setup.sh (none for main). The
# post-checkout hook (.delphi/park.sh) parks this workspace's repos/, worktrees/, references/ and
# linked/ and restores the new one's. Runs on bash 3.2 and Git Bash.
# .delphi/switch.sh --list: fetch main and the ws/* branches, then print main and each workspace on
# main that has its branch, one a line, as `<name> <its project folder>`, `* ` before this clone's
# and two spaces before the others (the delphi mod's /ws-delphi pane reads it).
set -euo pipefail
{ # one block, so bash has read all of it before the switch replaces this file
  cd "$(dirname "$0")/.."
  if [ "${1:-}" = --list ]; then
    git fetch -q --prune origin '+refs/heads/main:refs/remotes/origin/main' '+refs/heads/ws/*:refs/remotes/origin/ws/*' ||
      echo "switch: could not fetch main and the ws/* branches; listing the ones last fetched" >&2
    { echo main && bash .delphi/names.sh refs/remotes/origin/main | while read -r n f; do
        ! git rev-parse -q --verify "refs/remotes/origin/ws/$n" >/dev/null || echo "$n ${f%/workspaces/*}"
      done; } | awk -v here="$(git branch --show-current)" '{ print (($1 == "main" ? "main" : "ws/" $1) == here ? "* " : "  ") $0 }'
    exit
  fi
  name=${1:?usage: switch.sh <workspace>|main}
  name=${name#ws/} ref=ws/${name#ws/}
  case "$name" in main) ref=main ;; "" | [-.]* | *. | *..* | *[!a-z0-9.-]*) echo "switch: bad workspace name '$1'" >&2 && exit 1 ;; esac
  git diff --quiet HEAD -- || { echo "switch: commit or set aside your changes first (git status)" >&2 && exit 1; }
  git fetch -q origin "+refs/heads/$ref:refs/remotes/origin/$ref" || { echo "switch: could not fetch $ref" >&2 && exit 1; }
  git switch -q "$ref"
  git merge -q --ff-only "origin/$ref" 2>/dev/null || echo "switch: $ref has diverged from origin; not fast-forwarded" >&2
  [ ! -f workspace.yml ] || bash .delphi/setup.sh
  echo "switch: on $ref"
  exit
}
