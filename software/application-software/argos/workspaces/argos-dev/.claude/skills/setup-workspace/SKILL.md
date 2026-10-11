---
name: setup-workspace
description: Change what this workspace checks out and re-run its setup. workspace.yml lists code repos (repos:), read-only dependency sources (references-git:), and read-only copies of other Delphi workspaces or main (links:). Use when the user wants to read or compare another workspace's or main's instructions, skills, or docs (link it), add or remove a repo or dependency reference, or run setup after cloning or pulling.
---

`workspace.yml` at the workspace root lists what `.delphi/setup.sh` checks out, all git-ignored: code repos (`repos:`), dependency sources (`references-git:`), and other Delphi workspaces or main (`links:`). The comment on each section gives its entry format and where it lands; read it, then edit the file.

Run from the workspace root after any change, and to refresh references and links to their latest:

```
bash .delphi/setup.sh
```

- Links are for reading: never edit, branch, or push them. To change a linked workspace or main, switch to it (`switch-workspace` skill).
- `linked/main/` holds this workspace's project folder (shared context, `AUTHORING.md`, `defaults/`), the folder above `workspaces/<this-name>/`: `git -C linked/main ls-files '*/workspaces/<this-name>/workspace.yml'`. List workspaces: `git branch -r --list 'origin/ws/*'`.
- `workspace.yml` is shared: change it on a branch and open a PR into `ws/<this-name>`. For a one-off look, add the entry, run setup, then `git restore workspace.yml`.
- Setup never deletes what you'd lose. A removed entry's `linked/<name>/`, `references/<name>/`, or repo store and worktrees stay until you delete them (ask first).
- When Delphi releases a version that needs cleanup in clones, setup runs its migration first (`.delphi/migrations/`), once per workspace. A migration removes only what nothing is lost from, and otherwise stops setup with what to do: tell the user, do it with their go-ahead, and re-run.
