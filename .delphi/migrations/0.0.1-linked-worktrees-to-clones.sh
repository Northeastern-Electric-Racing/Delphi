#!/usr/bin/env bash
# 0.0.1: linked/<name> used to be a worktree of this clone (.delphi/link.sh); setup.sh now makes it a
# read-only copy. Deletes each old one, and its registration in .git/worktrees/, if nothing in it can
# be lost: no uncommitted or untracked files, and its commit is on a branch. setup.sh then makes it a
# copy. Stops, changing nothing more, at the first one that isn't safe to delete.
set -euo pipefail
for d in linked/*/; do
  d=${d%/}
  [ -f "$d/.git" ] || continue # a read-only copy already, or no checkout at all
  admin=$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null) || admin=
  case "$admin" in */.git/worktrees/*) ;; *)
    echo "migrate: $d is a broken worktree; move out anything you need, delete it, re-run setup" >&2 && exit 1 ;;
  esac
  [ -z "$(git -C "$d" status --porcelain)" ] ||
    { echo "migrate: $d has uncommitted changes; commit or move them, then re-run setup" >&2 && exit 1; }
  [ -n "$(git -C "$d" for-each-ref --count=1 --contains HEAD refs/heads refs/remotes)" ] ||
    { echo "migrate: $d has commits on no branch; git -C $d switch -c <branch>, then re-run setup" >&2 && exit 1; }
  rm -rf "$d" "$admin"
  echo "migrate: removed $d, an old link.sh worktree (nothing lost); setup.sh makes it a read-only copy"
done
