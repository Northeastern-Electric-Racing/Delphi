---
name: update-pr
description: Update the current branch's PR description to reflect the latest changes
---
Rewrite the current branch's PR body (`gh pr view`) to match `git diff origin/develop...HEAD`, following the PR body rules in the `open-pr` skill. Keep human-written text that's still accurate, `user-attachments` screenshots, and `Closes`/`Fixes` refs. Write it to `/tmp/<branch>-pr-body.md` and apply it with `gh pr edit --body-file`.
