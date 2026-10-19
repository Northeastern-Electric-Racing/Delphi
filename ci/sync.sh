#!/usr/bin/env bash
# ci/sync.sh [refresh|propose] [<name>]: sync each workspace folder software/**/workspaces/<leaf>/ on
# origin/main (or just <name>) with its branch ws/<name>, whose root is the folder. A workspace's
# <name> is .delphi/names.sh's: its folders' short names and <leaf>, joined by dots
# (software/application-software/argos/workspaces/argos-dev -> s.app.argos.argos-dev). CI runs it
# with no direction (both) on every push to main or ws/**.
#   refresh: merge main into ws/<name> (-Xsubtree=<folder>), then make its .delphi/ main's root
#            .delphi/ (a "delphi: sync" commit if that changed it), write over it the files it inherits
#            from main (every workspace-inherit/ folder from software/ down to its project folder,
#            less its workspace.yml's opt-out: paths) and remove those it inherited from the main it
#            last merged but no longer does (a "delphi: sync inherited" commit), list main's default plugin sets
#            above it under its workspace.yml's plugins: and regenerate its .claude/settings.json from
#            that (ci/plugins.sh; a "delphi: generate" commit if that changed either), and push if the
#            tree changed. While ws/<old> (the branch's name when workspaces were named by their
#            folder's path, software/application-software/argos/argos-dev) is ahead of ws/<name> or
#            ws/<name> is missing, it starts from ws/<old> (so its history and unproposed edits carry
#            over) and pushes the result to both, so clones still on ws/<old> get the version that
#            moves them. A missing ws/<name> with no ws/<old> is created as one commit: tree = the
#            folder plus main's .delphi/ and inherited files, parent = main.
#   propose: build propose/<name> = main + a subtree merge of ws/<name> without <folder>/.delphi/
#            or its inherited files (both managed on main); if that changes main and isn't already on propose/<name>, check it (against main),
#            force-push it, and open or update its PR.
# A conflict is reported with its files and that workspace skipped; exits 1 if any failed. ws/*
# branches without a folder, old names included, get a notice, never deleted. Merges run in a temporary worktree.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=ci/inherit.sh
source "$here/inherit.sh"
dir=both
case "${1:-}" in refresh | propose) dir=$1 && shift ;; esac
only=${1:-}
only=${only#ws/}
case "$only" in *[!a-z0-9.-]*) echo "usage: ci/sync.sh [refresh|propose] [<name>]" >&2 && exit 2 ;; esac

git fetch --quiet --prune origin
main=$(git rev-parse origin/main)
wt=$(mktemp -d)
mw=$(mktemp -d) # main, for ci/plugins.sh to read the plugin sets from
git worktree add --quiet --detach "$wt" "$main"
git worktree add --quiet --detach "$mw" "$main"
trap 'git worktree remove --force "$wt"; git worktree remove --force "$mw"; rm -f "$wt.yml" "$wt.settings" "$wt.err"' EXIT
failed=0 names=" "
tree() { git -C "$wt" rev-parse --quiet --verify "$1^{tree}" || true; } # empty if <rev> is missing

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

