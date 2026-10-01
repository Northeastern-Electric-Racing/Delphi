---
name: new-worktree
description: Create or reuse a worktree for a branch of a code repo (worktrees/<repo>/<branch>). Use before any branch work, such as starting a ticket or reviewing or fixing a PR branch, unless the user says not to use worktrees.
---

Run from the workspace root:

```
bash .delphi/new-worktree.sh <repo> <branch> [<base>]
```

- An existing branch (local or on origin, e.g. a PR head) is checked out; anything else is created from `<base>` (default: the repo's default branch). Safe to re-run.
- `cd` into the printed path and do all work there. Never switch branches in an existing worktree or work in the bare store `repos/<repo>`.
- Keep `worktrees/<repo>/<default-branch>/` a clean reference: fetch and fast-forward only.
- After the branch merges: `git -C repos/<repo> worktree remove ../../worktrees/<repo>/<branch>`.
