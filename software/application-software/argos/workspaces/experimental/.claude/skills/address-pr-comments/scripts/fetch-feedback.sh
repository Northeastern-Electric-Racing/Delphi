#!/usr/bin/env bash
# fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]: print a PR's review feedback as one JSON
# object after creating or reusing the PR head's worktree (worktrees/<repo>/<head>). The PR defaults
# to the current branch's. Default output keeps unresolved threads (first + latest message, bots
# tagged), conversation comments, and reviews with text; --all keeps everything. Exits 3 on any
# GitHub failure (see .claude/scripts/github.sh).
# shellcheck source-path=SCRIPTDIR source=../../../scripts/github.sh
set -euo pipefail
. "$(dirname "$0")/../../../scripts/github.sh"
all=false
[ "${1:-}" = --all ] && all=true && shift
repo=${1:?usage: fetch-feedback.sh [--all] <repo> [<pr-number>|<branch>]} ref=${2:-$(git branch --show-current 2>/dev/null || true)}
[ -n "$ref" ] || { echo "fetch-feedback: pass a PR number or branch" >&2; exit 2; }
gh_init fetch-feedback "$repo"

case "$ref" in *[!0-9]*) get "repos/$SLUG/pulls?state=all&head=${SLUG%%/*}:$ref" | jq '.[0] // error("no PR")' ;;
  *) get "repos/$SLUG/pulls/$ref" ;; esac >"$TMP/pr"
num=$(jq .number "$TMP/pr")
wt=""
[ "$(jq -r .head.repo.full_name "$TMP/pr")" != "$SLUG" ] || wt=$(bash "$ROOT/.delphi/new-worktree.sh" "$repo" "$(jq -r .head.ref "$TMP/pr")")

if [ "$MODE" = gh ]; then # thread state is GraphQL-only; reshape it like the proxy's ccr/review_threads
  # shellcheck disable=SC2016 # GraphQL variables
  gh api graphql -F o="${SLUG%%/*}" -F n="${SLUG##*/}" -F p="$num" -f query='query($o: String!, $n: String!, $p: Int!) {
    repository(owner: $o, name: $n) { pullRequest(number: $p) { reviewThreads(first: 100) { nodes {
      isResolved isOutdated comments(first: 50) { nodes { databaseId } } } } } } }' \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] |
      {resolved: .isResolved, outdated: .isOutdated, comment_ids: [.comments.nodes[].databaseId]}]'
else get "repos/$SLUG/pulls/$num/ccr/review_threads"; fi >"$TMP/th"
get "repos/$SLUG/pulls/$num/comments?per_page=100" >"$TMP/rc"
get "repos/$SLUG/issues/$num/comments?per_page=100" >"$TMP/ic"
get "repos/$SLUG/pulls/$num/reviews?per_page=100" >"$TMP/rv"

jq -n --arg wt "$wt" --argjson all "$all" --slurpfile pr "$TMP/pr" --slurpfile th "$TMP/th" \
  --slurpfile rc "$TMP/rc" --slurpfile ic "$TMP/ic" --slurpfile rv "$TMP/rv" '
  def who: {author: .user.login, bot: (.user.type == "Bot")};
  ($rc[0] | map({key: (.id | tostring), value: (who + {body, path, line: (.line // .original_line), diffHunk: .diff_hunk})}) | from_entries) as $byid |
  {pr: ($pr[0] | {number, title, url: .html_url, head: .head.ref, base: .base.ref}), worktree: $wt,
   threads: [$th[0][] | {resolved, outdated, comments: [.comment_ids[] | $byid[tostring]]}],
   comments: [$ic[0][] | who + {body}], reviews: [$rv[0][] | who + {state, body: (.body // "")}]} |
  if $all then . else
    .threads |= map(select(.resolved | not) | .comments as $c | $c[-1] + {outdated, path: $c[0].path, line: $c[0].line,
      diffHunk: (if .outdated then $c[0].diffHunk else null end), replies: ($c | length),
      first: (if ($c | length) > 1 then $c[0].body else null end)}) |
    .reviews |= map(select(.body != ""))
  end'
