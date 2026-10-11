---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request on an application-software repo (Argos, Nero)
---

First load the project's `pr-conventions` skill (from the project's plugin) for its base branch, commit format, checks, labels, and screenshots.

1. **Check** from the workspace root: `bash ${CLAUDE_SKILL_DIR}/scripts/pr-checks.sh worktrees/<repo>/<branch> origin/<base> '<commit format>'` (clean tree, commit subjects match the project's format, merges cleanly into the base), then the project's own checks. Stop and fix on any FAIL.
2. **Open:** push (`git -C worktrees/<repo>/<branch> push -u origin <branch>`), then run `(cd worktrees/<repo>/<branch> && gh pr create --draft --base <base> --head <branch> --title "<title>" --body-file /tmp/<branch>-pr-body.md --assignee @me)` with the project's labels (`--label`), and report the URL.

## PR body

Fill the worktree's `.github/pull_request_template.md` from the diff, following each section's comment, and write it to `/tmp/<branch>-pr-body.md`:

- Title: concise and imperative, no ticket number.
- The Changes section (not the whole body): about 50 words (1–3 sentences) on what landed and the key design choice. Describe the change, not the file list: don't enumerate components, classes or files the diff already shows. Name a specific one only when its behaviour changes in a way a reviewer must know.
- Delete the template's comments and any optional or non-applicable sections, and check off the Checklist.
- At most three backtick uses in the body.
- End with `Closes #{ticket}` (the branch's leading number).
- UI changes: put `_screenshot pending_` and remind the user to drag-drop the shots from the project's screenshot folder. Never commit screenshots.
