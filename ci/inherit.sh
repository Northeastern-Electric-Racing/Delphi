#!/usr/bin/env bash
# Source this resolver for inheritance at a git revision or on disk. Destination paths are native.
set -euo pipefail
# shellcheck source=ci/harnesses.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harnesses.sh"
inherit_levels() {
  echo "${1%/workspaces/*}" | awk -F/ '{ p = $1; print p; for (i = 2; i <= NF; i++) { p = p "/" $i; print p } }'
}
inherited_files() { # <revision or '' for disk> <workspace folder> <harness>: mode blob<TAB>destination<TAB>source
  local level kind record records meta path dest
  harness "$3" || return 1
  for level in $(inherit_levels "$2"); do
    for kind in workspace-inherit skills; do
      if [ -n "$1" ]; then
        records=$(git ls-tree -r "$1:$level/$kind" 2>/dev/null || true)
      elif [ -d "$level/$kind" ]; then
        records=$(cd "$level/$kind" && find . -type f | awk '{ sub(/^\.\//, ""); print "100644 blob disk\t" $0 }' | sort)
      else records=""; fi
      while IFS= read -r record; do
        [ -n "$record" ] || continue
        meta=${record%%$'\t'*}; path=${record#*$'\t'}
        dest=$(skill_path "$kind" "$path")
        printf '%s %s\t%s\t%s\n' "${meta%% *}" "${meta##* }" "$dest" "$level/$kind/$path"
      done <<<"$records"
    done
  done
}
