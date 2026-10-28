---
name: update-pr
description: Update a branch's PR description to reflect the latest changes
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Load the project's `pr-conventions` skill, then rewrite the branch's PR body (`(cd worktrees/<repo>/<branch> && gh pr view)`) to match `git -C worktrees/<repo>/<branch> diff origin/<base>...HEAD`, following the PR body rules in the `open-pr` skill. Keep human-written text that's still accurate, `user-attachments` screenshots, and `Closes`/`Fixes` refs; new screenshots or videos follow open-pr's media step, attached with `gh pr edit --attach`. Write it to `/tmp/<branch>-pr-body.md`, apply it with `gh pr edit <branch> --body-file` from the worktree, and add any of the project's labels that are missing with `--add-label`.
