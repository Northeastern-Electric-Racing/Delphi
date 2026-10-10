---
name: setup-workspace
description: Change what this workspace checks out and re-run its setup. workspace.yml lists code repos (repos:), read-only dependency sources (references-git:), and read-only copies of other Delphi workspaces or main (links:). Use when the user wants to read or compare another workspace's or main's instructions, skills, or docs (link it), add or remove a repo or dependency reference, or run setup after cloning or pulling.
---

`.delphi/setup.sh` checks out what `workspace.yml` lists, all git-ignored:

```yaml
repos:            # code you change: store repos/<name>, default branch at worktrees/<name>/<branch>
  argos: https://github.com/Northeastern-Electric-Racing/Argos.git
references-git:   # dependency sources, read-only, at references/<name>/ (optional tag or branch)
  zenoh: https://github.com/eclipse-zenoh/zenoh.git 1.10.1
links:            # Delphi workspaces or main, read-only, at linked/<name>/
  - main
  - argos-dev
```

Run from the workspace root after any change, and to refresh references and links to their latest:

```
bash .delphi/setup.sh
```

- Links are for reading: never edit, branch, or push them. To change a linked workspace or main, switch to it (`switch-workspace` skill).
- `linked/main/` holds this workspace's project folder (shared context, `AUTHORING.md`, `defaults/`), the folder above `workspaces/<this-name>/`: `git -C linked/main ls-files '*/workspaces/<this-name>/workspace.yml'`. List workspaces: `git branch -r --list 'origin/ws/*'`.
- `workspace.yml` is shared: change it on a branch and open a PR into `ws/<this-name>`. For a one-off look, add the entry, run setup, then `git restore workspace.yml`.
- Setup never deletes. A removed entry's `linked/<name>/`, `references/<name>/`, or repo store and worktrees stay until you delete them (ask first).
