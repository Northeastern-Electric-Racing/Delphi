#!/usr/bin/env bash
# ci/sync.sh [refresh|propose] [<name>]: subtree-sync native workspace folders on main with ws/<name>.
# Inherited native output is staged from main's sources and kept only on workspace branches.
# Subtree merges carry owned files; proposals exclude inherited copies and their ownership ledger.
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
cache=$(mktemp -d)
git worktree add --quiet --detach "$wt" "$main"
trap 'git worktree remove --force "$wt"; rm -f "$wt.index"; rm -rf "$cache"' EXIT
failed=0 names=" "
tree() { git -C "$wt" rev-parse --quiet --verify "$1^{tree}" || true; } # empty if <rev> is missing
file_entry() { git ls-tree "$1" -- "$2" | awk '$1 == "100644" || $1 == "100755" { print $1 " " $3 }'; }

with_delphi() { # <commit> [<folder>/]: its tree with <folder>/.delphi/ dropped, or (no folder) its
  # .delphi/ replaced by main's. Built in a temporary index, so the worktree is untouched.
  local i=$wt.index
  rm -f "$i" || return 1
  GIT_INDEX_FILE=$i git read-tree "$1" || return 1
  GIT_INDEX_FILE=$i git rm -rqf --cached --ignore-unmatch -- "${2:-}.delphi" >/dev/null || return 1
  [ -n "${2:-}" ] || ! git rev-parse -q --verify "$main:.delphi" >/dev/null ||
    GIT_INDEX_FILE=$i git read-tree --prefix=.delphi/ "$main:.delphi" || return 1
  GIT_INDEX_FILE=$i git write-tree || return 1
  rm -f "$i"
}

source_checkout() { # <main revision>: extract immutable sources once, outside the merge worktree
  local source=$cache/$1/source
  if [ ! -f "$cache/$1/source-ready" ]; then
    mkdir -p "$source" || return 1
    git archive "$1" | tar -x -C "$source" || return 1
    : >"$cache/$1/source-ready" || return 1
  fi
  printf '%s\n' "$source"
}

staged() { # <main revision> <folder>: trusted native output, including historical pre-staging main
  local source target=$cache/$1/native/$2 renderer records meta path src ready=$cache/status/main/$1/$2
  if [ ! -f "$ready" ]; then
    source=$(source_checkout "$1") || return 1
    mkdir -p "$target" || return 1
    if git cat-file -e "$1:$2/$generated" 2>/dev/null; then
      records=$(ledger "$1:$2/$generated") || return 1
      while IFS=$'\t' read -r meta path src; do
        [ -n "$path" ] || continue
        [ "$(file_entry "$1" "$2/$path")" = "$meta" ] || { echo "sync: invalid historical managed output $2/$path" >&2; return 1; }
        mkdir -p "$(dirname "$target/$path")" || return 1
        git show "$1:$2/$path" >"$target/$path" || return 1
        [ "${meta%% *}" != 100755 ] || chmod +x "$target/$path" || return 1
      done <<<"$records"
      { ledger_header; printf '%s\n' "$records"; } >"$target/$generated" || return 1
    else
      renderer=$here/render.sh
      if [ -f "$source/ci/render.sh" ] && grep -q -- '--workspace' "$source/ci/render.sh"; then renderer=$source/ci/render.sh; fi
      if [ ! -f "$source/ci/render.sh" ] && ! grep -q '^harness:' "$source/$2/workspace.yml"; then
        printf '\nharness: claude-code\n' >>"$source/$2/workspace.yml" || return 1
      fi
      bash "$renderer" --workspace "$2" "$source" "$cache/$1/native" >&2 || return 1
    fi
    mkdir -p "$(dirname "$ready")" || return 1
    : >"$ready" || return 1
  fi
  printf '%s\n' "$target"
}

previous_main() { # <workspace commit>: newest source-shaped main ancestor, never a workspace merge-base
  local revision
  for revision in $(git rev-list --first-parent "$main"); do
    if git merge-base --is-ancestor "$revision" "$1"; then printf '%s\n' "$revision"; return; fi
  done
}

previous_records() { # <workspace commit> <folder>: reconstruct trusted ownership from previous main sources
  local base native recipe records settings
  recipe=$(git log --first-parent -1 --format=%H "$1" -- "$generated") || return 1
  recipe=${recipe:-$1}
  base=$(previous_main "$recipe") || return 1
  [ -n "$base" ] || return 0
  git cat-file -e "$base:$2/workspace.yml" 2>/dev/null || return 0
  native=$(staged "$base" "$2") || return 1
  if ! git cat-file -e "$recipe:$generated" 2>/dev/null || git cat-file -e "$base:$2/$generated" 2>/dev/null; then
    generated_records <"$native/$generated"
    return
  fi
  settings=$(generated_records <"$native/$generated" | awk -F'\t' '$3 == "ci/plugins.sh"') || return 1
  native=$(staged_recipe "$base" "$2" "$recipe") || return 1
  records=$(generated_records <"$native/$generated") || return 1
  printf '%s\n' "$records" | awk -F'\t' -v settings="$settings" '$3 == "ci/plugins.sh" && settings != "" { print settings; next } { print }'
}

