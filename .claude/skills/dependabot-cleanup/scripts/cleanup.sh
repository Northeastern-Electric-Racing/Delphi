#!/usr/bin/env bash
# cleanup.sh <pr>...: for each merged or closed Dependabot PR, remove worktrees/argos/<its branch>,
# the local branch and the branch on GitHub, then empty folders left under worktrees/argos/.
# Refuses open PRs. Prints one line per PR.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
[ $# -gt 0 ] || { echo "usage: cleanup.sh <pr>..." >&2 && exit 2; }
g() { git -C "$DELPHI_REPOS/argos" "$@"; }
for pr in "$@"; do
  read -r state branch author < <(gh pr view "$pr" -R "$R" --json state,headRefName,author -q '"\(.state) \(.headRefName) \(.author.login)"')
  case $author in *dependabot*) ;; *) echo "#$pr skipped: author is $author" && continue ;; esac
  [ "$state" != OPEN ] || { echo "#$pr skipped: still open" && continue; }
  wt=$DELPHI_WORKTREES/argos/$branch
  [ ! -d "$wt" ] || g worktree remove --force "$wt"
  g branch -q -D "$branch" 2>/dev/null || true
  gh api -X DELETE "repos/$R/git/refs/heads/$branch" >/dev/null 2>&1 && remote="remote deleted" || remote="no remote branch"
  echo "#$pr cleaned $branch ($remote)"
done
find "$DELPHI_WORKTREES/argos/dependabot" -name .DS_Store -delete 2>/dev/null || true
find "$DELPHI_WORKTREES/argos/dependabot" -depth -type d -empty -delete 2>/dev/null || true
g worktree prune && g fetch -q --prune origin
