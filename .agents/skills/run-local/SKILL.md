---
name: run-local
description: Bring up the local Argos environment for running or testing — Docker backend (right profile for what changed) + an Angular client per worktree, each on its own free port. Use whenever you need to actually run the app locally, for a PR, a ticket's branch, or develop.
---

Run every skill helper through the workspace bootstrap, including in fresh shells and sub-agents:

```sh
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/<script>.sh" <arguments...>
```

Replace the placeholders with the known workspace root, this skill's installed native folder, the script name, and its arguments. Obtain the workspace's absolute path once with `bash .delphi/paths.sh` from the checked-out workspace root. The wrapper sets `DELPHI_ROOT` for every invocation and preserves the caller's working directory; do not assume shell exports persist.


Run the branches the user is asking about: a PR or ticket means its branch (make its worktree with `new-worktree` first), and `develop` only when they want current `develop` (fast-forward `worktrees/argos/develop/` first):

```
bash "<absolute-workspace-root>/.delphi/exec.sh" bash "<absolute-installed-skill-folder>/scripts/run-local.sh" <branch>...
```

It starts the backend if it's down (`client-dev`, or `scylla-dev` plus `cargo run` when a target changes `scylla-server/`), and serves each target's client on the next free port; parallel runs (one per session or agent) each get their own. With no branches it reports what's running.

Report each branch's client URL and the backend. A failed compile or a stale-backend warning is a finding: show it to the user. Stop a client with `kill <pid>` from its line. When every port is taken it lists what holds each; clients from other checkouts are the user's, so ask before stopping them.
