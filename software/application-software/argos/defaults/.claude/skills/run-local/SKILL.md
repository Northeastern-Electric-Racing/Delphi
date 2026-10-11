---
name: run-local
description: Bring up the local Argos environment for running or testing — Docker backend (right profile for what changed) + an Angular client per worktree, each on its own free port. Use whenever you need to actually run the app locally, for a PR, a ticket's branch, or develop.
---

Run the branches the user is asking about: a PR or ticket means its branch (make its worktree with `new-worktree` first), and `develop` only when they want current `develop` (fast-forward `worktrees/argos/develop/` first):

```
bash ${CLAUDE_SKILL_DIR}/scripts/run-local.sh ${CLAUDE_PROJECT_DIR} <branch>...
```

It starts the backend if it's down (`client-dev`, or `scylla-dev` plus `cargo run` when a target changes `scylla-server/`), and serves each target's client on the next free port. With only the root it reports what's running.

Report each branch's client URL and the backend. A failed compile or a stale-backend warning is a finding: show it to the user. Stop a client with `kill <pid>` from its line.
