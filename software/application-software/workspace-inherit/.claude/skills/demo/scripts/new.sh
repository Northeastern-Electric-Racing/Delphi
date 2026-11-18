#!/usr/bin/env bash
# new.sh <repo> <branch> <name> <route>: start demo <name> of the page at <route> from template.demo.js, next
# to the other demos in <branch>'s worktree of <repo> (or in demos/ at its root), and print its path.
set -euo pipefail
usage='usage: new.sh <repo> <branch> <name> <route>'
repo=${1:?$usage}; branch=${2:?$usage}; name=${3:?$usage}; route=${4:?$usage}
case $name in *[!a-z0-9-]*) echo "new: <name> takes lower-case letters, digits and dashes" >&2; exit 1 ;; esac
case $route in /*) ;; *) echo "new: <route> starts with /" >&2; exit 1 ;; esac
case $route in *[!A-Za-z0-9/_.?=-]*) echo "new: <route> takes letters, digits and / _ . ? = -" >&2; exit 1 ;; esac
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root}/.delphi/paths.sh"
wt=$DELPHI_WORKTREES/$repo/$branch
[ -d "$wt" ] || { echo "new: no worktree at worktrees/$repo/$branch (make it with new-worktree.sh)" >&2; exit 1; }
other=$(git -C "$wt" ls-files -co --exclude-standard -- '*.demo.js' | awk 'NR == 1')
dir=demos; [ -z "$other" ] || dir=$(dirname "$other")
file=$wt/$dir/$name.demo.js
[ ! -e "$file" ] || { echo "new: $file already exists" >&2; exit 1; }
mkdir -p "$wt/$dir"
sed -e "s|{{name}}|$name|g" -e "s|{{route}}|$route|g" "$(dirname "$0")/template.demo.js" >"$file"
echo "$file"
