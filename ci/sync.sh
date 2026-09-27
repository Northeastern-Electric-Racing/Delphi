#!/usr/bin/env bash
# ci/sync.sh [refresh|propose] [<name>]: keep every workspace branch and main in sync (CI runs it with no
# direction on each push to main or ws/**, which does both). For each workspace folder
# software/**/workspaces/<name>/ on origin/main (or just <name>):
#   1. refresh: merge origin/main into ws/<name> with -Xsubtree=<folder> and push if the tree changed.
#      A missing ws/<name> is created as one commit whose tree is the folder and whose parent is
#      main, so its history is joined to main from the start.
#   2. propose: if ws/<name> now has changes main doesn't, build propose/<name> = origin/main + a subtree
#      merge of ws/<name>, check it, force-push it, and open or update its PR to main with gh.
# Conflicts are reported per workspace and skipped; exit 1 at the end if any. Branches whose folder
# is gone are reported, never deleted. Merges run in a temporary worktree.
set -euo pipefail
dir=both
case "${1:-}" in refresh | propose) dir=$1 && shift ;; esac
only=${1:-}
case "$only" in *[!a-z0-9-]*) echo "usage: ci/sync.sh [refresh|propose] [<workspace-name>]" >&2 && exit 2 ;; esac
root=$(cd "$(dirname "$0")/.." && pwd)

git fetch --quiet --prune origin
main=$(git rev-parse origin/main)
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" "$main"
trap 'git worktree remove --force "$wt"' EXIT
failed=0
names=" "

conflict() { # <message>: report the conflicted files, abort the merge, skip this workspace
  echo "$1 Files:" >&2
  git -C "$wt" diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  git -C "$wt" merge --abort 2>/dev/null || true # nothing to abort if the merge never started
  failed=1 ok=0
}

refresh() { # <name> <folder>: leave the worktree at the up-to-date ws/<name>
  local ws=refs/remotes/origin/ws/$1
  if ! git rev-parse --quiet --verify "$ws" >/dev/null; then
    git -C "$wt" checkout --quiet --detach \
      "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$main:$2")"
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: created from $2"
    return
  fi
  git -C "$wt" checkout --quiet --detach "$ws"
  # --no-ff: once ws commits are in main, a fast-forward would put main's whole tree on ws/<name>.
  if ! git -C "$wt" merge --quiet --no-ff --no-edit -Xsubtree="$2" \
    -m "delphi: bring main into ws/$1" "$main" >/dev/null; then
    conflict "ws/$1: CONFLICT merging main; merge main into ws/$1 in a PR (see README)."
    return
  fi
  if [ "$(git -C "$wt" rev-parse 'HEAD^{tree}')" != "$(git rev-parse "$ws^{tree}")" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: merged main"
  fi
}

propose() { # <name> <folder>: PR the worktree's ws/<name> into main if it adds anything
  local ws
  ws=$(git -C "$wt" rev-parse HEAD)
  git -C "$wt" checkout --quiet -B "propose/$1" "$main"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" \
    -m "delphi: bring ws/$1 into main" "$ws" >/dev/null; then
    conflict "ws/$1: CONFLICT merging into main."
    return
  fi
  if [ "$(git -C "$wt" rev-parse 'HEAD^{tree}')" = "$(git rev-parse "$main^{tree}")" ]; then
    return
  fi
  if ! "$root/ci/check.sh" "$wt"; then failed=1 && return; fi
  git -C "$wt" push --quiet --force origin "propose/$1"
  local title="ws/$1 → main" body pr
  body="Brings \`ws/$1\` into \`$2/\` (opened by ci/sync.sh; see README).

Changed files:
$(git -C "$wt" diff --name-only "$main" HEAD | sed 's/^/- /')

Workspace commits:
$(git log --no-merges --invert-grep --grep='^delphi: ' --format='- %s (%an)' "$main..$ws")"
  pr=$(gh pr list --base main --head "propose/$1" --state open --json number --jq '.[0].number // empty')
  if [ -n "$pr" ]; then
    gh pr edit "$pr" --title "$title" --body "$body" >/dev/null
  else
    gh pr create --base main --head "propose/$1" --title "$title" --body "$body" >/dev/null
  fi
  echo "ws/$1: PR to main from propose/$1"
}

for folder in $(git ls-tree -r --name-only "$main" -- software |
  sed -nE 's#^(software/(.+/)?workspaces/[^/]+)/workspace\.yml$#\1#p'); do
  name=${folder##*/}
  names="$names$name "
  if [ -z "$only" ] || [ "$only" = "$name" ]; then
    ok=1
    if [ "$dir" = propose ]; then
      # propose only: take ws/<name> as it is (skip workspaces without a branch yet)
      if git rev-parse --quiet --verify "refs/remotes/origin/ws/$name" >/dev/null; then
        git -C "$wt" checkout --quiet --detach "origin/ws/$name"
      else ok=0; fi
    else
      refresh "$name" "$folder"
    fi
    if [ "$ok" = 1 ] && [ "$dir" != refresh ]; then propose "$name" "$folder"; fi
  fi
done

[ -z "$only" ] || case "$names" in *" $only "*) ;; *) echo "no workspace '$only' on main" >&2 && exit 1 ;; esac
for b in $(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ws/); do
  case "$names" in *" ${b#ws/} "*) ;; *) echo "notice: $b has no workspace folder on main (kept)" ;; esac
done
exit "$failed"
