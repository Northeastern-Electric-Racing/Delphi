#!/usr/bin/env bash
# .delphi/switch.sh <workspace>|main: move this clone to Delphi's ws/<workspace> (or main). Refuses if
# tracked files have changes (they would follow the switch), fetches the branch, switches to it (the
# local branch, else a new one tracking origin), fast-forwards it to origin, then runs the new
# workspace's .delphi/setup.sh. The post-checkout hook (.delphi/park.sh) parks this workspace's
# repos/, worktrees/, references/ and linked/ and restores the new one's. Runs on bash 3.2 and Git Bash.
set -euo pipefail
{ # one block, so bash has read all of it before the switch replaces this file
  cd "$(dirname "$0")/.."
  name=${1:?usage: switch.sh <workspace>|main}
  case "$name" in main) ref=main ;; -* | *[!a-z0-9-]*) echo "switch: bad workspace name '$name'" >&2 && exit 1 ;; *) ref=ws/$name ;; esac
  git diff --quiet HEAD -- || { echo "switch: commit or set aside your changes first (git status)" >&2 && exit 1; }
  git fetch -q origin "+refs/heads/$ref:refs/remotes/origin/$ref" || { echo "switch: could not fetch $ref" >&2 && exit 1; }
  git switch -q "$ref"
  git merge -q --ff-only "origin/$ref" 2>/dev/null || echo "switch: $ref has diverged from origin; not fast-forwarded" >&2
  [ ! -f .delphi/setup.sh ] || bash .delphi/setup.sh
  echo "switch: on $ref"
  exit
}
