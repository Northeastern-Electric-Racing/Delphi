#!/usr/bin/env bash
# ci/sync.sh [refresh|propose] [<name>]: subtree-sync native workspace folders on main with ws/<name>.
# Refresh copies reviewed generated files and main's runtime; it never reads source formats or runs
# harness adapters. Propose prepares a main checkout, renders its managed output, validates and opens a PR.
# Temporary worktrees keep the caller untouched. Conflicts in workspace-owned files are reported.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/managed.sh
source "$here/managed.sh"
dir=both
case "${1:-}" in refresh | propose) dir=$1 && shift ;; esac
only=${1:-}
only=${only#ws/}
case "$only" in *[!a-z0-9.-]*) echo "usage: ci/sync.sh [refresh|propose] [<name>]" >&2 && exit 2 ;; esac

git fetch --quiet --prune origin
main=$(git rev-parse origin/main)
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" "$main"
trap 'git worktree remove --force "$wt"; rm -f "$wt.index"' EXIT
failed=0 names=" "
tree() { git -C "$wt" rev-parse --quiet --verify "$1^{tree}" || true; } # empty if <rev> is missing
file_entry() { git ls-tree "$1" -- "$2" | awk '$1 == "100644" || $1 == "100755" { print $1 " " $3 }'; }

with_delphi() { # <commit> [<folder>/]: its tree with <folder>/.delphi/ dropped, or (no folder) its
  # .delphi/ replaced by main's. Built in a temporary index, so the worktree is untouched.
  local i=$wt.index
  rm -f "$i"
  GIT_INDEX_FILE=$i git read-tree "$1"
  GIT_INDEX_FILE=$i git rm -rqf --cached --ignore-unmatch -- "${2:-}.delphi" >/dev/null
  [ -n "${2:-}" ] || ! git rev-parse -q --verify "$main:.delphi" >/dev/null ||
    GIT_INDEX_FILE=$i git read-tree --prefix=.delphi/ "$main:.delphi"
  GIT_INDEX_FILE=$i git write-tree
  rm -f "$i"
}

previous_records() { # <workspace commit> <folder>: ownership from the main revision it last merged
  local base
  base=$(git merge-base "$1" "$main" || true)
  if [ -n "$base" ]; then
    if git cat-file -e "$base:$2/$generated" 2>/dev/null; then ledger "$base:$2/$generated"
    else ledger "$base:$generated"; fi
  fi
}

managed_records() { # <workspace commit> <folder>: trusted previous ownership, restricted by branch ownership
  local old trusted
  old=$(ledger "$1:$generated") || return 1
  trusted=$(previous_records "$1" "$2") || return 1
  # Dropping an entry after an opt-out records the ownership transfer, even before its proposal merges.
  printf '%s\n' "$old" | awk -F'\t' -v trusted="$trusted" 'BEGIN {
    n = split(trusted, rows, "\n"); for (i = 1; i <= n; i++) { split(rows[i], f, "\t"); owned[f[2]] = 1 }
  } $2 in owned'
}

with_generated() { # <workspace commit> <folder>: copy reviewed native output; no source resolution
  local i=$wt.index now old out meta path src entry blob
  now=$(ledger "$main:$2/$generated") || return 1
  old=$(managed_records "$1" "$2") || return 1
  out=$(git show "$1:workspace.yml" | optouts)
  rm -f "$i"
  GIT_INDEX_FILE=$i git read-tree "$1"
  printf '%s\n%s\n' "$old" "$now" | cut -f2 | LC_ALL=C sort -u |
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      opted_out "$path" "$out" && continue
      GIT_INDEX_FILE=$i git update-index --force-remove -- "$path"
      entry=$(file_entry "$main" "$2/$path")
      [ -z "$entry" ] || GIT_INDEX_FILE=$i git update-index --add --cacheinfo "${entry%% *},${entry##* },$path"
    done
  blob=$({ ledger_header
    while IFS=$'\t' read -r meta path src; do
      [ -n "$path" ] || continue
      opted_out "$path" "$out" || printf '%s\t%s\t%s\n' "$meta" "$path" "$src"
    done <<<"$now"
  } | git hash-object -w --stdin)
  GIT_INDEX_FILE=$i git update-index --add --cacheinfo "100644,$blob,$generated"
  GIT_INDEX_FILE=$i git write-tree
  rm -f "$i"
}

