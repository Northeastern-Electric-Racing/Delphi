---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request
---
From the branch's worktree: stop if the tree is dirty, check that the commits since `origin/develop` follow the commit format, run `clang-format --dry-run --Werror` on the changed C++ files and stop on any error, and check that `origin/develop` merges without conflicts. Then push and run `gh pr create --draft --base develop --head <branch> --title "<concise title>" --body-file /tmp/<branch>-pr-body.md --assignee @me`, and report the URL.

**PR body:** fill `.github/pull_request_template.md` from the diff. Changes gets 1–3 dense sentences on what landed and the key design choice, with no filler. Use at most three backticks in the body. Remove sections that don't apply, check off the Checklist, and end with `Closes #{ticket}`. For UI changes put `_screenshot pending_` and remind the user to drag-drop screenshots from `playwright/test-results/<case>/`. Write it to `/tmp/<branch>-pr-body.md`.
