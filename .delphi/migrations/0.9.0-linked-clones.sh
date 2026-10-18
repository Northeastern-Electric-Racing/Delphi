#!/usr/bin/env bash
# 0.9.0: linked/<name> used to be a shallow, detached, push-disabled copy of ws/<name> (or main);
# setup.sh now keeps a full clone there, on that branch and tracking origin, with pushes allowed. Turns
# each old copy here (its push URL is DISABLED-read-only-copy) into one in place: fetches its full
# history, puts it on a local ws/<name> (or main) at the commit it's on, so nothing in it moves, and
# allows pushes. setup.sh then pulls it. Parked copies are their own workspace's, migrated when it's
# set up. Stops at one it can't fetch or that already has a local branch of that name.
set -euo pipefail
for d in linked/*/; do
  d=${d%/}
  [ -d "$d/.git" ] || continue
  [ "$(git -C "$d" config remote.origin.pushurl || true)" = DISABLED-read-only-copy ] || continue # a clone already
  n=${d#linked/} ref=ws/${d#linked/} unshallow=
  [ "$n" != main ] || ref=main
  [ "$(git -C "$d" rev-parse --is-shallow-repository)" = false ] || unshallow=--unshallow
  git -C "$d" fetch -q ${unshallow:+"$unshallow"} origin "+refs/heads/$ref:refs/remotes/origin/$ref" </dev/null ||
    { echo "migrate: could not fetch $ref into $d; re-run setup when you can reach origin" >&2 && exit 1; }
  if [ -z "$(git -C "$d" branch --show-current)" ]; then
    git -C "$d" switch -q -c "$ref" 2>/dev/null ||
      { echo "migrate: $d already has a branch $ref; git -C $d switch $ref (or delete it), then re-run setup" >&2 && exit 1; }
  fi
  ! git -C "$d" rev-parse -q --verify "refs/heads/$ref" >/dev/null || git -C "$d" branch -q -u "origin/$ref" "$ref"
  git -C "$d" config --unset-all remote.origin.pushurl
  echo "migrate: $d is a full clone on $ref now"
done
