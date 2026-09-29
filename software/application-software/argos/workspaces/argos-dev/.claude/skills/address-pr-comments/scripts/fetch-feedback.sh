#!/usr/bin/env bash
# fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]: print a PR's review feedback as one JSON
# object, after creating or reusing the PR head's worktree (worktrees/<repo>/<head>). <repo> is a
# workspace repo (repos/<repo>); the PR defaults to the current branch's. Default output keeps
# unresolved threads (reply chains collapsed to first + latest message, bots tagged), conversation
# comments, and reviews with text. --all prints every thread, reply, comment, and review unfiltered.
# Uses gh (GraphQL) when authenticated; in a Claude Code remote session without gh, uses the
# session's GitHub REST proxy via curl + jq. Exits 3 if neither is available or a fetch fails, so
# the caller falls back to the GitHub MCP server.
# shellcheck disable=SC2016 # $vars in single quotes are jq/GraphQL, not shell
set -euo pipefail
all=0
[ "${1:-}" = --all ] && all=1 && shift
repo=${1:?usage: fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]} ref=${2:-}
root=$(cd "$(dirname "$0")/../../../.." && pwd)
if { command -v gh && gh auth status; } >/dev/null 2>&1; then mode=gh
elif [ -n "${CLAUDE_CODE_REMOTE:-}" ] && command -v curl >/dev/null && command -v jq >/dev/null; then mode=rest
else echo "fetch-feedback: no authenticated gh or remote-session proxy; use the GitHub MCP server" >&2 && exit 3
fi
trap 'echo "fetch-feedback: GitHub fetch failed ($mode); use the GitHub MCP server" >&2; exit 3' ERR

url=$(git -C "$root/repos/$repo" remote get-url origin)
slug=${url#*github.com[:/]} && slug=${slug%.git}
[ -n "$ref" ] || ref=$(git branch --show-current 2>/dev/null) || true
[ -n "$ref" ] || { echo "fetch-feedback: pass a PR number or branch" >&2; exit 2; }
api() { curl -fsS "https://api.github.com/repos/$slug/$1"; }
if [ "$mode" = gh ]; then
  read -r num head cross < <(gh pr view "$ref" -R "$slug" --json number,headRefName,isCrossRepository \
    -q '"\(.number) \(.headRefName) \(.isCrossRepository)"')
else
  case "$ref" in *[!0-9]*) ref=$(api "pulls?state=all&head=${slug%%/*}:$ref" | jq -r '.[0].number // empty')
    [ -n "$ref" ] || { echo "fetch-feedback: no PR for that branch" >&2; exit 2; } ;; esac
  read -r num head cross < <(api "pulls/$ref" | jq -r --arg s "$slug" '"\(.number) \(.head.ref) \(.head.repo.full_name != $s)"')
fi
[ -n "${num:-}" ] || false
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

if [ "$mode" = gh ]; then
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
  exit
fi
# REST: rebuild the GraphQL shape from the proxy's review_threads plus the plain comment/review lists.
tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
api "pulls/$num" >"$tmp/pr" && api "pulls/$num/ccr/review_threads" >"$tmp/th"
api "pulls/$num/comments?per_page=100" >"$tmp/rc" && api "issues/$num/comments?per_page=100" >"$tmp/ic"
api "pulls/$num/reviews?per_page=100" >"$tmp/rv"
jq -n --slurpfile pr "$tmp/pr" --slurpfile th "$tmp/th" --slurpfile rc "$tmp/rc" --slurpfile ic "$tmp/ic" \
  --slurpfile rv "$tmp/rv" '
  def who: {login: .user.login, __typename: (if .user.type == "Bot" then "Bot" else "User" end)};
  $pr[0] as $p | {data: {repository: {pullRequest: {
    number: $p.number, title: $p.title, url: $p.html_url, headRefName: $p.head.ref, baseRefName: $p.base.ref,
    reviewThreads: {nodes: [$th[0][] | {isResolved: .resolved, isOutdated: .outdated, comments: {nodes:
      [.comment_ids[] as $id | $rc[0][] | select(.id == $id) | {author: who, body, path, line,
        originalLine: .original_line, diffHunk: .diff_hunk, createdAt: .created_at}]}}]},
    comments: {nodes: [$ic[0][] | {author: who, body, createdAt: .created_at}]},
    reviews: {nodes: [$rv[0][] | {author: who, state, body: (.body // ""), submittedAt: .submitted_at}]}}}}}' |
  jq "$filter"
