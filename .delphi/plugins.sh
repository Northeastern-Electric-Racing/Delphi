#!/usr/bin/env bash
# .delphi/plugins.sh: setup.sh runs it to warn about the plugins this workspace's generated harness
# settings enable but this machine hasn't installed, so their skills are missing (CLAUDE.md says how to
# install them). Prints nothing when all are installed, or when it can't tell. Only `harness:
# claude-code` so far: installed means at user scope, or at project or local scope for this root.
# Finds the workspace from its own place, never by searching. Bash 3.2, Git Bash safe.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f workspace.yml ] && [ "$(awk '/^harness:/ { print $2; exit }' workspace.yml)" = claude-code ] || exit 0
enabled=$(sed -nE 's/^[[:space:]]*"([^"]+@[^"]+)": true,?$/\1/p' .claude/settings.json 2>/dev/null || true)
[ -n "$enabled" ] && command -v claude >/dev/null || exit 0
root=$(pwd -W 2>/dev/null || pwd) # Git Bash: the Windows path Claude Code records
installed=$(claude plugin list --json 2>/dev/null | awk -v root="$root" '
  function val(l) { sub(/^[^:]*:[[:space:]]*"/, "", l); sub(/"[^"]*$/, "", l); gsub(/\\\\/, "/", l); return l }
  /"id":/ { id = val($0); scope = path = "" }
  /"scope":/ { scope = val($0) }
  /"projectPath":/ { path = val($0) }
  /^[[:space:]]*}/ && id != "" { if (scope == "user" || tolower(path) == tolower(root)) print id; id = "" }') || exit 0
missing=$(for p in $enabled; do echo "$installed" | grep -qxF "$p" || echo "$p"; done | paste -sd " " -)
[ -z "$missing" ] ||
  echo "delphi: this workspace's plugins $missing aren't installed here, so their skills are missing; install each with: claude plugin install <plugin> --scope local"
