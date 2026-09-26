---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request
---

Stop if the working tree is dirty. Check the commits since `develop` follow the commit format, lint the frontend if it changed, and check that `origin/develop` merges without conflicts. Then push and run `gh pr create --draft --base develop --head <branch> --title "#{ticket} title" --body-file /tmp/<branch>-pr-body.md --assignee @me`, and report the URL.

Write the PR body as described in `pr-body.md` (next to this file) before running `gh pr create`.