staged_recipe() { # recover the last generated target from its manifest; hashes come only from trusted main sources
  local source original renderer target=$cache/recipe/$1/$3/native/$2 ready=$cache/status/recipe/$1/$3/$2
  if [ ! -f "$ready" ]; then
    original=$(source_checkout "$1") || return 1
    source=$cache/recipe/$1/$3/source
    mkdir -p "$source" || return 1
    cp -R "$original/." "$source/" || return 1
    rm -rf "${source:?}/$2" || return 1
    mkdir -p "$source/$2" || return 1
    git show "$3:workspace.yml" >"$source/$2/workspace.yml" || return 1
    renderer=$here/render.sh
    if [ -f "$source/ci/render.sh" ] && grep -q -- '--workspace' "$source/ci/render.sh"; then renderer=$source/ci/render.sh; fi
    bash "$renderer" --workspace "$2" "$source" "$cache/recipe/$1/$3/native" >&2 || return 1
    mkdir -p "$(dirname "$ready")" || return 1
    : >"$ready" || return 1
  fi
  printf '%s\n' "$target"
}

legacy_workspace() { # pre-ledger workspaces alone may adopt copies proven by source provenance
  local base
  git cat-file -e "$1:$generated" 2>/dev/null && return 1
  base=$(previous_main "$1") || return 1
  [ -n "$base" ] && ! git cat-file -e "$base:ci/render.sh" 2>/dev/null
}

managed_records() { # <workspace commit> <folder>: trusted previous ownership, restricted by branch ownership
  local old trusted meta path src
  old=$(ledger "$1:$generated") || return 1
  trusted=$(previous_records "$1" "$2") || return 1
  if legacy_workspace "$1"; then
    while IFS=$'\t' read -r meta path src; do
      [ -n "$path" ] || continue
      [ "$(file_entry "$1" "$path")" != "$meta" ] || printf '%s\t%s\t%s\n' "$meta" "$path" "$src"
    done <<<"$trusted"
    return
  fi
  # Dropping an entry after an opt-out records the ownership transfer, even before its proposal merges.
  printf '%s\n' "$old" | awk -F'\t' -v trusted="$trusted" 'BEGIN {
    n = split(trusted, rows, "\n"); for (i = 1; i <= n; i++) { split(rows[i], f, "\t"); owned[f[2]] = rows[i] }
  } $2 in owned { print owned[$2] }'
}

