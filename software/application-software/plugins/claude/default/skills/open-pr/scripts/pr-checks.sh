#!/usr/bin/env bash
# pr-checks.sh <workspace-root> <repo> <branch> [<base> [<format>]]: open-pr's shared pre-PR checks on
# worktrees/<repo>/<branch>. Prints
# one PASS/FAIL/SKIP line per check: clean tree, every commit subject since <base> (default
# origin/develop, fetched first) matches <format> (an extended regex, default '^#[0-9]+ - '), and no
# merge conflicts with <base>. Exits 1 if any check fails. The project's own checks (lint, format)
# are in its pr-conventions skill.
set -euo pipefail
usage="usage: pr-checks.sh <workspace-root> <repo> <branch> [<base> [<format>]]"
root=${1:?$usage} repo=${2:?$usage} branch=${3:?$usage}
[ -f "$root/.delphi/paths.sh" ] || { echo "pr-checks: '$root' is not a Delphi workspace root" >&2 && exit 2; }
# shellcheck source=/dev/null
. "$root/.delphi/paths.sh"
cd "$DELPHI_WORKTREES/$repo/$branch"
base=${4:-origin/develop} format=${5:-'^#[0-9]+ - '} fail=0
res() { echo "$1 $2"; [ "$1" != FAIL ] || fail=1; }
git fetch -q origin "${base#origin/}" 2>/dev/null || true

if [ -z "$(git status --porcelain)" ]; then res PASS "clean tree"; else res FAIL "uncommitted changes"; fi
bad=$(git log --format=%s "$base..HEAD" | grep -Ev "$format" || true)
if [ -z "$bad" ]; then res PASS "commit format"; else res FAIL "commit format: $(echo "$bad" | paste -sd'|' -)"; fi
if git merge-tree --write-tree HEAD "$base" >/dev/null 2>&1; then res PASS "merges cleanly into $base"
elif [ $? -eq 1 ]; then res FAIL "conflicts with $base"; else res SKIP "conflict check (needs git 2.38+)"; fi
exit "$fail"
