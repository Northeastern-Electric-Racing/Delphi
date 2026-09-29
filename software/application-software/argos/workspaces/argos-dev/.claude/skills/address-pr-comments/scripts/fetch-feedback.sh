#!/usr/bin/env bash
# fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]: print a PR's review feedback as one JSON
# object, after creating or reusing the PR head's worktree (worktrees/<repo>/<head>). <repo> is a
# workspace repo (repos/<repo>); the PR defaults to the current branch's. Default output keeps
# unresolved threads (reply chains collapsed to first + latest message, bots tagged), conversation
# comments, and reviews with text. --all prints every thread, reply, comment, and review unfiltered.
# Exits 3 if gh is missing or unauthenticated (fall back to the GitHub MCP server).
# shellcheck disable=SC2016 # $vars in single quotes are jq/GraphQL, not shell
set -euo pipefail
all=0
[ "${1:-}" = --all ] && all=1 && shift
repo=${1:?usage: fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]} ref=${2:-}
root=$(cd "$(dirname "$0")/../../../.." && pwd)
if ! { command -v gh && gh auth status; } >/dev/null 2>&1; then
  echo "fetch-feedback: gh missing or not authenticated; use the GitHub MCP server (pull_request_read)" >&2 && exit 3
fi

slug=$(gh repo view "$(git -C "$root/repos/$repo" remote get-url origin)" --json nameWithOwner -q .nameWithOwner)
[ -n "$ref" ] || ref=$(git branch --show-current 2>/dev/null) || true
[ -n "$ref" ] || { echo "fetch-feedback: pass a PR number or branch" >&2; exit 2; }
read -r num head cross < <(gh pr view "$ref" -R "$slug" --json number,headRefName,isCrossRepository \
  -q '"\(.number) \(.headRefName) \(.isCrossRepository)"')
wt=""
[ "$cross" = true ] || wt=$(bash "$root/.delphi/new-worktree.sh" "$repo" "$head")
wt=${wt//\\/\\\\} && wt=${wt//\"/\\\"}

if [ "$all" = 1 ]; then
  filter='.data.repository.pullRequest + {worktree: "'"$wt"'"}'
else
  filter='.data.repository.pullRequest as $p | {
    pr: ($p | {number, title, url, head: .headRefName, base: .baseRefName}), worktree: "'"$wt"'",
    threads: [$p.reviewThreads.nodes[] | select(.isResolved | not) | .comments.nodes as $c | {
      outdated: .isOutdated, path: $c[0].path, line: ($c[0].line // $c[0].originalLine),
      diffHunk: (if .isOutdated then $c[0].diffHunk else null end), replies: ($c | length),
      first: (if ($c | length) > 1 then $c[0].body else null end),
      author: $c[-1].author.login, bot: ($c[-1].author.__typename == "Bot"), body: $c[-1].body}],
    comments: [$p.comments.nodes[] | {author: .author.login, bot: (.author.__typename == "Bot"), body}],
    reviews: [$p.reviews.nodes[] | select(.body != "") | {author: .author.login, state, body}]}'
fi

gh api graphql -F owner="${slug%%/*}" -F name="${slug##*/}" -F num="$num" --jq "$filter" -f query='
query($owner: String!, $name: String!, $num: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $num) {
    number title url headRefName baseRefName
    reviewThreads(first: 100) { nodes { isResolved isOutdated
      comments(first: 50) { nodes { author { login __typename } body path line originalLine diffHunk createdAt } } } }
    comments(first: 100) { nodes { author { login __typename } body createdAt } }
    reviews(first: 100) { nodes { author { login __typename } state body submittedAt } }
  } }
}'
