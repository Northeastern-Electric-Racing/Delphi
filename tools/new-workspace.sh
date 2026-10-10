#!/usr/bin/env bash
# tools/new-workspace.sh <org-path under software/> <name>: propose a new workspace as a PR to main.
# In a temporary worktree of origin/main, copies templates/workspace/ and then, if present, the
# project's software/<org-path>/defaults/ (its CLAUDE.md appended to the template's) to
# software/<org-path>/workspaces/<name>/, sets `name:` in its workspace.yml, checks it, pushes branch new-workspace/<name>, and opens
# the PR with gh. Your checkout is untouched. After merge, ci/sync.sh creates ws/<name>.
set -euo pipefail
die() { echo "new-workspace: $*" >&2 && exit 1; }
[ $# -eq 2 ] || die "usage: tools/new-workspace.sh <org-path under software/> <name>"
org=${1%/}
org=${org#software/}
name=$2
case "$name" in '' | -* | *[!a-z0-9-]*) die "name must be lowercase letters, digits, and '-'" ;; esac
case "/$org/" in // | *//* | */./* | */../* | */workspaces/* | *[!A-Za-z0-9._/-]*) die "bad org path '$1'" ;; esac
cd "$(dirname "$0")/.."

git fetch --quiet --prune origin
! git ls-tree -r --name-only origin/main -- software | grep "/workspaces/$name/workspace\.yml\$" >/dev/null ||
  die "a workspace named '$name' already exists on main"
! git rev-parse --quiet --verify "refs/remotes/origin/ws/$name" >/dev/null ||
  die "branch ws/$name already exists (from a removed workspace?); pick another name"

folder=software/$org/workspaces/$name
branch=new-workspace/$name
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" origin/main
trap 'git worktree remove --force "$wt"' EXIT
defaults=$wt/software/$org/defaults
mkdir -p "$wt/$folder"
cp -R "$wt/templates/workspace/." "$wt/$folder/"
if [ -d "$defaults" ]; then
  cp -R "$defaults/." "$wt/$folder/"
  cp "$wt/templates/workspace/CLAUDE.md" "$wt/$folder/CLAUDE.md"
  [ ! -f "$defaults/CLAUDE.md" ] || { echo && cat "$defaults/CLAUDE.md"; } >>"$wt/$folder/CLAUDE.md"
fi
sed -i.bak -e "s|{{name}}|$name|g" -e "s|{{folder}}|$folder|g" "$wt/$folder/CLAUDE.md" && rm "$wt/$folder/CLAUDE.md.bak"
y=$wt/$folder/workspace.yml
{ echo "name: $name"; grep -v '^name:' "$y"; } >"$y.new" && mv "$y.new" "$y"
"$wt/ci/check.sh" "$wt"
git -C "$wt" add -A "$folder"
git -C "$wt" commit --quiet -m "New workspace $name at $folder"
git -C "$wt" push --quiet origin "HEAD:refs/heads/$branch"
gh pr create --base main --head "$branch" --title "New workspace: $name" --body "Adds \`$folder/\` from templates/workspace (plus \`software/$org/defaults\` if present). Fill in \`workspace.yml\` repos (and list \`main\` under \`links:\`, recommended, so it can read this project's shared context) and \`CLAUDE.md\` before merging; after merge, CI creates branch \`ws/$name\`."
