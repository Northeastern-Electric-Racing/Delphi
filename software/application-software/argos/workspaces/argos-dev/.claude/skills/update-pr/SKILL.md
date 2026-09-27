---
name: update-pr
description: Update the current branch's PR description to reflect the latest changes
---
Rewrite the current branch's PR body (`gh pr view`) to match `git diff develop...HEAD`. Keep human-written text that's still accurate, `user-attachments` screenshots, and `Closes`/`Fixes` refs. Apply it with `gh pr edit --body-file`.

**PR body:** fill `.github/pull_request_template.md` from the diff. Changes gets 1–3 dense sentences on what landed and the key design choice, with no filler. Remove sections that don't apply, check off the Checklist, and end with `Closes #{ticket}`. For UI changes put `_screenshot pending_` and remind the user to drag-drop screenshots from `pictures/<branch>/`. Write it to `/tmp/<branch>-pr-body.md`.
