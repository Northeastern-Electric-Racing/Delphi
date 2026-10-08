---
name: update-pr
description: Update the current branch's PR description to reflect the latest changes
---
Rewrite the current branch's PR body (`gh pr view`) to match `git diff develop...HEAD`. Keep human-written text that's still accurate, `user-attachments` screenshots, and `Closes`/`Fixes` refs. Apply it with `gh pr edit --body-file`, and add any missing written-by or area labels with `--add-label`.

**PR body:** fill `.github/pull_request_template.md` from the diff. Follow each section's comment: Changes in about 50 words. Describe the change, not the file list: don't enumerate components, classes or files the diff already shows. Name a specific one only when its behaviour changes in a way a reviewer must know. Then delete the comments and any optional or non-applicable sections. Check off the Checklist and end with `Closes #{ticket}`. For UI changes put `_screenshot pending_` and remind the user to drag-drop screenshots from `pictures/<branch>/`. Write it to `/tmp/<branch>-pr-body.md`.
