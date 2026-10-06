---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request
---
From the branch's worktree, run `bash <workspace>/.claude/skills/open-pr/scripts/pr-checks.sh` (clean tree, commit format, frontend lint if changed, conflicts with `origin/develop`); stop and fix on any FAIL. Then push and run `gh pr create --draft --base develop --head <branch> --title "<concise imperative title>" --body-file /tmp/<branch>-pr-body.md --assignee @me --label "by: <ai|ai-assisted|human>" --label <area>...` (written-by plus area labels: `frontend`, `backend`, `devops`), and report the URL.

**PR body:** fill `.github/pull_request_template.md` from the diff. Follow each section's comment: Changes in about 50 words, then delete the comments and any optional or non-applicable sections. Check off the Checklist and end with `Closes #{ticket}`. For UI changes put `_screenshot pending_` and remind the user to drag-drop screenshots from `pictures/<branch>/`. Write it to `/tmp/<branch>-pr-body.md`.
