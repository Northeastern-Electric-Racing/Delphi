---
name: new-worktree
description: Create or reuse a worktree for a branch of a code repo (worktrees/<repo>/<branch>). Use before any branch work, such as starting a ticket or reviewing or fixing a PR branch, unless the user says not to use worktrees.
---

Run from the workspace root:

```
bash .delphi/new-worktree.sh <repo> <branch> [<base>]
```

- An existing branch (local or on origin, e.g. a PR head) is checked out; anything else is created from `<base>` (default: the repo's default branch). Safe to re-run.
- Stay at the workspace root and reach into the worktree by the printed path. Never switch branches in an existing worktree.
- Keep `worktrees/<repo>/<default-branch>/` (made by setup) a clean reference: fetch and fast-forward only.
- After the branch merges: `git -C repos/<repo> worktree remove ../../worktrees/<repo>/<branch>`.
