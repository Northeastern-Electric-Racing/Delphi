#!/usr/bin/env bash
# .delphi/switch.sh <workspace>|main: move this clone to Delphi's ws/<workspace> (or main). A workspace
# is named by its place in the tree (software/application-software/argos/argos-dev; ws/ in front is
# fine), or by its last part alone (argos-dev) if only one workspace ends in it. Refuses if
# tracked files have changes (they would follow the switch), fetches the branch, switches to it (the
# local branch, else a new one tracking origin), fast-forwards it to origin, then runs the new
# workspace's .delphi/setup.sh (none for main). The post-checkout hook (.delphi/park.sh) parks this workspace's
# repos/, worktrees/, references/ and linked/ and restores the new one's. Runs on bash 3.2 and Git Bash.
set -euo pipefail
{ # one block, so bash has read all of it before the switch replaces this file
  cd "$(dirname "$0")/.."
  name=${1:?usage: switch.sh <workspace>|main}
  name=${name#ws/} ref=ws/${name#ws/}
  case "$name" in main) ref=main ;; "" | [-/]* | */ | *//* | *[!a-z0-9/-]*) echo "switch: bad workspace name '$1'" >&2 && exit 1 ;; esac
  if [ "$ref" != main ] && [ "$name" = "${name##*/}" ]; then # its last part alone: find the one workspace it names
    git fetch -q origin '+refs/heads/ws/*:refs/remotes/origin/ws/*' || { echo "switch: could not fetch the ws/* branches" >&2 && exit 1; }
    ref=$(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ws/ | grep "^ws/.*/$name\$" || true) # not ws/<name>: an old name
    [ -n "$ref" ] && [ "$(echo "$ref" | wc -l)" -eq 1 ] ||
      { echo "switch: no one workspace ends in '$name' (found: $(echo "${ref:-none}" | tr '\n' ' ')); give its full name" >&2 && exit 1; }
  fi
  git diff --quiet HEAD -- || { echo "switch: commit or set aside your changes first (git status)" >&2 && exit 1; }
  git fetch -q origin "+refs/heads/$ref:refs/remotes/origin/$ref" || { echo "switch: could not fetch $ref" >&2 && exit 1; }
  git switch -q "$ref"
  git merge -q --ff-only "origin/$ref" 2>/dev/null || echo "switch: $ref has diverged from origin; not fast-forwarded" >&2
  [ ! -f workspace.yml ] || bash .delphi/setup.sh
  echo "switch: on $ref"
  exit
}