resolve_generated_conflicts() { # <workspace commit> <folder> <prefix>: only explicit managed ownership resolves automatically
  local now old previous out paths path relative entry meta src
  now=$(ledger "$main:$2/$generated") || return 1
  old=$(managed_records "$1" "$2") || return 1
  previous=$(previous_records "$1" "$2") || return 1
  out=$(git show "$1:workspace.yml" | optouts)
  paths=" $(printf '%s\n%s\n' "$old" "$now" | cut -f2 | tr '\n' ' ') $generated "
  while IFS=$'\t' read -r meta path src; do
    [ -z "$path" ] || ! opted_out "$path" "$out" || paths="$paths$path "
  done <<<"$previous"
  while IFS= read -r path; do
    relative=${path#"$3"}
    [ "$path" = "$3$relative" ] || continue
    case "$paths" in *" $relative "*) ;; *) continue ;; esac
    git -C "$wt" update-index --force-remove -- "$path"
    if [ "$relative" = "$generated" ] || opted_out "$relative" "$out"; then
      entry=$(file_entry "$1" "$relative")
    else
      entry=$(file_entry "$main" "$2/$relative")
    fi
    [ -z "$entry" ] || git -C "$wt" update-index --add --cacheinfo "${entry%% *},${entry##* },$path"
  done < <(git -C "$wt" diff --name-only --diff-filter=U)
  [ -z "$(git -C "$wt" diff --name-only --diff-filter=U)" ] || return 1
  git -C "$wt" commit --quiet --no-edit
  git -C "$wt" reset --quiet --hard HEAD
}

conflict() { # <message>: report the conflicted files, abort the merge, skip this workspace
  echo "$1 Files:" >&2
  git -C "$wt" diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  git -C "$wt" merge --abort 2>/dev/null || true # nothing to abort if the merge never started
  failed=1 ok=0
}

