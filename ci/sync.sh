#!/usr/bin/env bash
# ci/sync.sh [refresh|propose] [<name>]: sync each workspace folder software/**/workspaces/<name>/ on
# origin/main (or just <name>) with its branch ws/<name>, whose root is the folder. CI runs it with
# no direction (both) on every push to main or ws/**.
#   refresh: merge main into ws/<name> (-Xsubtree=<folder>) and push if the tree changed. A missing
#            ws/<name> is created as one commit: tree = the folder, parent = main.
#   propose: build propose/<name> = main + a subtree merge of ws/<name>; if that changes main and
#            isn't already on propose/<name>, check it, force-push it, and open or update its PR.
# A conflict is reported with its files and that workspace skipped; exits 1 if any failed. ws/*
# branches without a folder get a notice, never deleted. Merges run in a temporary worktree.
set -euo pipefail
dir=both
case "${1:-}" in refresh | propose) dir=$1 && shift ;; esac
only=${1:-}
case "$only" in *[!a-z0-9-]*) echo "usage: ci/sync.sh [refresh|propose] [<name>]" >&2 && exit 2 ;; esac

git fetch --quiet --prune origin
main=$(git rev-parse origin/main)
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" "$main"
trap 'git worktree remove --force "$wt"' EXIT
failed=0 names=" "
tree() { git -C "$wt" rev-parse --quiet --verify "$1^{tree}" || true; } # empty if <rev> is missing

conflict() { # <message>: report the conflicted files, abort the merge, skip this workspace
  echo "$1 Files:" >&2
  git -C "$wt" diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  git -C "$wt" merge --abort 2>/dev/null || true # nothing to abort if the merge never started
  failed=1 ok=0
}

refresh() { # <name> <folder>: leave the worktree at ws/<name> with main merged in
  local ws=refs/remotes/origin/ws/$1
  if [ -z "$(tree "$ws")" ]; then
    git -C "$wt" checkout --quiet --detach \
      "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$main:$2")"
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: created from $2"
    return
  fi
  git -C "$wt" checkout --quiet --detach "$ws"
  # --no-ff: once ws commits are in main, a fast-forward would put main's whole tree on ws/<name>.
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: refresh ws/$1 from main" "$main" >/dev/null; then
    conflict "ws/$1: CONFLICT refreshing from main; merge main into ws/$1 in a PR (see README)."
  elif [ "$(tree HEAD)" != "$(tree "$ws")" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: refreshed"
  fi
}

propose() { # <name> <folder>: PR the worktree's ws/<name> into main if it changes anything
  local ws title="ws/$1 → main" body pr
  ws=$(git -C "$wt" rev-parse HEAD)
  git -C "$wt" checkout --quiet --detach "$main"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: propose ws/$1 to main" "$ws" >/dev/null; then
    conflict "ws/$1: CONFLICT proposing to main; merge main into ws/$1 in a PR (see README)."
    return
  fi
  case "$(tree HEAD)" in "$(tree "$main")" | "$(tree "refs/remotes/origin/propose/$1")") return ;; esac
  "$wt/ci/check.sh" "$wt" || { echo "ws/$1: check failed; not proposed" >&2 && failed=1 && return; }
  git -C "$wt" push --quiet --force origin "HEAD:refs/heads/propose/$1"
  body="Proposes \`ws/$1\` into \`$2/\` (opened by ci/sync.sh; see README).

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
  echo "ws/$1: proposed (PR from propose/$1)"
}

for folder in $(git ls-tree -r --name-only "$main" -- software |
  sed -nE 's#^(software/(.+/)?workspaces/[^/]+)/workspace\.yml$#\1#p'); do
  name=${folder##*/} ok=1
  names="$names$name "
  [ -z "$only" ] || [ "$only" = "$name" ] || continue
  if [ "$dir" != propose ]; then
    refresh "$name" "$folder"
  elif [ -n "$(tree "refs/remotes/origin/ws/$name")" ]; then
    git -C "$wt" checkout --quiet --detach "refs/remotes/origin/ws/$name" # propose ws/<name> as is
  else ok=0; fi
  if [ "$ok" = 1 ] && [ "$dir" != refresh ]; then propose "$name" "$folder"; fi
done

[ -z "$only" ] || case "$names" in *" $only "*) ;; *) echo "no workspace '$only' on main" >&2 && exit 1 ;; esac
for b in $(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ws/); do
  case "$names" in *" ${b#ws/} "*) ;; *) echo "notice: $b has no workspace folder on main (kept)" ;; esac
done
exit "$failed"
