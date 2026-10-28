---
name: new-worktree
description: Create or reuse a worktree for a branch of a code repo (worktrees/<repo>/<branch>). Use before any branch work, such as starting a ticket or reviewing or fixing a PR branch, unless the user says not to use worktrees.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Run from the workspace root:

```
bash .delphi/new-worktree.sh <repo> <branch> [<base>]
```

- An existing branch (local or on origin, e.g. a PR head) is checked out; anything else is created from `<base>` (default: the repo's default branch). Safe to re-run.
- Stay at the workspace root and reach into the worktree by the printed path. Never switch branches in an existing worktree or work in its store, `worktrees/<repo>/.bare`.
- For a subagent, make its worktree here first and hand it the path. Never use the harness's own worktree isolation: it checks out this Delphi clone from main, not the code repo, and fences the subagent out of `worktrees/`.
- Keep `worktrees/<repo>/<default-branch>/` (made by setup) a clean reference: fetch and fast-forward only.
- After the branch merges: `git -C worktrees/<repo>/.bare worktree remove ../<branch>`.