refresh() { # <name> <folder> <old name>: leave the worktree at ws/<name> with main merged in
  local ws=refs/remotes/origin/ws/$1 from=refs/remotes/origin/ws/$1 was=refs/remotes/origin/ws/$3
  if [ -n "$(tree "$was")" ] && { [ -z "$(tree "$ws")" ] ||
    { [ "$(git rev-parse "$ws")" != "$(git rev-parse "$was")" ] && git merge-base --is-ancestor "$ws" "$was"; }; }; then
    from=$was # its old name is ahead: carry that over
  fi
  if [ -z "$(tree "$from")" ]; then
    git -C "$wt" checkout --quiet --detach \
      "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$(with_delphi "$main:$2")")"
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: created from $2"
    return
  fi
  local head t ws
  t=$(with_generated "$from" "$2") || { failed=1 ok=0; return; }
  ws=$from
  if [ "$t" != "$(tree "$from")" ]; then
    ws=$(git commit-tree -p "$from" -m "delphi: sync generated files from main" "$t")
  fi
  git -C "$wt" checkout --quiet --detach "$ws"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: refresh ws/$1 from main" "$main" >/dev/null; then
    if ! resolve_generated_conflicts "$ws" "$2" ""; then
      conflict "ws/$1: CONFLICT refreshing from main; merge main into ws/$1 in a PR (see README)."
      return
    fi
  fi
  head=$(git -C "$wt" rev-parse HEAD)
  t=$(with_delphi "$head")
  if [ "$t" != "$(tree "$head")" ]; then
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$head" -m "delphi: sync .delphi/ from main" "$t")"
  fi
  if [ "$from" != "refs/remotes/origin/ws/$1" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1" "HEAD:refs/heads/ws/$3"
    echo "ws/$1: from ws/$3, its old name (pushed to both)"
  elif [ "$(git -C "$wt" rev-parse HEAD)" != "$(git rev-parse "refs/remotes/origin/ws/$1")" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: refreshed"
  fi
}

propose() { # <name> <folder>: PR the worktree's ws/<name> into main if it changes anything
  local ws title="ws/$1 → main" body pr
  ws=$(git -C "$wt" rev-parse HEAD)
  local t
  t=$(with_generated "$ws" "$2") || { failed=1 ok=0; return; }
  [ "$t" = "$(tree "$ws")" ] || ws=$(git commit-tree -p "$ws" -m "delphi: prepare managed files for proposal" "$t")
  git -C "$wt" checkout --quiet --detach "$main"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: propose ws/$1 to main" "$ws" >/dev/null; then
    if ! resolve_generated_conflicts "$ws" "$2" "$2/"; then
      conflict "ws/$1: CONFLICT proposing to main; merge main into ws/$1 in a PR (see README)."
      return
    fi
  fi
  t=$(with_delphi "$(git -C "$wt" rev-parse HEAD)" "$2/")
  git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$main" -p "$ws" -m "delphi: propose ws/$1 to main" "$t")"
  if ! bash "$wt/ci/render.sh" "$wt"; then
    echo "ws/$1: main-side rendering failed; not proposed" >&2
    failed=1; return
  fi
  git -C "$wt" add -A
  t=$(git -C "$wt" write-tree)
  git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$main" -p "$ws" -m "delphi: propose ws/$1 to main" "$t")"
  case "$(tree HEAD)" in "$(tree "$main")" | "$(tree "refs/remotes/origin/propose/$1")") return ;; esac
  "$wt/ci/check.sh" "$wt" "$main" || { echo "ws/$1: check failed; not proposed" >&2; failed=1; return; }
  git -C "$wt" push --quiet --force origin "HEAD:refs/heads/propose/$1"
  body="## Changes

Proposes \`ws/$1\` into \`$2/\` (opened by ci/sync.sh, updated on each push to it; see README). Workspace commits:

$(git log --no-merges --invert-grep --grep='^delphi: ' --format='- %s (%an)' "$main..$ws")

## Testing

- ci/check.sh, run by sync before proposing

## Checklist

- [x] \`ci/check.sh .\` passes
- [x] No merge conflicts
- [ ] Request reviewers & ping on Slack"
  pr=$(gh pr list --base main --head "propose/$1" --state open --json number --jq '.[0].number // empty')
  if [ -n "$pr" ]; then # labels are left alone, so a written-by label someone changed stays
    gh pr edit "$pr" --title "$title" --body "$body" >/dev/null
  else
    gh pr create --base main --head "propose/$1" --title "$title" --body "$body" --label "by: ai" >/dev/null
  fi
  echo "ws/$1: proposed (PR from propose/$1)"
}

olds=" " # <old name>|<name> of each workspace
while read -r name folder; do
  ok=1
  names="$names$name " olds="$olds${folder%/workspaces/*}/${folder##*/}|$name "
  [ -z "$only" ] || [ "$only" = "$name" ] || continue
  if [ "$dir" != propose ]; then
    refresh "$name" "$folder" "${folder%/workspaces/*}/${folder##*/}"
  elif [ -n "$(tree "refs/remotes/origin/ws/$name")" ]; then
    git -C "$wt" checkout --quiet --detach "refs/remotes/origin/ws/$name" # propose ws/<name> as is
  else ok=0; fi
  if [ "$ok" = 1 ] && [ "$dir" != refresh ]; then propose "$name" "$folder"; fi
done < <(bash "$here/../.delphi/names.sh" "$main")

[ -z "$only" ] || case "$names" in *" $only "*) ;; *) echo "no workspace '$only' on main" >&2 && exit 1 ;; esac
for b in $(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ws/); do
  case "$names" in *" ${b#ws/} "*) continue ;; esac
  n=${olds#*" ${b#ws/}|"} n=${n%% *}
  case "$olds" in *" ${b#ws/}|"*)
    if git merge-base --is-ancestor "refs/remotes/origin/$b" "refs/remotes/origin/ws/$n" 2>/dev/null; then
      echo "notice: $b is ws/$n's old name (kept; delete it once no clone is on it)"
    else echo "notice: $b, ws/$n's old name, has commits ws/$n lacks: merge it into ws/$n in a PR (kept)"; fi ;;
  *) echo "notice: $b has no workspace folder on main (kept)" ;; esac
done
exit "$failed"
