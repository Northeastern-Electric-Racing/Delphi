#!/usr/bin/env bash
# new.sh <repo> <branch> <name> <route> [<app-folder>]: start demo <name> of the page at <route> from
# template.demo.js, in the demos folder of <branch>'s worktree of <repo>, and print its path. The repo's first
# demo makes <app-folder>/demos/ (the folder of the app it shows; `.` for the root). Each goes in
# demos/v<version>/scripts/, <version> being the template's format below, so a demo's format shows in its path.
set -euo pipefail
version=1 # bump when template.demo.js or engine.js changes what a demo file must contain
usage='usage: new.sh <repo> <branch> <name> <route> [<app-folder>]'
repo=${1:?$usage}; branch=${2:?$usage}; name=${3:?$usage}; route=${4:?$usage}; app=${5:-}
case $name in *[!a-z0-9-]*) echo "new: <name> takes lower-case letters, digits and dashes" >&2; exit 1 ;; esac
case $route in /*) ;; *) echo "new: <route> starts with /" >&2; exit 1 ;; esac
case $route in *[!A-Za-z0-9/_.?=-]*) echo "new: <route> takes letters, digits and / _ . ? = -" >&2; exit 1 ;; esac
# shellcheck source=/dev/null
. "${DELPHI_ROOT:?unset: start the session at the workspace root}/.delphi/paths.sh"
wt=$DELPHI_WORKTREES/$repo/$branch
[ -d "$wt" ] || { echo "new: no worktree at worktrees/$repo/$branch (make it with new-worktree.sh)" >&2; exit 1; }
other=$(git -C "$wt" ls-files -co --exclude-standard -- '*.demo.js' | awk 'NR == 1')
if [ -n "$other" ]; then dir=$(dirname "$other" | sed 's|/v[0-9][0-9]*/scripts$||')
elif [ -n "$app" ] && [ -d "$wt/$app" ]; then dir=${app%/}/demos; dir=${dir#./}
else echo "new: the first demo needs <app-folder>, the folder in $repo of the app it shows" >&2; exit 1; fi
dir=$dir/v$version/scripts
file=$wt/$dir/$name.demo.js
[ ! -e "$file" ] || { echo "new: $file already exists" >&2; exit 1; }
mkdir -p "$wt/$dir"
sed -e "s|{{name}}|$name|g" -e "s|{{route}}|$route|g" "$(dirname "$0")/template.demo.js" >"$file"
echo "$file"
