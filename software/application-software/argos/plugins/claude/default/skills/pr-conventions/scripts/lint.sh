#!/usr/bin/env bash
# lint.sh <branch> [<base>]: Argos's pre-PR check for open-pr, on
# worktrees/argos/<branch>. Prints one PASS/FAIL/SKIP line: frontend prettier + ng lint, only if
# angular-client/ changed since <base> (default origin/develop). Exits 1 if it fails.
set -euo pipefail
usage="usage: lint.sh <branch> [<base>]"
branch=${1:?$usage}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root, on Delphi 0.2.0+ (pull its ws/ branch), or source <root>/.delphi/paths.sh}/.delphi/paths.sh"
cd "$DELPHI_WORKTREES/argos/$branch"
base=${2:-origin/develop}
if git diff --quiet "$base...HEAD" -- angular-client; then echo "SKIP frontend lint (no changes)"
elif [ ! -d angular-client/node_modules ]; then echo "FAIL frontend lint: run npm ci in angular-client/" && exit 1
elif (cd angular-client && npx prettier --check "src/**/*.{ts,html,scss}" >/dev/null && npx ng lint >/dev/null 2>&1)
then echo "PASS frontend lint"; else echo "FAIL frontend lint (run prettier --check / ng lint to see why)" && exit 1; fi
