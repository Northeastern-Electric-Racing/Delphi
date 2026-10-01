---
name: run-local
description: Bring up the local Argos environment for running or testing — Docker backend (right profile for what changed) + Angular client on the next free port. Use whenever you need to actually run the app locally, not just start the frontend.
---

From the ticket's worktree, run `bash <workspace>/.claude/skills/run-local/scripts/find-app.sh`. It prints `client`, `backend`, `scylla` (docker/local), and `free_client_port`.

- `backend=none`: ask the user to start it on the right profile (Local Development in CLAUDE.md).
- `scylla=docker` while `scylla-server/` has changes: flag that the backend is stale.
- `client=none`: start `npx ng serve --port <free_client_port>` in `angular-client/` in the background and wait for "Compiled successfully".

Report the client URL and whether the backend is up.
