---
name: update-pr
description: Update the current branch's PR description to reflect the latest changes
---

Rewrite the current branch's PR body (`gh pr view`) to match `git diff develop...HEAD`. Keep human-written text that's still accurate, `user-attachments` screenshots, and `Closes`/`Fixes` refs. Apply it with `gh pr edit --body-file`.

Write the new body as described in `pr-body.md` (next to this file).
