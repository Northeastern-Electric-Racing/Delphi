---
name: open-pr
description: Run pre-PR checks, push the branch, and open a draft pull request on an application-software repo (Argos, Nero)
---

First load the project's `pr-conventions` skill (inherited from the project's `workspace-inherit/`) for its base branch, commit format, checks, labels, and screenshots.

1. **Check:** `bash scripts/pr-checks.sh <repo> <branch> origin/<base> '<commit format>'` (clean tree, commit subjects match the project's format, merges cleanly into the base), then the project's own checks. Stop and fix on any FAIL.
2. **Media:** if the diff touches the UI, ask the user whether to add screenshots to the PR, listing any already in the project's screenshot folder for this branch so they can pick those instead of new ones; on no, skip this step. For new ones, use the project's UI QA to take Playwright screenshots of the changed views into its screenshot folder, or, when the change adds or changes an animation, record a short video instead (a browser context with `recordVideo: { dir }` saves a `.webm` when it closes). Images must be under 10 MB; video under 10 MB on a Free plan, 100 MB on a paid one.
3. **Open:** push (`git -C worktrees/<repo>/<branch> push -u origin <branch>`), then run `(cd worktrees/<repo>/<branch> && gh pr create --draft --base <base> --head <branch> --title "<title>" --body-file /tmp/<branch>-pr-body.md --assignee @me)` with the project's labels plus the ticket's category label from `create-ticket`'s Labels (one `--label` each; only spikes and dev work get PRs, never ideas or epics) and one `--attach <file>` per screenshot or video, and report the URL.
4. **Spike:** the PR stays a draft; getting it merged isn't the goal. Once it's checked and working, run `report-spike`.

## PR body

Fill the worktree's `.github/pull_request_template.md` from the diff, following each section's comment, and write it to `/tmp/<branch>-pr-body.md`:

- Title: concise and imperative, no ticket number.
- The Changes section (not the whole body): about 50 words (1–3 sentences) on what landed and the key design choice. Describe the change, not the file list: don't enumerate components, classes or files the diff already shows. Name a specific one only when its behaviour changes in a way a reviewer must know.
- Delete the template's comments and any optional or non-applicable sections, and check off the Checklist.
- At most three backtick uses in the body.
- End with `Closes #{ticket}` (the branch's leading number), or `Spike for #{ticket}` on a spike, which its PR never closes.
- Screenshots and videos: reference each one by its path from the worktree, `![<what it shows>](<path>)`; `--attach` uploads it and rewrites the reference to its `user-attachments` URL. `--attach` needs gh v2.99.0+: if `gh pr create --help` doesn't list it, put `_screenshot pending_` instead and remind the user to drag-drop the files from the screenshot folder. Never commit screenshots or videos.
