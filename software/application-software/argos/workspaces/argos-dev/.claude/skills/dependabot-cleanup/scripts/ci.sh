#!/usr/bin/env bash
# ci.sh <pr>: why a PR's CI is red. Prints each failing check, the step and first error lines of each failing job
# (gates skipped), how far develop has moved since the PR's base, and develop's latest result per
# workflow. A failure develop shares, or one develop has fixed since, is not the PR's.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
pr=${1:?usage: ci.sh <pr>}
branch=$(pr_branch "$pr")
checks=$(gh pr checks "$pr" -R "$R" --json name,bucket,link -q '.[] | select(.bucket == "fail") | "\(.name)\t\(.link)"' || true)
[ -n "$checks" ] || { echo "#$pr no failing checks" && exit 0; }
while IFS=$'\t' read -r name link; do echo "FAIL $name $link"; done <<<"$checks"
# gate jobs only repeat another job's result, so show the jobs they gate (the rest if all are gates)
jobs=$(grep -v -- $'-gate\t' <<<"$checks" || true) && jobs=${jobs:-$checks}
while IFS=$'\t' read -r name link; do
  echo "--- $name"
  job=${link##*/}
  gh run view -R "$R" --job "$job" --log-failed 2>/dev/null | cut -f3- | sed -E 's/^[0-9T:.-]+Z //' |
    awk '/##\[group\]Run / { step = $0; n = 0; next } /##\[error\]/ { print step; for (i = 0; i < n; i++) print m[i]; print; exit }
         tolower($0) ~ /error|fail|panick/ && $0 !~ /^npm error *$/ && n < 10 { m[n++] = $0 }' | cut -c1-200
done <<<"$jobs"
g() { git -C "$DELPHI_REPOS/argos" "$@"; }
g fetch -q origin develop "$branch"
echo "--- develop is $(g rev-list --count "$(g merge-base origin/develop "origin/$branch")..origin/develop") commits past this PR's base"
gh run list -R "$R" -b develop -L 20 --json workflowName,conclusion \
  -q 'unique_by(.workflowName)[] | "develop \(.workflowName): \(.conclusion)"'
