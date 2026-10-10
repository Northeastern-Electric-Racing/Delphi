---
name: new-worktree
description: Create or reuse a worktree for a branch of a code repo (worktrees/<repo>/<branch>), for a ticket, a PR branch, or a throwaway experiment.
---

Each code checkout is a worktree under `worktrees/<repo>/<branch>/`, made from the bare store `repos/<repo>`. `.delphi/setup.sh` makes the default branch's; run anything there, but make code changes on a branch of your own.

Run from the workspace root:

```
bash .delphi/new-worktree.sh <repo> <branch> [<base>]
```

An existing branch (local or on origin, e.g. a PR's head) is checked out; anything else is created from `<base>` (default: the repo's default branch). It's safe to re-run and prints the worktree path to work in.

When you're done with a branch, remove it with `git -C repos/<repo> worktree remove ../../worktrees/<repo>/<branch>`.

Argos: pass `origin/develop` as `<base>`. Name the branch `{issue-number}-{kebab-case-title}` for a ticket, or `throwaway-{kebab-case-title}` to try something without one. Run `npm ci` in the worktree's `angular-client/` before building, testing, or running the client.