optouts() { # <rev:path of a workspace.yml>: its opt-out: entries, space-separated
  git show "$1" 2>/dev/null | awk '/^opt-out:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
    s && /^[[:space:]]+-[[:space:]]+/ { sub(/^[[:space:]]+-[[:space:]]+/, ""); sub(/[[:space:]]*#.*$/, ""); sub(/\/$/, ""); printf "%s ", $0 }'
}

inherited() { # <revision> <folder> <opt-outs> <harness>: mode blob<TAB>native destination
  inherited_files "$1" "$2" "$4" | awk -F'\t' -v out="$3" 'BEGIN { n = split(out, o, " ") }
    { for (i = 1; i <= n; i++) if ($2 == o[i] || index($2, o[i] "/") == 1) next
      print $1 "\t" $2 }'
}

with_inherited() { # <tree-ish> <folder> <old main or ''> <rev:path of its workspace.yml> [<prefix>/]: without
  # <prefix>, its tree with what the workspace inherits from main written over it, and what it
  # inherited from <old> but no longer does removed; with <prefix> (a proposal), those paths under
  # <prefix> put back to main's. Opt-outs come from that workspace.yml.
  local i=$wt.index out old_out="" now p ms adapter old_adapter old_manifest pre=${5:-}
  out=$(optouts "$4")
  adapter=$(git show "$4" | awk '/^harness:/ { print $2; exit }')
  old_adapter=$adapter
  if [ -n "$3" ]; then
    old_manifest=$3:$2/workspace.yml
    git cat-file -e "$old_manifest" 2>/dev/null || old_manifest=$3:workspace.yml
    old_adapter=$(git show "$old_manifest" | awk '/^harness:/ { print $2; exit }')
    old_out=$(optouts "$old_manifest")
  fi
  now=$(inherited "$main" "$2" "$out" "$adapter")
  rm -f "$i"
  GIT_INDEX_FILE=$i git read-tree "$1"
  { [ -z "$3" ] || inherited "$3" "$2" "$out $old_out" "$old_adapter"; [ -z "$pre" ] || printf '%s\n' "$now"; } | cut -f2 | sort -u |
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      [ -n "$pre" ] || ! printf '%s\n' "$now" | cut -f2 | grep -qxF "$p" || continue # still inherited: written below
      GIT_INDEX_FILE=$i git rm -qf --cached --ignore-unmatch -- "$pre$p" >/dev/null
      [ -z "$pre" ] || { ms=$(git ls-tree "$main" -- "$pre$p" | cut -f1) && [ -z "$ms" ]; } ||
        GIT_INDEX_FILE=$i git update-index --add --cacheinfo "${ms%% *},${ms##* },$pre$p"
    done
  [ -n "$pre" ] || printf '%s\n' "$now" | while IFS=$'\t' read -r ms p; do
    [ -z "$p" ] || GIT_INDEX_FILE=$i git update-index --add --cacheinfo "${ms% *},${ms#* },$p"
  done
  GIT_INDEX_FILE=$i git write-tree
  rm -f "$i"
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
      "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$(with_inherited "$(with_delphi "$main:$2")" "$2" "" "$main:$2/workspace.yml")")"
    if ! generate_harness "$mw" "$2" "$wt" 2>"$wt.err"; then
      echo "ws/$1: $(cat "$wt.err"); not created" >&2
      git -C "$wt" reset --quiet --hard HEAD
      git -C "$wt" clean -qfd
      failed=1 ok=0
      return
    fi
    git -C "$wt" add -A
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$main" -m "delphi: create ws/$1 from $2" "$(git -C "$wt" write-tree)")"
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1"
    echo "ws/$1: created from $2"
    return
  fi
  git -C "$wt" checkout --quiet --detach "$from"
  local old head t
  old=$(git merge-base "$from" "$main" || true) # the main it last merged: what it inherited then
  # --no-ff: once ws commits are in main, a fast-forward would put main's whole tree on ws/<name>.
  if ! git -C "$wt" merge --quiet --no-ff -Xsubtree="$2" -m "delphi: refresh ws/$1 from main" "$main" >/dev/null; then
    conflict "ws/$1: CONFLICT refreshing from main; merge main into ws/$1 in a PR (see README)."
    return
  fi
  head=$(git -C "$wt" rev-parse HEAD) && t=$(with_delphi "$head")
  if [ "$t" != "$(tree "$head")" ]; then
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$head" -m "delphi: sync .delphi/ from main" "$t")"
  fi
  head=$(git -C "$wt" rev-parse HEAD) && t=$(with_inherited "$head" "$2" "$old" "$head:workspace.yml")
  if [ "$t" != "$(tree "$head")" ]; then
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$head" -m "delphi: sync inherited files from main" "$t")"
  fi
  if ! generate_harness "$mw" "$2" "$wt" 2>"$wt.err"; then
    echo "ws/$1: $(cat "$wt.err"); not refreshed" >&2
    git -C "$wt" reset --quiet --hard HEAD
    git -C "$wt" clean -qfd
    failed=1 ok=0
    return
  fi
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    git -C "$wt" add -A # only the adapter has written since the inherited tree was committed
    git -C "$wt" commit --quiet -m "delphi: generate plugins: defaults and .claude/settings.json"
  fi
  if [ "$from" = "$was" ]; then
    git -C "$wt" push --quiet origin "HEAD:refs/heads/ws/$1" "HEAD:refs/heads/ws/$3"
    echo "ws/$1: from ws/$3, its old name (pushed to both)"
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
  local t
  t=$(with_delphi "$(git -C "$wt" rev-parse HEAD)" "$2/") # .delphi/ and inherited files are managed on main, never proposed
  t=$(with_inherited "$t" "$2" "$(git merge-base "$ws" "$main" || true)" "$ws:workspace.yml" "$2/")
  [ "$t" = "$(tree HEAD)" ] ||
    git -C "$wt" checkout --quiet --detach "$(git commit-tree -p "$main" -p "$ws" -m "delphi: propose ws/$1 to main" "$t")"
  case "$(tree HEAD)" in "$(tree "$main")" | "$(tree "refs/remotes/origin/propose/$1")") return ;; esac
  "$wt/ci/check.sh" "$wt" "$main" || { echo "ws/$1: check failed; not proposed" >&2 && failed=1 && return; }
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