with_generated() { # <workspace commit> <folder> [<ownership commit> [<native stage>]]: check ownership, then materialize
  local i=$wt.index now old out meta path src entry blob base legacy=0 branch_entry child parent paths native owner=${3:-$1} trusted main_native
  native=${4:-$(staged_recipe "$main" "$2" "$1")} || return 1
  now=$(generated_records <"$native/$generated") || return 1
  old=$(managed_records "$owner" "$2") || return 1
  trusted=$(previous_records "$owner" "$2") || return 1
  out=$(git show "$1:workspace.yml" | optouts) || return 1
  base=$(previous_main "$owner") || return 1
  if legacy_workspace "$owner"; then legacy=1; fi
  main_native=$(staged "$main" "$2") || return 1
  # Unmerged plugin choices wait for their proposal to merge, as do main's other native settings.
  entry=$(generated_records <"$main_native/$generated" | awk -F'\t' '$3 == "ci/plugins.sh"') || return 1
  if [ -n "$entry" ]; then
    now=$(printf '%s\n' "$now" | awk -F'\t' -v settings="$entry" '$3 == "ci/plugins.sh" { print settings; next } { print }') || return 1
  fi
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    while IFS=$'\t' read -r branch_entry child; do
      [ -n "$child" ] || continue
      if recorded "$child" "$old" && ! opted_out "$child" "$out"; then continue; fi
      [ "$src" != ci/plugins.sh ] || [ "$child" != "$path" ] || continue
      branch_entry="${branch_entry%% *} ${branch_entry##* }"
      # Pre-ledger clones can adopt copies proven by reviewed output or previous main provenance.
      if [ "$legacy" = 1 ] && [ "$child" = "$path" ] && { [ "$branch_entry" = "$meta" ] ||
        [ "$branch_entry" = "$(printf '%s\n' "$trusted" | awk -F'\t' -v p="$path" '$2 == p { print $1; exit }')" ] ||
        [ "$branch_entry" = "$(file_entry "$base" "$src")" ] ||
        [ "$branch_entry" = "$(file_entry "$base" "$2/$path")" ]; }; then continue; fi
      echo "sync: $2: CONFLICT: workspace-owned $child collides with managed output $path; opt out or resolve it in a workspace PR" >&2
      return 1
    done < <(git ls-tree -r "$1" -- "$path")
    parent=$(dirname "$path")
    while [ "$parent" != . ]; do
      branch_entry=$(git ls-tree "$1" -- "$parent" | awk '$1 != "040000" { print $1 " " $3 }')
      if [ -n "$branch_entry" ] && { ! recorded "$parent" "$old" || opted_out "$parent" "$out"; }; then
        echo "sync: $2: CONFLICT: workspace-owned $parent collides with managed output $path; opt out or resolve it in a workspace PR" >&2
        return 1
      fi
      parent=$(dirname "$parent")
    done
  done <<<"$now"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    recorded "$path" "$now" && continue
    branch_entry=$(git ls-tree "$1" -- "$path" | awk '$1 != "040000" { print $1 " " $3 }')
    if [ -n "$branch_entry" ] && [ "$branch_entry" != "$meta" ]; then
      echo "sync: $2: CONFLICT: retired managed $path has local edits; preserve it at another path or resolve it explicitly in a workspace PR" >&2
      return 1
    fi
  done <<<"$old"
  rm -f "$i" || return 1
  GIT_INDEX_FILE=$i git read-tree "$1" || return 1
  paths=$(printf '%s\n%s\n' "$old" "$now" | cut -f2 | LC_ALL=C sort -u) || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    GIT_INDEX_FILE=$i git update-index --force-remove -- "$path" || return 1
  done <<<"$paths"
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    opted_out "$path" "$out" && continue
    entry=$native/$path
    if [ "$src" = ci/plugins.sh ] && [ -f "$main_native/$path" ]; then entry=$main_native/$path; fi
    blob=$(git hash-object -w -- "$entry") || return 1
    [ "$blob" = "${meta#* }" ] || { echo "sync: staged hash mismatch for $path" >&2; return 1; }
    GIT_INDEX_FILE=$i git update-index --add --cacheinfo "${meta%% *},$blob,$path" || return 1
  done <<<"$now"
  blob=$({ ledger_header
    while IFS=$'\t' read -r meta path src; do
      [ -n "$path" ] || continue
      opted_out "$path" "$out" || printf '%s\t%s\t%s\n' "$meta" "$path" "$src"
    done <<<"$now"
  } | git hash-object -w --stdin) || return 1
  GIT_INDEX_FILE=$i git update-index --add --cacheinfo "100644,$blob,$generated" || return 1
  GIT_INDEX_FILE=$i git write-tree || return 1
  rm -f "$i"
}

without_generated() { # <normalized workspace commit>: leave owned payloads and native settings for subtree merging
  local i=$wt.index records meta path src
  records=$(ledger "$1:$generated") || return 1
  rm -f "$i" || return 1
  GIT_INDEX_FILE=$i git read-tree "$1" || return 1
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    [ "$src" != ci/plugins.sh ] || continue
    GIT_INDEX_FILE=$i git update-index --force-remove -- "$path" || return 1
  done <<<"$records"
  GIT_INDEX_FILE=$i git update-index --force-remove -- "$generated" || return 1
  GIT_INDEX_FILE=$i git write-tree || return 1
  rm -f "$i"
}

staged_workspace() { # <stripped workspace commit> <folder>: render current sources with the merged owned workspace
  local source original target=$cache/workspace/$1/native/$2 ready=$cache/status/workspace/$1/$2
  if [ ! -f "$ready" ]; then
    original=$(source_checkout "$main") || return 1
    source=$cache/workspace/$1/source
    mkdir -p "$source" || return 1
    cp -R "$original/." "$source/" || return 1
    rm -rf "${source:?}/$2" || return 1
    mkdir -p "$source/$2" || return 1
    git archive "$1" | tar -x -C "$source/$2" || return 1
    rm -rf "$source/$2/.delphi" || return 1
    bash "$here/render.sh" --workspace "$2" "$source" "$cache/workspace/$1/native" >&2 || return 1
    mkdir -p "$(dirname "$ready")" || return 1
    : >"$ready" || return 1
  fi
  printf '%s\n' "$target"
}

