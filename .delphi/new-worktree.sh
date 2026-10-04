#!/usr/bin/env bash
# .delphi/new-worktree.sh <repo> <branch> [<base>]: create or reuse worktrees/<repo>/<branch> from
# the store .delphi/setup.sh made at repos/<repo>, and print its path. An existing branch
# (local or on origin) is checked out; a new one starts from <base> (default: origin's default
# branch). Runs on bash 3.2 and Git Bash.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
repo=${1:?usage: new-worktree.sh <repo> <branch> [<base>]} branch=${2:?usage: new-worktree.sh <repo> <branch> [<base>]}
base=${3:-origin/HEAD} dest="$root/worktrees/$repo/$branch"
g() { git -C "$root/repos/$repo" "$@"; }
[ -d "$root/repos/$repo" ] ||
  { echo "new-worktree: no repos/$repo (list it under repos: and run .delphi/setup.sh; references are read-only)" >&2 && exit 1; }
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
