#!/usr/bin/env bash
# .delphi/setup.sh: run in a checkout of ws/<name> (the workspace root). For each repo listed under
# `repos:` in workspace.yml, fetches it into a bare store at repos/<name> (unless present) and checks
# out its default branch as the first worktree, worktrees/<name>/<default-branch>. For each repo under
# `references-git:` (read-only dependency sources, `<name>: <git-url> [<ref>]`), checks out a shallow,
# detached copy of <ref> (default: origin's default branch) at references/<name>, refreshed on every
# run, with pushes disabled. Each entry under `links:` (`- <workspace>` or `- main`) gets the same
# kind of copy of this clone's origin (Delphi) at ws/<workspace> (or main), at linked/<name>; to edit
# one, switch this clone to it (.delphi/switch.sh). Adds /repos/, /worktrees/, /references/ and
# /linked/ to this clone's .git/info/exclude, and installs .delphi/park.sh as its post-checkout hook
# (unless another hook is there) so switching to another workspace or main parks them. Safe to
# re-run. Keep it bash 3.2 (macOS) and Git Bash safe: no bash-4 features, POSIX awk only.
set -euo pipefail
cd "$(dirname "$0")/.."

list=$(awk '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  /^repos:/ { s = "repo"; next }
  /^references-git:/ { s = "ref"; next }
  /^links:/ { s = "link"; next }
  /^[^[:space:]]/ { s = "" }
  s == "link" { sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, ""); print s, $0; next }
  s { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+#.*$/, ""); n = index($0, ":")
      if (n) print s, substr($0, 1, n - 1), substr($0, n + 1) }' workspace.yml)

readonly_copy() { # <dir> <url> [<ref>]: shallow, detached, push-disabled checkout at <dir>
  local dir=$1
  [ -d "$dir/.git" ] || { git init -q "$dir" && git -C "$dir" remote add origin "$2"; }
  git -C "$dir" remote set-url origin "$2"
  git -C "$dir" remote set-url --push origin DISABLED-read-only-copy
  if git -C "$dir" fetch -q --depth 1 origin "${3:-HEAD}" </dev/null &&
    git -C "$dir" checkout -q --detach FETCH_HEAD; then
    echo "$dir: at ${3:-default branch} ($(git -C "$dir" rev-parse --short HEAD))"
  else
    echo "setup: could not update $dir to ${3:-the default branch}" >&2
  fi
}

self=$(awk '/^name:/ { print $2; exit }' workspace.yml)
link() { # <workspace>|main: a read-only copy of Delphi's ws/<workspace> (or main) at linked/<name>
  case "$1" in -* | *[!a-z0-9-]*) echo "setup: skipping bad link '$1'" >&2 && return ;; "$self") return ;; esac
  [ ! -f "linked/$1/.git" ] ||
    { echo "setup: linked/$1 is an old link.sh worktree; run git worktree remove linked/$1, then re-run" >&2 && return; }
  local ref=ws/$1
  [ "$1" != main ] || ref=main
  readonly_copy "linked/$1" "$(git remote get-url origin)" "$ref"
}

while read -r kind name url ref; do
  [ -n "$name" ] || continue
  case "$name" in . | .. | *[!A-Za-z0-9._-]*) echo "setup: skipping unsafe repo name '$name'" >&2 && continue ;; esac
  if [ "$kind" = link ]; then link "$name"; continue; fi
  if [ "$kind" = ref ]; then readonly_copy "references/$name" "$url" ${ref:+"$ref"} && continue; fi
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
for d in /repos/ /worktrees/ /references/ /linked/; do
  grep -qxF "$d" "$exclude" 2>/dev/null || echo "$d" >>"$exclude"
done
hook=$(git rev-parse --git-path hooks/post-checkout)
if [ ! -e "$hook" ] || grep -qF '.delphi/park.sh' "$hook"; then
  mkdir -p "$(dirname "$hook")" && cp .delphi/park.sh "$hook" && chmod +x "$hook"
else
  echo "setup: $hook is another hook; not installing .delphi/park.sh, so checkouts won't park repos/" >&2
fi
