#!/usr/bin/env bash
# .delphi/setup.sh: run in a checkout of ws/<name> (the workspace root). For each repo listed under
# `repos:` in workspace.yml, fetches it into a bare store at repos/<name> (unless present) and checks
# out its default branch as the first worktree, worktrees/<name>/<default-branch>. For each repo under
# `references-git:` (read-only dependency sources, `<name>: <git-url> [<ref>]`), checks out a shallow,
# detached copy of <ref> (default: origin's default branch) at references/<name>, refreshed on every
# run, with pushes disabled. Adds /repos/, /worktrees/ and /references/ to this clone's
# .git/info/exclude. Safe to re-run. Keep it bash 3.2 (macOS) and Git Bash safe: no bash-4
# features, POSIX awk only.
set -euo pipefail
cd "$(dirname "$0")/.."

list=$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /^repos:/ { s = "repo"; next }
  /^references-git:/ { s = "ref"; next }
  /^[^[:space:]]/ { s = "" }
  s { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); n = index($0, ":")
      if (n) print s, substr($0, 1, n - 1), substr($0, n + 1) }' workspace.yml)

reference() { # <name> <url> [<ref>]: shallow, detached, push-disabled checkout at references/<name>
  local dir=references/$1
  [ -d "$dir/.git" ] || { git init -q "$dir" && git -C "$dir" remote add origin "$2"; }
  git -C "$dir" remote set-url origin "$2"
  git -C "$dir" remote set-url --push origin DISABLED-references-are-read-only
  if git -C "$dir" fetch -q --depth 1 origin "${3:-HEAD}" </dev/null &&
    git -C "$dir" checkout -q --detach FETCH_HEAD; then
    echo "references/$1: at ${3:-default branch} ($(git -C "$dir" rev-parse --short HEAD))"
  else
    echo "setup: could not update references/$1 to ${3:-the default branch}" >&2
  fi
}

while read -r kind name url ref; do
  [ -n "$name" ] || continue
  case "$name" in . | .. | *[!A-Za-z0-9._-]*) echo "setup: skipping unsafe repo name '$name'" >&2 && continue ;; esac
  if [ "$kind" = ref ]; then reference "$name" "$url" ${ref:+"$ref"} && continue; fi
  store=repos/$name
  if [ -e "$store" ]; then
    echo "repos/$name: already present"
  else
    git init -q --bare "$store"
    git -C "$store" remote add origin "$url"
    git -C "$store" fetch -q origin </dev/null
    git -C "$store" remote set-head origin -a >/dev/null </dev/null
  fi
  def=$(git -C "$store" symbolic-ref -q --short refs/remotes/origin/HEAD) ||
    { echo "setup: repos/$name has no origin/HEAD; skipping its worktree" >&2 && continue; }
  def=${def#origin/}
  dest=worktrees/$name/$def
  if [ -e "$dest" ]; then continue
  elif git -C "$store" rev-parse -q --verify "refs/heads/$def" >/dev/null; then
    git -C "$store" worktree add -q "$PWD/$dest" "$def" ||
      echo "setup: could not check out $dest (is $def checked out in repos/$name?)" >&2
  else
    git -C "$store" worktree add -q --track -b "$def" "$PWD/$dest" "origin/$def"
  fi
done <<EOF2
$list
EOF2

exclude=$(git rev-parse --git-path info/exclude)
mkdir -p "$(dirname "$exclude")"
for d in /repos/ /worktrees/ /references/; do
  grep -qxF "$d" "$exclude" 2>/dev/null || echo "$d" >>"$exclude"
done
