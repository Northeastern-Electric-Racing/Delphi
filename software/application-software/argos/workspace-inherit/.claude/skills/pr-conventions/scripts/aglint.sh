#!/usr/bin/env bash
# aglint.sh <branch>: Argos's AGLint check, on worktrees/argos/<branch>/angular-client. Runs
# `aglint check --fast` (the branch against the base in .aglint/config.yml) and exits with its code:
# 0 PASS, 4 WARN, 1 FAIL, 2 config error, 3 internal error. Prints nothing and exits 0 when aglint
# isn't on PATH or the worktree has no angular-client/.aglint/ (AGLint is private and not on develop yet).
set -euo pipefail
usage="usage: aglint.sh <branch>"
branch=${1:?$usage}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root, on Delphi 0.2.0+ (pull its ws/ branch), or source <root>/.delphi/paths.sh}/.delphi/paths.sh"
cd "$DELPHI_WORKTREES/argos/$branch"
if ! command -v aglint >/dev/null || [ ! -d angular-client/.aglint ]; then exit 0; fi
cd angular-client && exec aglint check --fast
