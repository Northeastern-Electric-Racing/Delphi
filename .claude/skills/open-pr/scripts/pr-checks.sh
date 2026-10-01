#!/usr/bin/env bash
# pr-checks.sh [<base>]: pre-PR checks for open-pr, run from the branch's worktree. Prints one
# PASS/FAIL/SKIP line per check: clean tree, commit subjects match "#<ticket> - ...", frontend
# prettier + ng lint (only if angular-client/ changed), and no merge conflicts with <base>
# (default origin/develop, fetched first). Exits 1 if any check fails.
set -euo pipefail
base=${1:-origin/develop} fail=0
res() { echo "$1 $2"; [ "$1" != FAIL ] || fail=1; }
git fetch -q origin "${base#origin/}" 2>/dev/null || true

if [ -z "$(git status --porcelain)" ]; then res PASS "clean tree"; else res FAIL "uncommitted changes"; fi
bad=$(git log --format=%s "$base..HEAD" | grep -Ev '^#[0-9]+ - ' || true)
if [ -z "$bad" ]; then res PASS "commit format"; else res FAIL "commit format: $(echo "$bad" | paste -sd'|' -)"; fi
if git diff --quiet "$base...HEAD" -- angular-client; then res SKIP "frontend lint (no changes)"
elif [ ! -d angular-client/node_modules ]; then res FAIL "frontend lint: run npm ci in angular-client/"
elif (cd angular-client && npx prettier --check "src/**/*.{ts,html,scss}" >/dev/null && npx ng lint >/dev/null 2>&1)
then res PASS "frontend lint"; else res FAIL "frontend lint (run prettier --check / ng lint to see why)"; fi
if git merge-tree --write-tree HEAD "$base" >/dev/null 2>&1; then res PASS "merges cleanly into $base"
elif [ $? -eq 1 ]; then res FAIL "conflicts with $base"; else res SKIP "conflict check (needs git 2.38+)"; fi
exit "$fail"
