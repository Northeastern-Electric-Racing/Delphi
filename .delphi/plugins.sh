#!/usr/bin/env bash
# .delphi/plugins.sh: setup.sh runs it to keep this clone's Delphi plugins in step with this
# workspace, so a plugin change on main reaches everyone on their next setup, switch or pull, with no
# migration of its own. Of the `@delphi` plugins (the Delphi marketplace's; others are only warned
# about), this workspace's generated .claude/settings.json is the list: it installs the ones it
# enables but this clone hasn't (claude plugin install --scope local, for this root), uninstalls this
# root's local installs it doesn't enable (a switch leaves the last workspace's behind, still enabled
# in the git-ignored .claude/settings.local.json), and uninstalls installed ones the marketplace no
# longer has (Claude Code marks them plugin-not-found), at any scope. Other clones' installs and
# user-scope ones the marketplace still has are never touched. It refreshes the marketplace before
# installing or uninstalling what it dropped, only then; if it can't (offline), it does only the
# local uninstalls and warns about the rest. Installed means at user scope, or at project or local
# scope for this root. Says what it did in one line; prints nothing when all is in order or it can't
# tell. Only `harness: claude-code` so far. Finds the workspace from its own place, never by
# searching. Bash 3.2, Git Bash safe.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f workspace.yml ] && [ "$(awk '/^harness:/ { print $2; exit }' workspace.yml)" = claude-code ] || exit 0
command -v claude >/dev/null || exit 0
enabled=$(sed -nE 's/^[[:space:]]*"([^"]+@[^"]+)": true,?$/\1/p' .claude/settings.json 2>/dev/null || true)
root=$(pwd -W 2>/dev/null || pwd) # Git Bash: the Windows path Claude Code records

# `<id> <scope> <gone>` for each plugin installed for this root (gone: 1 if its marketplace lost it)
installed() {
  claude plugin list --json 2>/dev/null | awk -v root="$root" '
    function val(l) { sub(/^[^:]*:[[:space:]]*"/, "", l); sub(/"[^"]*$/, "", l); gsub(/\\\\/, "/", l); return l }
    depth == 1 && /"id":/ { id = val($0); scope = path = ""; gone = 0 }
    depth == 1 && /"scope":/ { scope = val($0) }
    depth == 1 && /"projectPath":/ { path = val($0) }
    /"type":[[:space:]]*"plugin-not-found"/ { gone = 1 }
    { opened = gsub(/\{/, "{"); closed = gsub(/\}/, "}"); depth += opened - closed }
    closed && depth == 0 && id != "" { if (scope == "user" || tolower(path) == tolower(root)) print id, scope, gone; id = "" }'
}
# What's left to do: `install <id>`, `drop <id>` (a local install here this workspace doesn't enable),
# `uninstall <id> <scope>` (gone from the marketplace), `missing <id>` (another marketplace's)
todo() {
  local have
  have=$(installed) || return 1
  for p in $enabled; do
    echo "$have" | awk -v p="$p" '$1 == p { f = 1 } END { exit !f }' && continue
    case $p in *@delphi) echo "install $p" ;; *) echo "missing $p" ;; esac
  done
  echo "$have" | awk -v on=" ${enabled//$'\n'/ } " '$1 ~ /@delphi$/ {
    if ($2 == "local" && !index(on, " " $1 " ")) print "drop", $1; else if ($3 == 1) print "uninstall", $1, $2 }'
}
work=$(todo) || exit 0
[ -n "$work" ] || exit 0
online=""
if echo "$work" | grep -qE '^(un)?install ' && claude plugin marketplace update delphi >/dev/null 2>&1; then
  online=1
  work=$(todo) || exit 0 # again, against the marketplace as it is now
fi
did="" left=""
while read -r verb id scope; do
  case $verb in
    drop) claude plugin uninstall "$id" --scope local >/dev/null 2>&1 &&
      did="$did; uninstalled $id (this workspace doesn't enable it)" || left="$left
drop $id" ;;
    install) [ -n "$online" ] && claude plugin install "$id" --scope local >/dev/null 2>&1 &&
      did="$did; installed $id" || left="$left
missing $id" ;;
    uninstall) [ -n "$online" ] && claude plugin uninstall "$id" --scope "$scope" >/dev/null 2>&1 &&
      did="$did; uninstalled $id (gone from the Delphi marketplace)" || left="$left
uninstall $id" ;;
    *) left="$left
$verb $id" ;;
  esac
done <<<"$work"
[ -z "$did" ] || echo "delphi: plugins: ${did#; }; run /reload-plugins in Claude Code (or restart it) to load the change"
missing=$(echo "$left" | awk '$1 == "missing" || $1 == "install" { print $2 }' | paste -sd " " -)
stale=$(echo "$left" | awk '$1 == "uninstall" { print $2 }' | paste -sd " " -)
extra=$(echo "$left" | awk '$1 == "drop" { print $2 }' | paste -sd " " -)
[ -z "$missing" ] ||
  echo "delphi: this workspace's plugins $missing aren't installed here, so their skills are missing; install each with: claude plugin install <plugin> --scope local"
[ -z "$stale" ] ||
  echo "delphi: plugins $stale are gone from the Delphi marketplace; uninstall each with: claude plugin uninstall <plugin> --scope <its scope>"
[ -z "$extra" ] ||
  echo "delphi: plugins $extra are installed here but this workspace doesn't enable them; uninstall each with: claude plugin uninstall <plugin> --scope local"
