#!/usr/bin/env bash
# Main-side inheritance resolver. Source format and target harness are independent inputs.
set -euo pipefail
# shellcheck source=ci/harnesses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harnesses.sh"
# shellcheck source=ci/sources.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sources.sh"
inherit_levels() {
  echo "${1%/workspaces/*}" | awk -F/ '{ p = $1; print p; for (i = 2; i <= NF; i++) { p = p "/" $i; print p } }'
}
inherited_files() { # <revision or '' for disk> <workspace folder> <harness>: mode blob<TAB>destination<TAB>source
  local level
  harness "$3" || return 1
  for level in $(inherit_levels "$2"); do
    if { [ -n "$1" ] && git cat-file -e "$1:$level/workspace-inherit" 2>/dev/null; } ||
      { [ -z "$1" ] && [ -d "$level/workspace-inherit" ]; }; then
      bundle_files "$1" "$level/workspace-inherit" "$3" || return 1
    fi
  done
}
