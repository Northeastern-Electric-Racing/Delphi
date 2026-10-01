---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request
---
From the branch's worktree, run `bash <workspace>/.claude/skills/open-pr/scripts/pr-checks.sh` (clean tree, commit format, frontend lint if changed, conflicts with `origin/develop`); stop and fix on any FAIL. Then push and run `gh pr create --draft --base develop --head <branch> --title "<concise imperative title>" --body-file /tmp/<branch>-pr-body.md --assignee @me`, and report the URL.

**PR body:** fill `.github/pull_request_template.md` from the diff. Changes gets 1–3 dense sentences on what landed and the key design choice, with no filler. Remove sections that don't apply, check off the Checklist, and end with `Closes #{ticket}`. For UI changes put `_screenshot pending_` and remind the user to drag-drop screenshots from `pictures/<branch>/`. Write it to `/tmp/<branch>-pr-body.md`.
