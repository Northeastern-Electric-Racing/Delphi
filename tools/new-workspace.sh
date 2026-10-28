#!/usr/bin/env bash
# tools/new-workspace.sh [--by ai|ai-assisted|human] [--harness <adapter>] <org-path> <leaf>:
# prepare a main-side PR with owned native defaults; CI adds inheritance on the workspace branch.
# Uses a temporary checkout of origin/main; never changes the caller's checkout.
set -euo pipefail
die() { echo "new-workspace: $*" >&2 && exit 1; }
by=ai
adapter=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --by) [ "$#" -ge 2 ] || die "--by needs a value"; by=$2; shift 2 ;;
    --harness) [ "$#" -ge 2 ] || die "--harness needs a value"; adapter=$2; shift 2 ;;
    *) break ;;
  esac
done
case "$by" in ai | ai-assisted | human) ;; *) die "--by must be ai, ai-assisted or human" ;; esac
[ $# -eq 2 ] || die "usage: tools/new-workspace.sh [--by ai|ai-assisted|human] [--harness <adapter>] <org-path under software/> <leaf>"
org=${1%/}
org=${org#software/}
leaf=$2
case "$leaf" in '' | -* | *[!a-z0-9-]*) die "leaf must be lowercase letters, digits, and '-'" ;; esac
case "/$org/" in // | *//* | */./* | */../* | */workspaces/* | *[!a-z0-9/-]*) die "bad org path '$1' (lowercase letters, digits, '-' and '/')" ;; esac
cd "$(dirname "$0")/.."

folder=software/$org/workspaces/$leaf
branch=new-workspace/$org/$leaf
git fetch --quiet --prune origin
wt=$(mktemp -d)
git worktree add --quiet --detach "$wt" origin/main
trap 'git worktree remove --force "$wt"' EXIT
defaults=$wt/software/$org/workspace-defaults
[ ! -e "$wt/$folder" ] || die "$folder already exists on main"
mkdir -p "$wt/$folder"
# shellcheck source=ci/inherit.sh
source "$wt/ci/inherit.sh"
[ -n "$adapter" ] || adapter=$(awk '/^harness:/ { print $2; exit }' "$defaults/workspace.yml" 2>/dev/null || true)
harness_exists "${adapter:-claude-code}" || die "unsupported harness"
adapter=${adapter:-claude-code}
instruction=$(harness_field "$adapter" instruction)
instruction_template=$(harness_field "$adapter" instruction_template)
instruction_base=$(harness_field "$adapter" instruction_base)
plugins=$(harness_field "$adapter" plugins)
cp -R "$wt/templates/workspace/." "$wt/$folder/"
for target in $(harnesses); do rm -f "$wt/$folder/$(harness_field "$target" instruction)"; done
mkdir -p "$(dirname "$wt/$folder/$instruction")"
{ [ -z "$instruction_base" ] || cat "$wt/$instruction_base"; cat "$wt/$instruction_template"; } >"$wt/$folder/$instruction"
if [ -d "$defaults" ]; then
  records=$(cd "$wt" && bundle_files "software/$org/workspace-defaults" "$adapter") || die "cannot read project defaults"
  exclusions=''
  [ ! -f "$defaults/workspace.yml" ] || exclusions=$(optouts <"$defaults/workspace.yml")
  inherited=$(cd "$wt" && inherited_files "$folder" "$adapter" "$exclusions") || die "cannot read inherited sources"
  skill_names=$(harness_skill_names "$adapter" "$wt/$folder" "$records"$'\n'"$inherited" "$exclusions")
  while IFS=$'\t' read -r meta path src; do
    [ -n "$path" ] || continue
    if [ "$path" = "$instruction" ]; then
      { echo; cat "$wt/$src"; } >>"$wt/$folder/$instruction"
    else
      mkdir -p "$(dirname "$wt/$folder/$path")"
      harness_file "$adapter" "$wt/$src" "$skill_names" >"$wt/$folder/$path"
      [ "${meta%% *}" != 100755 ] || chmod +x "$wt/$folder/$path"
    fi
  done <<<"$records"
fi
name=$(cd "$wt" && bash .delphi/names.sh | awk -v f="$folder" '$2 == f { print $1 }')
taken=$(cd "$wt" && bash .delphi/names.sh | awk -v n="$name" -v f="$folder" '$1 == n && $2 != f { print $2 }')
[ -z "$taken" ] || die "$taken is already named $name (names are unique); pick another leaf"
for b in "ws/$name" "ws/software/$org/$leaf"; do # ws/software/…: a workspace's branch when they were named by path, which sync would carry over
  ! git rev-parse --quiet --verify "refs/remotes/origin/$b" >/dev/null || die "branch $b already exists (from a removed workspace?); pick another leaf"
done
sed -i.bak -e "s|{{name}}|$name|g" -e "s|{{folder}}|$folder|g" "$wt/$folder/$instruction" && rm "$wt/$folder/$instruction.bak"
y=$wt/$folder/workspace.yml
if [ "$plugins" = none ] && awk '/^plugins:/ { s = 1; next } /^[^[:space:]#]/ { s = 0 }
  s && /^[[:space:]]+-/ { found = 1 } END { exit !found }' "$y"; then
  die "$adapter does not support Delphi plugin sets in project defaults"
fi
{ echo "name: $name"; echo "harness: $adapter"; awk -v plugins="$plugins" '/^name:|^harness:/ { next } plugins == "none" && /^plugins:/ { skip = 1; next } /^[^[:space:]#]/ { skip = 0 } !skip { print }' "$y"; } >"$y.new" && mv "$y.new" "$y"
bash "$wt/ci/render.sh" "$wt"
"$wt/ci/check.sh" "$wt"
git -C "$wt" add -A "$folder"
git -C "$wt" commit --quiet -m "New workspace $name"
git -C "$wt" push --quiet origin "HEAD:refs/heads/$branch"
gh pr create --base main --head "$branch" --title "Add workspace $name" --label "by: $by" --body "## Changes

Adds \`$folder/\` from templates/workspace (plus translated project defaults). After merge, CI creates branch ws/$name with its inherited context.

## Testing

- ci/check.sh on the new folder

## Notes

Before merging, fill in its workspace.yml repos (and list main under workspaces:, recommended, so it can read this project's shared context) and its $instruction.

## Checklist

- [x] \`ci/check.sh .\` passes
- [x] No merge conflicts
- [ ] Request reviewers & ping on Slack"
