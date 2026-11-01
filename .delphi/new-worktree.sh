#!/usr/bin/env bash
# .delphi/new-worktree.sh <repo> <branch> [<base>]: create or reuse worktrees/<repo>/<branch> from
# the bare store .delphi/setup.sh made at worktrees/<repo>/.bare (never the clone at repos/<repo>), and
# print its path. An existing branch (local or on origin) is checked out; a new one starts from <base>
# (default: origin's default branch; a <base> only on origin is used as origin/<base>), and the script
# fails unless the worktree ends up on <branch>. Runs on bash 3.2 and Git Bash.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=paths.sh
. "$(dirname "$0")/paths.sh"
repo=${1:?usage: new-worktree.sh <repo> <branch> [<base>]} branch=${2:?usage: new-worktree.sh <repo> <branch> [<base>]}
base=${3:-origin/HEAD} dest="$DELPHI_WORKTREES/$repo/$branch"
store=$DELPHI_WORKTREES/$repo/.bare
g() { git -C "$store" "$@"; }
[ -d "$store" ] ||
  { echo "new-worktree: no worktrees/$repo/.bare (list it under repos: and run .delphi/setup.sh; references are read-only)" >&2 && exit 1; }
g fetch -q origin
if [ -d "$dest" ]; then :
elif g rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
  g worktree add -q "$dest" "$branch"
elif g rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
  g worktree add -q --track -b "$branch" "$dest" "origin/$branch"
else # a <base> only on origin goes as origin/<base>: given the bare name, Git 2.43 checks out <base>, not -b
  if ! g rev-parse -q --verify "$base^{commit}" >/dev/null && g rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null; then
    base=origin/$base
  fi
  g worktree add -q --no-track -b "$branch" "$dest" "$base"
fi
on=$(git -C "$dest" branch --show-current)
[ "$on" = "$branch" ] || { echo "new-worktree: worktrees/$repo/$branch is on '${on:-a detached HEAD}', not '$branch';" \
  "remove it (git -C worktrees/$repo/.bare worktree remove ../$branch) and rerun" >&2 && exit 1; }
echo "$dest"
