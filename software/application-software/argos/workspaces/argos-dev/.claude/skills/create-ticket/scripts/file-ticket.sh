#!/usr/bin/env bash
# file-ticket.sh <repo> <type> <title> <body-file> [--parent <n>] <label>...: file an issue with the
# given issue type and labels, assigned to you, optionally as a sub-issue of #<n>; print its URL.
# <repo> is a workspace repo (argos) or owner/name. Exits 2 if a label doesn't exist on the repo,
# 3 on any GitHub failure (see .claude/scripts/github.sh).
# shellcheck source-path=SCRIPTDIR source=../../../scripts/github.sh
set -euo pipefail
. "$(dirname "$0")/../../../scripts/github.sh"
usage="usage: file-ticket.sh <repo> <type> <title> <body-file> [--parent <n>] <label>..."
repo=${1:?$usage} type=${2:?$usage} title=${3:?$usage} body=${4:?$usage}
shift 4
parent=
if [ "${1:-}" = --parent ]; then parent=${2:?$usage}; shift 2; fi
gh_init file-ticket "$repo"
missing=$(get "repos/$SLUG/labels?per_page=100" | jq -r --args '[.[].name] as $have | $ARGS.positional - $have | join(", ")' "$@")
if [ -n "$missing" ]; then
  trap - EXIT; rm -rf "$TMP"
  echo "file-ticket: labels missing on $SLUG: $missing" >&2; exit 2
fi
me=$(get user | jq -r .login)
issue=$(jq -n --arg t "$title" --rawfile b "$body" --arg ty "$type" --arg me "$me" --args \
  '{title: $t, body: $b, type: $ty, labels: $ARGS.positional, assignees: [$me]}' "$@" |
  post "repos/$SLUG/issues")
if [ -n "$parent" ]; then
  jq '{sub_issue_id: .id}' <<<"$issue" | post "repos/$SLUG/issues/$parent/sub_issues" >/dev/null
fi
jq -r .html_url <<<"$issue"