resolve_generated_conflicts() { # <stripped workspace commit> <folder> <prefix> <ownership commit>
  local now old previous out paths path relative entry meta src
  now=$(staged "$main" "$2") || return 1
  now=$(generated_records <"$now/$generated") || return 1
  old=$(managed_records "$4" "$2") || return 1
  previous=$(previous_records "$4" "$2") || return 1
  out=$(git show "$1:workspace.yml" | optouts)
  paths=" $(printf '%s\n%s\n' "$old" "$now" | cut -f2 | tr '\n' ' ') $generated "
  while IFS=$'\t' read -r meta path src; do
    [ -z "$path" ] || ! opted_out "$path" "$out" || paths="$paths$path "
  done <<<"$previous"
  while IFS= read -r path; do
    relative=${path#"$3"}
    [ "$path" = "$3$relative" ] || continue
    case "$paths" in *" $relative "*) ;; *) continue ;; esac
    git -C "$wt" update-index --force-remove -- "$path" || return 1
    entry=""
    if [ "$relative" = "$generated" ]; then :
    elif opted_out "$relative" "$out"; then
      entry=$(file_entry "$1" "$relative")
    else
      entry=$(file_entry "$main" "$2/$relative")
    fi
    [ -z "$entry" ] || git -C "$wt" update-index --add --cacheinfo "${entry%% *},${entry##* },$path" || return 1
  done < <(git -C "$wt" diff --name-only --diff-filter=U)
  [ -z "$(git -C "$wt" diff --name-only --diff-filter=U)" ] || return 1
  git -C "$wt" commit --quiet --no-edit || return 1
  git -C "$wt" reset --quiet --hard HEAD || return 1
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
    local initial native
    initial=$(with_delphi "$main:$2") || { failed=1 ok=0; return; }
    initial=$(git commit-tree -p "$main" -m "delphi: prepare ws/$1" "$initial") || { failed=1 ok=0; return; }
    initial=$(with_generated "$initial" "$2") || { failed=1 ok=0; return; }
    git -C "$wt" checkout --quiet --detach \
      "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$initial")" || { failed=1 ok=0; return; }
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1" || { failed=1 ok=0; return; }
    echo "ws/$1: created from $2"
    return
  fi
  local head t ws native
  t=$(with_generated "$from" "$2") || { failed=1 ok=0; return; }
  ws=$from
  if [ "$t" != "$(tree "$from")" ]; then
    ws=$(git commit-tree -p "$from" -m "delphi: sync generated files from main" "$t")
  fi
  t=$(without_generated "$ws") || { failed=1 ok=0; return; }
  [ "$t" = "$(tree "$ws")" ] || ws=$(git commit-tree -p "$ws" -m "delphi: prepare owned files for refresh" "$t")
  git -C "$wt" checkout --quiet --detach "$ws"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: refresh ws/$1 from main" "$main" >/dev/null; then
    if ! resolve_generated_conflicts "$ws" "$2" "" "$from"; then
      conflict "ws/$1: CONFLICT refreshing from main; merge main into ws/$1 in a PR (see README)."
      return
    fi
  fi
  head=$(git -C "$wt" rev-parse HEAD)
  native=$(staged_workspace "$head" "$2") || { failed=1 ok=0; return; }
  t=$(with_generated "$head" "$2" "$from" "$native") || { failed=1 ok=0; return; }
  if [ "$t" != "$(tree "$head")" ]; then
    head=$(git commit-tree -p "$head" -m "delphi: sync generated files from main" "$t")
    git -C "$wt" checkout --quiet --detach "$head"
  fi
  t=$(with_delphi "$head")
  if [ "$t" != "$(tree "$head")" ]; then
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$head" -m "delphi: sync .delphi/ from main" "$t")"
  fi
  if [ "$(tree HEAD)" = "$(tree "$from")" ] && git merge-base --is-ancestor "$main" "$from"; then
    git -C "$wt" checkout --quiet --detach "$from"
  fi
  if [ "$from" != "refs/remotes/origin/ws/$1" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1" "HEAD:refs/heads/ws/$3"
    echo "ws/$1: from ws/$3, its old name (pushed to both)"
  elif [ "$(git -C "$wt" rev-parse HEAD)" != "$(git rev-parse "refs/remotes/origin/ws/$1")" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: refreshed"
  fi
}

propose() { # <name> <folder>: PR owned workspace files into main, leaving inherited output on ws/*
  local ws owner title="ws/$1 → main" body pr
  ws=$(git -C "$wt" rev-parse HEAD)
  owner=$ws
  local t
  t=$(with_generated "$ws" "$2") || { failed=1 ok=0; return; }
  [ "$t" = "$(tree "$ws")" ] || ws=$(git commit-tree -p "$ws" -m "delphi: prepare managed files for proposal" "$t")
  t=$(without_generated "$ws") || { failed=1 ok=0; return; }
  [ "$t" = "$(tree "$ws")" ] || ws=$(git commit-tree -p "$ws" -m "delphi: propose owned files only" "$t")
  git -C "$wt" checkout --quiet --detach "$main"
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: propose ws/$1 to main" "$ws" >/dev/null; then
    if ! resolve_generated_conflicts "$ws" "$2" "$2/" "$owner"; then
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
