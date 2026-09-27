#!/usr/bin/env bash
# .delphi/link.sh <workspace>|main: check out another workspace (ws/<workspace>) or Delphi's main
# as a detached worktree at linked/<name>/ of this clone, for reference; print its path. Re-runs
# update it to origin's latest unless you switched it to a branch. Adds /linked/ to
# .git/info/exclude. Runs on bash 3.2 and Git Bash.
set -euo pipefail
cd "$(dirname "$0")/.."
name=${1:?usage: link.sh <workspace>|main}
case "$name" in main) ref=main ;; -* | *[!a-z0-9-]*) echo "link: bad workspace name '$name'" >&2 && exit 1 ;; *) ref=ws/$name ;; esac
dest=$PWD/linked/$name
git fetch -q origin "+refs/heads/$ref:refs/remotes/origin/$ref"
if [ ! -d "$dest" ]; then
  git worktree add -q --detach "$dest" "origin/$ref"
elif git -C "$dest" symbolic-ref -q HEAD >/dev/null; then
  echo "link: linked/$name is on a branch; not updated" >&2
else
  git -C "$dest" checkout -q --detach "origin/$ref"
fi
exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
grep -qxF /linked/ "$exclude" 2>/dev/null || echo /linked/ >>"$exclude"
echo "$dest"
