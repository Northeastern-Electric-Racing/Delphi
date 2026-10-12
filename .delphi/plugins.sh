#!/usr/bin/env bash
# .delphi/plugins.sh [--install]: the plugins this workspace's generated harness settings enable but this
# machine hasn't installed, so their skills are missing. Prints a warning naming them (nothing when all
# are installed, or when it can't tell); setup.sh and each session's start hook run it, so the warning
# reaches the person and the model. --install installs them: Claude Code adds the marketplace the
# settings name if it's new here, then installs each at local scope (recorded in the git-ignored
# .claude/settings.local.json; the generated settings.json is never touched). Only `harness:
# claude-code` so far. Finds the workspace from its own place, never by searching. Bash 3.2, Git Bash safe.
set -euo pipefail
cd "$(dirname "$0")/.."
install=0
[ "${1:-}" != --install ] || install=1
[ -f workspace.yml ] && [ "$(awk '/^harness:/ { print $2; exit }' workspace.yml)" = claude-code ] || exit 0
s=.claude/settings.json
enabled=$(sed -nE 's/^[[:space:]]*"([^"]+@[^"]+)": true,?$/\1/p' "$s" 2>/dev/null || true)
[ -n "$enabled" ] || exit 0
command -v claude >/dev/null || {
  [ "$install" = 0 ] || { echo "delphi: no claude on PATH; in Claude Code, run /plugin install for each of: $(echo "$enabled" | paste -sd " " -)" >&2 && exit 1; }
  exit 0
}
root=$(pwd -W 2>/dev/null || pwd) # Git Bash: the Windows path Claude Code records
# installed for this workspace: at user scope, or project/local scope with this root as its projectPath
installed=$(claude plugin list --json 2>/dev/null | awk -v root="$root" '
  function val(l) { sub(/^[^:]*:[[:space:]]*"/, "", l); sub(/"[^"]*$/, "", l); gsub(/\\\\/, "/", l); return l }
  /"id":/ { id = val($0); scope = path = "" }
  /"scope":/ { scope = val($0) }
  /"projectPath":/ { path = val($0) }
  /^[[:space:]]*}/ && id != "" { if (scope == "user" || tolower(path) == tolower(root)) print id; id = "" }') || exit 0
missing=$(for p in $enabled; do echo "$installed" | grep -qxF "$p" || echo "$p"; done)
[ -n "$missing" ] || exit 0
names=$(echo "$missing" | paste -sd " " -)
if [ "$install" = 0 ]; then
  echo "delphi: this workspace's plugins $names aren't installed here, so their skills are missing." \
    "Install them with the delphi skill (bash .delphi/plugins.sh --install, from the workspace root), then restart the session."
  exit 0
fi
known=$(claude plugin marketplace list --json 2>/dev/null || true)
failed=0
for m in $(for p in $missing; do echo "${p#*@}"; done | sort -u); do
  echo "$known" | grep -qE "\"name\": *\"$m\"" && continue
  repo=$(awk -v m="\"$m\"" '$1 == m":" { s = 1 } s && /"repo":/ { gsub(/[",]/, "", $2); print $2; exit }' "$s")
  if [ -z "$repo" ] || ! claude plugin marketplace add "$repo"; then
    echo "delphi: could not add marketplace $m${repo:+ ($repo)}" >&2 && failed=1
  fi
done
for p in $missing; do
  claude plugin install "$p" --scope local || { echo "delphi: could not install $p" >&2 && failed=1; }
done
[ "$failed" = 1 ] || echo "delphi: installed $names; restart the session to load their skills"
exit "$failed"
