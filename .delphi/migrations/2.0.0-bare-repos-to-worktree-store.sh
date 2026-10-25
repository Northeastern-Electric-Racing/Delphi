#!/usr/bin/env bash
# 2.0.0: a bare repos/<name> (the store before 1.1.0) becomes the worktree store, worktrees/<name>/.bare,
# and repos/<name> is vacated for setup.sh to clone normally. Moves it (git worktree repair, so its
# worktrees follow) and sets origin/HEAD. Skips, reporting why, one with no origin, one whose branches or
# worktree HEADs aren't on origin, or whose .bare exists, or that can't be fetched to check.
set -euo pipefail
for d in repos/*; do
  [ -d "$d" ] || continue
  [ "$(git -C "$d" rev-parse --is-bare-repository 2>/dev/null)" = true ] || continue
  name=${d#repos/}
  to=worktrees/$name/.bare
  skip() { echo "migrate: $d $1; left it (move it to $to by hand)" >&2; }
  git -C "$d" remote get-url origin >/dev/null 2>&1 || { skip "has no origin remote"; continue; }
  [ ! -e "$to" ] || { skip "and $to both exist"; continue; }
  git -C "$d" fetch -q origin '+refs/heads/*:refs/remotes/origin/*' </dev/null 2>/dev/null || { skip "could not be fetched from origin"; continue; }
  heads=$({ git -C "$d" for-each-ref --format='%(objectname)' refs/heads
    git -C "$d" worktree list --porcelain | awk '/^HEAD / { print $2 }'; } | grep -v '^0*$' | sort -u)
  # shellcheck disable=SC2086 # object names
  if [ -n "$heads" ] && [ -n "$(git -C "$d" rev-list $heads --not --remotes=origin | head -n 1)" ]; then
    skip "has branches or worktree commits not on origin"; continue
  fi
  mkdir -p "worktrees/$name"
  mv "$d" "$to"
  git -C "$to" worktree repair "$PWD"/worktrees/"$name"/* 2>/dev/null || true
  git -C "$to" remote set-head origin -a >/dev/null </dev/null || true
  echo "migrate: moved $d to $to"
done
