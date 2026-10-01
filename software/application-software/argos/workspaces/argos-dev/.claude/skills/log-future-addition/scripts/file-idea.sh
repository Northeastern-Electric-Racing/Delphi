#!/usr/bin/env bash
# file-idea.sh <repo> <title> <body-file> [<label>...]: file a raw idea as a GitHub issue on a
# workspace repo (repos/<repo>), labelled needs-triage plus any <label>s and assigned to you; print
# its URL. Uses gh when logged in, else (Claude Code remote session) the GitHub REST proxy via
# curl + jq. Exits 3 if neither is available or the request fails (fall back to the GitHub MCP server).
set -euo pipefail
repo=${1:?usage: file-idea.sh <repo> <title> <body-file> [<label>...]} title=${2:?title} body=${3:?body file}
shift 3
root=$(cd "$(dirname "$0")/../../../.." && pwd)
url=$(git -C "$root/repos/$repo" remote get-url origin) && slug=${url#*github.com[:/]} && slug=${slug%.git}
labels=needs-triage
for l in "$@"; do labels="$labels,$l"; done
trap 'echo "file-idea: GitHub request failed; use the GitHub MCP server" >&2; exit 3' ERR

if { command -v gh && gh auth status; } >/dev/null 2>&1; then
  gh issue create -R "$slug" --title "$title" --body-file "$body" --assignee @me --label "$labels"
elif [ -n "${CLAUDE_CODE_REMOTE:-}" ] && command -v curl >/dev/null && command -v jq >/dev/null; then
  me=$(curl -fsS https://api.github.com/user | jq -r .login)
  jq -n --arg t "$title" --rawfile b "$body" --arg l "$labels" --arg me "$me" \
    '{title: $t, body: $b, labels: ($l | split(",")), assignees: [$me]}' |
    curl -fsS -X POST --data-binary @- "https://api.github.com/repos/$slug/issues" | jq -r .html_url
else
  echo "file-idea: no authenticated gh or remote-session proxy; use the GitHub MCP server" >&2 && exit 3
fi
