#!/usr/bin/env bash
# validate.sh <pr>: check a Dependabot PR locally in worktrees/argos/<its branch> (made or reset to
# the PR's head). The diff may only touch manifests, lockfiles and workflows; then it runs CI's
# checks for each folder whose manifest changed: angular-client (npm ci, build, tests, lint,
# prettier) or scylla-server (build, clippy, unit tests; integration tests need Postgres, so CI runs
# them). Prints one line, PASS or FAIL <step>, with its log; exits 1 on FAIL.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
pr=${1:?usage: validate.sh <pr>}
branch=$(pr_branch "$pr")
log=$LOGS/$pr && rm -rf "$log" && mkdir -p "$log"
wt=$(bash "$DELPHI_ROOT/.delphi/new-worktree.sh" argos "$branch")
fail() { echo "#$pr FAIL $1 log=$log${2:+/$2.log}" && exit 1; }
[ -z "$(git -C "$wt" status --porcelain)" ] || fail "worktree has local changes ($wt)"
git -C "$wt" fetch -q origin develop "$branch" && git -C "$wt" reset -q --hard "origin/$branch" # Dependabot force-pushes

files=$(git -C "$wt" diff --name-only origin/develop...HEAD)
other=$(echo "$files" | grep -Ev '(^|/)(package(-lock)?\.json|Cargo\.(toml|lock))$|^\.github/workflows/' || true)
[ -z "$other" ] || fail "scope: touches $(echo "$other" | paste -sd, -)"

run() { # run <step> <dir> <cmd...>: log to $log/<step>.log, fail on error
  local step=$1 dir=$2 && shift 2
  (cd "$wt/$dir" && "$@") >"$log/$step.log" 2>&1 || fail "$step" "$step"
}
ran=""
for dir in $(echo "$files" | grep -E '(package(-lock)?\.json|Cargo\.(toml|lock))$' | xargs -n1 dirname | sort -u); do
  case $dir in
    angular-client)
      run npm-ci "$dir" npm ci
      run ng-build "$dir" npm run build
      run ng-test "$dir" npm run test:ci
      run ng-lint "$dir" npm run lint -- --max-warnings=0
      run prettier "$dir" npm run prettier-check ;;
    scylla-server)
      run cargo-build "$dir" cargo build --locked
      run clippy "$dir" cargo clippy --all-targets --locked
      run cargo-test "$dir" cargo test --locked ;;
    *) run "npm-ci-${dir//\//-}" "$dir" npm ci ;;
  esac
  ran="$ran $dir"
done
echo "#$pr PASS${ran:- scope only (CI checks workflows)} log=$log"
