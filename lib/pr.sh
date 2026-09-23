# pr.sh — the single path for writing to the Delphi monorepo.
#
#   pr_begin <branch> <start-commit>   temp worktree on <branch> (reset to <start>); sets PR_WT
#   … caller edits files under $PR_WT …
#   pr_commit <subject> [body]         stage everything, commit with provenance trailers
#   pr_finish <title> <body> <force>   confirm, push, open or update the PR
# The user's own Delphi checkout is never touched. Requires provenance.sh (PROV_* resolved).

pr_begin() {
  PR_BRANCH=$1
  make_tmp; PR_WT="$REPLY/wt"
  dgit worktree add --quiet -B "$PR_BRANCH" "$PR_WT" "$2" >/dev/null 2>&1 ||
    die "cannot create branch $PR_BRANCH (is it checked out elsewhere?)"
  defer "git -C $(printf %q "$DELPHI_ROOT") worktree remove --force $(printf %q "$PR_WT")"
  PR_START=$(git -C "$PR_WT" rev-parse HEAD)
}

# pr_commit: returns 1 (without committing) when there is nothing staged.
pr_commit() {
  git -C "$PR_WT" add -A || die "git add failed"
  git -C "$PR_WT" diff --cached --quiet && return 1
  git -C "$PR_WT" commit --quiet -F - <<EOF || die "git commit failed"
$1
${2:+
$2
}
$(provenance_trailers)
EOF
}

pr_has_commits() { [ "$(git -C "$PR_WT" rev-parse HEAD)" != "$PR_START" ]; }

# pr_finish <title> <body> <force: 0|1>
pr_finish() {
  local title=$1 body lease me author num
  body="$2

$(provenance_table)"
  if ! confirm "Push $PR_BRANCH and open/update its PR?"; then
    info "Not pushed. Branch $PR_BRANCH is committed locally in $DELPHI_ROOT."
    return 0
  fi
  if [ "$3" = 1 ]; then
    me=$(gh api user --jq .login 2>/dev/null) || die "gh is not authenticated (run: gh auth login)"
    author=$(cd "$PR_WT" && gh pr list --head "$PR_BRANCH" --state open --json author --jq '.[0].author.login // empty' 2>/dev/null || true)
    [ -z "$author" ] || [ "$author" = "$me" ] || die "open PR on $PR_BRANCH belongs to $author; refusing to overwrite"
    lease=$(dgit ls-remote --heads origin "refs/heads/$PR_BRANCH" | cut -f1)
    git -C "$PR_WT" push --quiet --force-with-lease="refs/heads/$PR_BRANCH:$lease" origin "HEAD:refs/heads/$PR_BRANCH" ||
      die "push failed"
  else
    git -C "$PR_WT" push --quiet origin "HEAD:refs/heads/$PR_BRANCH" || die "push failed"
  fi
  num=$(cd "$PR_WT" && gh pr list --head "$PR_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -n "$num" ]; then
    (cd "$PR_WT" && gh pr edit "$num" --title "$title" --body "$body" >/dev/null) || die "gh pr edit failed"
    info "Updated PR #$num"
  else
    (cd "$PR_WT" && gh pr create --head "$PR_BRANCH" --base main --title "$title" --body "$body") || die "gh pr create failed"
  fi
}
