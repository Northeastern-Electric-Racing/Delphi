#!/usr/bin/env bash
# tools/new-workspace.sh [--by ai|ai-assisted|human] <org-path under software/> <name>: propose a new
# workspace as a PR to main, labelled `by: <who>` (default ai: who wrote it, as the PR template asks).
# In a temporary worktree of origin/main, copies templates/workspace/ and then, if present, the
# project's software/<org-path>/workspace-defaults/ (its CLAUDE.md appended to the template's) to
# software/<org-path>/workspaces/<name>/, sets `name:` in its workspace.yml to its place in the tree
# (software/<org-path>/<name>; the workspace-inherit/ folders above it reach ws/<name> on each sync), lists its default plugin sets and generates its .claude/settings.json (ci/plugins.sh), checks it, pushes branch new-workspace/<org-path>/<name>, and opens
# the PR with gh. Your checkout is untouched. After merge, ci/sync.sh creates ws/software/<org-path>/<name>.
set -euo pipefail
die() { echo "new-workspace: $*" >&2 && exit 1; }
by=ai
[ "${1:-}" != --by ] || { by=${2:-} && shift 2; }
case "$by" in ai | ai-assisted | human) ;; *) die "--by must be ai, ai-assisted or human" ;; esac
[ $# -eq 2 ] || die "usage: tools/new-workspace.sh [--by ai|ai-assisted|human] <org-path under software/> <name>"
org=${1%/}
org=${org#software/}
name=$2
case "$name" in '' | -* | *[!a-z0-9-]*) die "name must be lowercase letters, digits, and '-'" ;; esac
case "/$org/" in // | *//* | */./* | */../* | */workspaces/* | *[!a-z0-9/-]*) die "bad org path '$1' (lowercase letters, digits, '-' and '/')" ;; esac
cd "$(dirname "$0")/.."

git fetch --quiet --prune origin
id=software/$org/$name
! git cat-file -e "origin/main:software/$org/workspaces/$name" 2>/dev/null ||
  die "workspace $id already exists on main"
for b in "ws/$id" "ws/$name"; do # ws/<name>: a workspace's branch before they were named by path, which sync would carry over
  ! git rev-parse --quiet --verify "refs/remotes/origin/$b" >/dev/null || die "branch $b already exists (from a removed workspace?); pick another name"
done

folder=software/$org/workspaces/$name
branch=new-workspace/$org/$name
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" origin/main
trap 'git worktree remove --force "$wt"' EXIT
defaults=$wt/software/$org/workspace-defaults
mkdir -p "$wt/$folder"
cp -R "$wt/templates/workspace/." "$wt/$folder/"
if [ -d "$defaults" ]; then
  cp -R "$defaults/." "$wt/$folder/"
  cp "$wt/templates/workspace/CLAUDE.md" "$wt/$folder/CLAUDE.md"
  [ ! -f "$defaults/CLAUDE.md" ] || { echo && cat "$defaults/CLAUDE.md"; } >>"$wt/$folder/CLAUDE.md"
fi
sed -i.bak -e "s|{{name}}|$id|g" -e "s|{{folder}}|$folder|g" "$wt/$folder/CLAUDE.md" && rm "$wt/$folder/CLAUDE.md.bak"
y=$wt/$folder/workspace.yml
{ echo "name: $id"; grep -v '^name:' "$y"; } >"$y.new" && mv "$y.new" "$y"
bash "$wt/ci/plugins.sh" "$wt" >/dev/null # its plugins: defaults and .claude/settings.json
"$wt/ci/check.sh" "$wt"
git -C "$wt" add -A "$folder"
git -C "$wt" commit --quiet -m "New workspace $id"
git -C "$wt" push --quiet origin "HEAD:refs/heads/$branch"
gh pr create --base main --head "$branch" --title "Add workspace $id" --label "by: $by" --body "## Changes

Adds \`$folder/\` from templates/workspace (plus software/$org/workspace-defaults if present). After merge, CI creates branch ws/$id.

## Testing

- ci/check.sh on the new folder

## Notes

Before merging, fill in its workspace.yml repos (and list main under workspaces:, recommended, so it can read this project's shared context) and its CLAUDE.md.

## Checklist

- [x] \`ci/check.sh .\` passes
- [x] No merge conflicts
- [ ] Request reviewers & ping on Slack"
