#!/usr/bin/env bash
# .delphi/new-worktree.sh <repo> <branch> [<base>]: create or reuse worktrees/<repo>/<branch> from
# the store .delphi/setup.sh made at worktrees/<repo>/.bare, and print its path. An existing branch
# (local or on origin) is checked out; a new one starts from <base> (default: origin's default
# branch). Runs on bash 3.2 and Git Bash.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
repo=${1:?usage: new-worktree.sh <repo> <branch> [<base>]} branch=${2:?usage: new-worktree.sh <repo> <branch> [<base>]}
base=${3:-origin/HEAD} dest="$root/worktrees/$repo/$branch"
g() { git -C "$root/worktrees/$repo/.bare" "$@"; }
g fetch -q origin
if [ -d "$dest" ]; then :
elif g rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
  g worktree add -q "$dest" "$branch"
elif g rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
  g worktree add -q --track -b "$branch" "$dest" "origin/$branch"
else
  g worktree add -q --no-track -b "$branch" "$dest" "$base"
fi
echo "$dest"
