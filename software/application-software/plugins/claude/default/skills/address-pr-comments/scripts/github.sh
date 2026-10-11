# github.sh: sourced by skill scripts that call GitHub. gh_init <tool> <repo> picks
# a backend (gh when logged in, else a Claude Code remote session's REST proxy via curl; jq is
# needed either way), sets SLUG from repos/<repo>'s origin, and makes any failure exit 3 so the
# calling skill falls back to the GitHub MCP server. ROOT is the workspace root (the nearest folder
# up from the current one with a workspace.yml); TMP is a scratch dir removed on exit.
# shellcheck shell=bash
ROOT=$PWD
while [ ! -f "$ROOT/workspace.yml" ] && [ "$ROOT" != / ]; do ROOT=$(dirname "$ROOT"); done
[ -f "$ROOT/workspace.yml" ] || { echo "github.sh: run from inside a Delphi workspace" >&2; exit 2; }
fail() { echo "$TOOL: $1; use the GitHub MCP server" >&2; exit 3; }
on_exit() { local rc=$?; rm -rf "$TMP"; [ "$rc" -eq 0 ] || fail "GitHub request failed ($MODE)"; }
gh_init() {
  TOOL=$1
  if { command -v gh && gh auth status; } >/dev/null 2>&1; then MODE=gh
  elif [ -n "${CLAUDE_CODE_REMOTE:-}" ] && command -v curl >/dev/null; then MODE=rest
  else fail "no authenticated gh or remote-session proxy"; fi
  command -v jq >/dev/null || fail "jq not installed"
  SLUG=$(git -C "$ROOT/repos/$2" remote get-url origin) && SLUG=${SLUG#*github.com[:/]} && SLUG=${SLUG%.git}
  TMP=$(mktemp -d)
  trap on_exit EXIT
}
get() { if [ "$MODE" = gh ]; then gh api "$1"; else curl -fsS "https://api.github.com/$1"; fi; }
post() { if [ "$MODE" = gh ]; then gh api -X POST "$1" --input -; else curl -fsS -X POST --data-binary @- "https://api.github.com/$1"; fi; }
