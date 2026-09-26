---
name: new-worktree
description: Create or reuse the worktree for a branch in this Delphi workspace (worktrees/<branch>), checking out an existing branch or starting a new one from origin/develop. Use before starting a ticket, reviewing or fixing a PR branch, or whenever work needs its own checkout.
---

Run from the workspace root:

```
bash .claude/skills/new-worktree/scripts/new-worktree.sh <branch>
```

An existing branch (local or on origin, e.g. a PR's head) is checked out; anything else is created from `origin/develop`. New ticket branches follow `{issue-number}-{kebab-case-title}`. It's safe to re-run.

It prints the worktree path: `cd` there and do all work in it. Run `npm ci` in its `angular-client/` before building, testing, or running the client.
