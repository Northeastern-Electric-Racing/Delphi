#!/usr/bin/env bash
# aglint.sh <branch>: Argos's AGLint check, from the root of worktrees/argos/<branch>. Runs
# `aglint check --fast` once over every subproject with an .aglint/ (angular-client, scylla-server),
# skipping those the branch doesn't touch, and exits with the combined code: 0 PASS, 4 WARN, 1 FAIL,
# 2 config error, 3 internal error. Prints nothing and exits 0 when aglint isn't on PATH or no
# subproject has an .aglint/ (AGLint is private and not on develop yet).
set -euo pipefail
usage="usage: aglint.sh <branch>"
branch=${1:?$usage}
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root, on Delphi 0.2.0+ (pull its ws/ branch), or source <root>/.delphi/paths.sh}/.delphi/paths.sh"
cd "$DELPHI_WORKTREES/argos/$branch"
if ! command -v aglint >/dev/null || ! compgen -G '*/.aglint/config.yml' >/dev/null; then exit 0; fi
exec aglint check --fast
