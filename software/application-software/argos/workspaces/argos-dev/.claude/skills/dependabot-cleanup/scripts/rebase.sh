#!/usr/bin/env bash
# rebase.sh <pr>...: ask Dependabot to rebase each PR onto develop, so CI reruns with develop's fixes
# (rerunning a check reuses the old merge commit).
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
[ $# -gt 0 ] || { echo "usage: rebase.sh <pr>..." >&2 && exit 2; }
for pr in "$@"; do gh pr comment "$pr" -R "$R" -b "@dependabot rebase" >/dev/null && echo "#$pr rebase requested"; done
