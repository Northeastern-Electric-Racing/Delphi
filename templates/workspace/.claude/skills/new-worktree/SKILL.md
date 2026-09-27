---
name: new-worktree
description: Create or reuse a worktree for a branch of a repo in repos/ (repos/worktrees/<repo>/<branch>). Worktrees are the default way to make or check out any new branch; use this before starting a ticket, reviewing or fixing a PR branch, or any other branch work, unless the user says not to use worktrees.
---

Make every new branch as a worktree, never by branching in `repos/<repo>/`, unless the user explicitly says not to use worktrees. `repos/<repo>/` stays a clean checkout of the default branch.

Run from the workspace root:

```
bash .delphi/new-worktree.sh <repo> <branch> [<base>]
```

An existing branch (local or on origin, e.g. a PR's head) is checked out; anything else is created from `<base>` (default: the repo's default branch). It's safe to re-run. It prints the worktree path: `cd` there and do all work in it.

After the branch merges, remove it with `git -C repos/<repo> worktree remove ../worktrees/<repo>/<branch>`.
