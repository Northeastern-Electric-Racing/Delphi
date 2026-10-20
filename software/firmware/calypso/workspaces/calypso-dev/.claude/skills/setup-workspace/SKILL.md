---
name: setup-workspace
description: Change what this workspace checks out and re-run its setup. workspace.yml lists code repos (repos:), read-only dependency sources (references-git:), and clones of other Delphi workspaces or main to read (workspaces:). Use when the user wants to read or compare another workspace's or main's instructions, skills, or docs (link it), add or remove a repo or dependency reference, or run setup after cloning or pulling.
---

`workspace.yml` at the workspace root lists what `.delphi/setup.sh` checks out, all git-ignored: code repos (`repos:`), dependency sources (`references-git:`), and other Delphi workspaces or main (`workspaces:`, entries `- <name>` or `- main`; a workspace's name is the short names of its folders (each folder's `short-name` file, else its name) and its own folder name, joined by dots, like `s.app.argos.argos-dev`; `bash .delphi/switch.sh --list` lists them). The comment on each section gives its entry format and where it lands; read it, then edit the file.

Run from the workspace root after any change, and to refresh references and workspace copies to their latest:

```
bash .delphi/setup.sh
```

- The clones under `workspaces/` are full clones, each on its branch (`ws/<name>` or `main`) tracking origin, for reading: don't edit, branch, or push them from this workspace. Each setup run switches a clone back to its branch if it was switched away (refused while it has uncommitted changes), pulls it, and runs its own setup, so that workspace's repos and references are under it too (it skips its own `workspaces:`, so they don't chain). To change one of those workspaces or main, work in its own clone or switch to it (`switch-workspace` skill).
- This workspace's project folder (shared context, `AUTHORING.md`, `workspace-defaults/`) is the folder above `workspaces/<leaf>/` in `workspaces/main/` (`bash .delphi/switch.sh --list` prints it): for `s.app.argos.argos-dev`, `workspaces/main/software/application-software/argos/`. List workspaces and their project folders: `bash .delphi/switch.sh --list`.
- `workspace.yml` is shared: change it on a branch and open a PR into `ws/<this-name>` (the `name:` in `workspace.yml`). For a one-off look, add the entry, run setup, then `git restore workspace.yml`.
- Setup never deletes what you'd lose. A removed entry's `workspaces/<name>/`, `references/<name>/`, or repo store and worktrees stay until you delete them (ask first).
- When Delphi releases a version that needs cleanup in clones, setup runs its migration first (`.delphi/migrations/`), once per workspace. A migration removes only what nothing is lost from, and otherwise stops setup with what to do: tell the user, do it with their go-ahead, and re-run.
