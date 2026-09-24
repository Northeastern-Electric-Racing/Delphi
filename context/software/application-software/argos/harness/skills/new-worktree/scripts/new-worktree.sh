#!/usr/bin/env bash
# new-worktree.sh <branch> — create or reuse worktrees/<branch> for repos/argos. Prints the path.
# An existing branch (local or on origin) is checked out; a new one starts from origin/develop.
set -euo pipefail

root=$(cd "$(dirname "$0")/../../../.." && pwd)
branch=${1:?usage: new-worktree.sh <branch>}
repo="$root/repos/argos" dest="$root/worktrees/$branch"

git -C "$repo" fetch -q origin
if [ -d "$dest" ]; then :
elif git -C "$repo" rev-parse -q --verify "$branch" > /dev/null || git -C "$repo" rev-parse -q --verify "origin/$branch" > /dev/null; then
  git -C "$repo" worktree add -q "$dest" "$branch"
else
  git -C "$repo" worktree add -q --no-track -b "$branch" "$dest" origin/develop
fi
echo "$dest"
