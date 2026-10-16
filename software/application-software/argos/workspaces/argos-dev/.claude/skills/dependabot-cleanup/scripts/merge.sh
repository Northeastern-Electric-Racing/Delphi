#!/usr/bin/env bash
# merge.sh <pr>...: for each Dependabot PR in turn, approve it as you, wait for CI, and merge it
# (merge commit). Waits out GitHub's UNKNOWN mergeability after the previous merge. Prints one line
# per PR: merged, or blocked <why>; exits 1 if any is blocked.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
[ $# -gt 0 ] || { echo "usage: merge.sh <pr>..." >&2 && exit 2; }
rc=0
for pr in "$@"; do
  blocked() { echo "#$pr blocked: $1" && rc=1; }
  author=$(gh pr view "$pr" -R "$R" --json author -q .author.login)
  case $author in *dependabot*) ;; *) blocked "author is $author, not Dependabot" && continue ;; esac
  gh pr review "$pr" -R "$R" --approve -b "Validated locally (dependabot-cleanup)." >/dev/null 2>&1 || true
  if ! gh pr checks "$pr" -R "$R" --watch --fail-fast >/dev/null 2>&1; then blocked "CI failing (ci.sh $pr)" && continue; fi
  state=UNKNOWN
  for _ in $(seq 20); do
    state=$(gh pr view "$pr" -R "$R" --json mergeable -q .mergeable)
    [ "$state" = UNKNOWN ] || break
    sleep 5
  done
  case $state in
    MERGEABLE) if out=$(gh pr merge "$pr" -R "$R" --merge 2>&1); then echo "#$pr merged"; else blocked "${out##*$'\n'}"; fi ;;
    CONFLICTING) blocked "conflicts with develop (rebase.sh $pr)" ;;
    *) blocked "mergeable still $state" ;;
  esac
done
exit $rc
