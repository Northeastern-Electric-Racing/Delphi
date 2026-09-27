#!/usr/bin/env bash
# tools/new-workspace.sh <org-path under software/> <name>: propose a new workspace as a PR to main.
# Copies templates/workspace/ (as on origin/main) to software/<org-path>/workspaces/<name>/ on a new
# branch new-workspace/<name>, checks it, pushes, and opens the PR with gh. Your checkout is left
# untouched (the work happens in a temporary worktree). ci/sync.sh creates ws/<name> after merge.
set -euo pipefail
die() { echo "new-workspace: $*" >&2 && exit 1; }
[ $# -eq 2 ] || die "usage: tools/new-workspace.sh <org-path under software/> <name>"
org=${1%/}
org=${org#software/}
name=$2
case "$name" in '' | -* | *[!a-z0-9-]*) die "name must be lowercase letters, digits, and '-'" ;; esac
case "/$org/" in // | *//* | */./* | */../* | */workspaces/* | *[!A-Za-z0-9._/-]*) die "bad org path '$1'" ;; esac
cd "$(dirname "$0")/.."

git fetch --quiet origin
git ls-tree -r --name-only origin/main -- software | grep "/workspaces/$name/workspace\.yml\$" >/dev/null &&
  die "a workspace named '$name' already exists on main"
git rev-parse --quiet --verify "refs/remotes/origin/ws/$name" >/dev/null &&
  die "branch ws/$name already exists (from a removed workspace?); pick another name"

folder=software/$org/workspaces/$name
branch=new-workspace/$name
wt=$(mktemp -d)
git worktree add --quiet -b "$branch" "$wt" origin/main
trap 'git worktree remove --force "$wt"' EXIT
mkdir -p "$wt/$folder"
cp -R "$wt/templates/workspace/." "$wt/$folder/"
sed -e "s|{{name}}|$name|g" -e "s|{{folder}}|$folder|g" "$wt/$folder/CLAUDE.md" >"$wt/claude.tmp"
mv "$wt/claude.tmp" "$wt/$folder/CLAUDE.md"
"$wt/ci/check.sh" "$wt"
git -C "$wt" add -A "$folder"
git -C "$wt" commit --quiet -m "New workspace $name at $folder"
git -C "$wt" push --quiet -u origin "$branch"
gh pr create --base main --head "$branch" --title "New workspace: $name" --body "Adds \`$folder/\` from templates/workspace. Fill in \`workspace.yml\` repos and \`CLAUDE.md\` before merging; after merge, CI creates branch \`ws/$name\`."
