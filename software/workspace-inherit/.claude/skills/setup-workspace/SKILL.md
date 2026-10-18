---
name: setup-workspace
description: Change what this workspace checks out and re-run its setup. workspace.yml lists code repos (repos:), read-only dependency sources (references-git:), and read-only copies of other Delphi workspaces or main (workspaces:). Use when the user wants to link another workspace or main (a copy under linked/), read or compare its instructions, skills, or docs, add or remove a repo or dependency reference, or run setup after cloning or pulling.
---

`workspace.yml` at the workspace root lists what `.delphi/setup.sh` checks out, all git-ignored: code repos (`repos:`), dependency sources (`references-git:`), and other Delphi workspaces or main (`workspaces:`, entries `- ws/<name>` or `- main`; a workspace's name is its place in the tree, like `software/application-software/argos/argos-dev`). The comment on each section gives its entry format and where it lands; read it, then edit the file.

Run from the workspace root after any change, and to refresh references and workspace copies to their latest:

```
bash .delphi/setup.sh
```

- The copies under `linked/` are for reading: never edit, branch, or push them. To change one of those workspaces or main, switch to it (`switch-workspace` skill).
- This workspace's project folder (shared context, `AUTHORING.md`, `workspace-defaults/`) is `linked/main/` plus this workspace's name without its last part: for `software/application-software/argos/argos-dev`, `linked/main/software/application-software/argos/`. List workspaces: `git branch -r --list 'origin/ws/*'`.
- `workspace.yml` is shared: change it on a branch and open a PR into `ws/<this-name>` (the `name:` in `workspace.yml`). For a one-off look, add the entry, run setup, then `git restore workspace.yml`.
- Setup never deletes what you'd lose. A removed entry's `linked/<branch>/`, `references/<name>/`, or repo store and worktrees stay until you delete them (ask first).
- When Delphi releases a version that needs cleanup in clones, setup runs its migration first (`.delphi/migrations/`), once per workspace. A migration removes only what nothing is lost from, and otherwise stops setup with what to do: tell the user, do it with their go-ahead, and re-run.
