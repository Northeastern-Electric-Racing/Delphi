# github.sh: sourced by skill scripts that call GitHub. gh_init <tool> <git-dir> picks a backend
# (gh when logged in, else an explicitly enabled GitHub REST proxy via curl; jq is needed either
# way), sets SLUG from that repo's origin, and makes any failure exit 3 so the calling skill falls
# back to the available GitHub integration. TMP is a scratch dir removed on exit.
# shellcheck shell=bash
fail() { echo "$TOOL: $1; use the available GitHub integration" >&2; exit 3; }
on_exit() { local rc=$?; rm -rf "$TMP"; [ "$rc" -eq 0 ] || fail "GitHub request failed ($MODE)"; }
gh_init() {
  TOOL=$1
  if { command -v gh && gh auth status; } >/dev/null 2>&1; then MODE=gh
  elif [ -n "${DELPHI_GITHUB_REST_PROXY:-${CLAUDE_CODE_REMOTE:-}}" ] && command -v curl >/dev/null; then MODE=rest
  else fail "no authenticated gh or enabled REST proxy"; fi
  command -v jq >/dev/null || fail "jq not installed"
  SLUG=$(git -C "$2" remote get-url origin) && SLUG=${SLUG#*github.com[:/]} && SLUG=${SLUG%.git}
  TMP=$(mktemp -d)
  trap on_exit EXIT
}
get() { if [ "$MODE" = gh ]; then gh api "$1"; else curl -fsS "https://api.github.com/$1"; fi; }
post() { if [ "$MODE" = gh ]; then gh api -X POST "$1" --input -; else curl -fsS -X POST --data-binary @- "https://api.github.com/$1"; fi; }
